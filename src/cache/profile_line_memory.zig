const std = @import("std");

const hashing = @import("../common/hashing.zig");
const spline = @import("../common/math/spline.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const CostTiming = @import("../instrumentation/cost_timing.zig");

const Allocator = std.mem.Allocator;
const max_spectroscopy_profile_nodes: usize = 64;

// profile_line_memory.zig ------------------------------------------------------------------------------------|
// Retained O2 line cross-section rows and support-profile sigma ownership.                                    |
//                                                                                                             |
// ownership                                                                                                   |
//   ProfileLineValues owns wavelength-major diagnostic rows and support-profile total-sigma columns. Build    |
//   code lives in profile_line_build.zig; hot-path readers use this module to borrow retained rows only.      |
// ------------------------------------------------------------------------------------------------------------|

// ProfileLineValue -------------------------------------------------------------------------------------------|
// One line-spectroscopy value at a single exact wavelength and layer profile node.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                     : f64                                                            |
// [ 8..11] layer_index                       : u32                                                            |
// [12..15] interval_index_1based             : u32                                                            |
// [16..23] pressure_hpa                      : f64                                                            |
// [24..31] temperature_k                     : f64                                                            |
// [32..39] weak_line_sigma_cm2_per_molecule  : f64                                                            |
// [40..47] strong_line_sigma_cm2_per_molecule: f64                                                            |
// [48..55] line_sigma_cm2_per_molecule       : f64                                                            |
// [56..63] line_mixing_sigma_cm2_per_molecule: f64                                                            |
// [64..71] total_sigma_cm2_per_molecule      : f64                                                            |
// [72..79] d_sigma_d_temperature_cm2_per_molecule_per_k : f64                                                 |
pub const ProfileLineValue = struct {
    wavelength_nm: f64,
    layer_index: u32,
    interval_index_1based: u32,
    pressure_hpa: f64,
    temperature_k: f64,
    weak_line_sigma_cm2_per_molecule: f64,
    strong_line_sigma_cm2_per_molecule: f64,
    line_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
    d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// ProfileLineValues ------------------------------------------------------------------------------------------|
// Owner for wavelength-major layer-node rows and support-profile total-sigma columns.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] values                    : []ProfileLineValue                                                     |
// [16..31] support_profile_total_sigma_cm2_per_molecule: []f64                                                |
// [32..39] wavelength_count          : usize                                                                  |
// [40..47] profile_node_count        : usize                                                                  |
// [48..55] support_profile_node_count: usize                                                                  |
// [56..63] reuse_stamp               : ReuseStamp                                                             |
//                                                                                                             |
// referenced storage                                                                                          |
//   values owns wavelength_count * profile_node_count diagnostic rows. support_profile_total_sigma owns one   |
//   f64 column indexed as wavelength-major, then support-profile node. Root spectrum runs may set             |
//   profile_node_count to zero when diagnostics are not requested; support sigma rows still exist.            |
pub const ProfileLineValues = struct {
    values: []ProfileLineValue = &.{},
    support_profile_total_sigma_cm2_per_molecule: []f64 = &.{},
    wavelength_count: usize = 0,
    profile_node_count: usize = 0,
    support_profile_node_count: usize = 0,
    reuse_stamp: hashing.ReuseStamp = .{},

    pub fn deinit(self: *ProfileLineValues, allocator: Allocator) void {
        // ProfileLineValues.deinit ---------------------------------------------------------------------------|
        // Release exact-route profile-line rows owned by this memory object.                                  |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.support_profile_total_sigma_cm2_per_molecule);
        allocator.free(self.values);
        self.* = .{};
    }

    pub fn supportProfileTotalSigmaAt(
        self: ProfileLineValues,
        wavelength_index: usize,
        profile_node_index: usize,
    ) ?f64 {
        // ProfileLineValues.supportProfileTotalSigmaAt -------------------------------------------------------|
        // Return one retained support-profile sigma from the dense f64 column.                                |
        // ----------------------------------------------------------------------------------------------------|
        if (wavelength_index >= self.wavelength_count or
            profile_node_index >= self.support_profile_node_count)
        {
            return null;
        }
        return self.support_profile_total_sigma_cm2_per_molecule[
            wavelength_index * self.support_profile_node_count + profile_node_index
        ];
    }

    pub fn fillSupportLineSigmaAtWavelengthIndex(
        self: ProfileLineValues,
        layer_grid: atmosphere_layers.LayerGrid,
        wavelength_index: usize,
        out_sigma_cm2_per_molecule: []f64,
        stage_cost: ?CostTiming.Active,
    ) !void {
        // ProfileLineValues.fillSupportLineSigmaAtWavelengthIndex --------------------------------------------|
        // Sample retained canonical sigma_total profile rows onto the setup support grid.                     |
        //                                                                                                     |
        //   The line list has already been evaluated into the support-profile total-sigma column; this helper |
        //   only prepares endpoint-secant spline curvature and samples it by support altitude.                |
        //                                                                                                     |
        // memory                                                                                              |
        //   Uses fixed stack rows capped at max_spectroscopy_profile_nodes and writes caller-owned support    |
        //   sigma storage. It allocates nothing inside the per-wavelength solve.                              |
        // ----------------------------------------------------------------------------------------------------|
        if (wavelength_index >= self.wavelength_count) return error.InvalidShape;
        if (out_sigma_cm2_per_molecule.len != layer_grid.support_mid_altitudes_km.len) return error.InvalidShape;

        const node_count = self.support_profile_node_count;
        if (node_count < 3 or node_count > max_spectroscopy_profile_nodes) return error.InvalidShape;
        if (layer_grid.spectroscopy_profile.rows.len != node_count) return error.InvalidShape;

        const timing_start = CostTiming.start(stage_cost);
        defer CostTiming.finish(stage_cost, timing_start, "profile_interp");

        const start = wavelength_index * node_count;
        const total_column = self.support_profile_total_sigma_cm2_per_molecule[start .. start + node_count];
        var altitudes_km: [max_spectroscopy_profile_nodes]f64 = undefined;
        var total_values: [max_spectroscopy_profile_nodes]f64 = undefined;
        var total_second: [max_spectroscopy_profile_nodes]f64 = undefined;

        for (layer_grid.spectroscopy_profile.rows, total_column, 0..) |profile_row, total_sigma, profile_node_index| {
            altitudes_km[profile_node_index] = profile_row.altitude_km;
            total_values[profile_node_index] = total_sigma;
        }

        const altitudes = altitudes_km[0..node_count];
        spline.endpointSecantSecondDerivatives(
            altitudes,
            total_values[0..node_count],
            total_second[0..node_count],
        ) catch return error.InvalidShape;

        for (out_sigma_cm2_per_molecule, layer_grid.support_mid_altitudes_km) |*sigma, altitude_km| {
            sigma.* = @max(
                spline.sampleWithSecondDerivatives(
                    altitudes,
                    total_values[0..node_count],
                    total_second[0..node_count],
                    altitude_km,
                ) catch return error.InvalidShape,
                0.0,
            );
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|
