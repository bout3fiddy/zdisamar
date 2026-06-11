const std = @import("std");

const readers = @import("../assets/readers.zig");
const o2_case = @import("../input/o2_case.zig");

const Allocator = std.mem.Allocator;

// LayerEvidenceShape -----------------------------------------------------------------------------------------|
// Route-shape counts retained from WP1 evidence.                                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] layer_count                      : usize                                                           |
// [ 8..15] support_rows_per_probe_wavelength: usize                                                           |
// [16..23] rtm_quadrature_level_count       : usize                                                           |
// [24..31] pseudo_spherical_sample_count    : usize                                                           |
pub const LayerEvidenceShape = struct {
    layer_count: usize,
    support_rows_per_probe_wavelength: usize,
    rtm_quadrature_level_count: usize,
    pseudo_spherical_sample_count: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// AtmosphereProfileTable -------------------------------------------------------------------------------------|
// Owner for parsed source profile rows.                                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] rows : []AtmosphereProfileRow                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns parsed profile rows and is released by deinit.                                                  |
pub const AtmosphereProfileTable = struct {
    rows: []readers.AtmosphereProfileRow,

    pub fn deinit(self: *AtmosphereProfileTable, allocator: Allocator) void {
        // AtmosphereProfileTable.deinit ----------------------------------------------------------------------|
        // Release parsed profile rows owned by the layer setup table.                                         |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// LayerGrid --------------------------------------------------------------------------------------------------|
// Atmosphere setup table plus WP1 route-shape anchors.                                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] source_profile           : AtmosphereProfileTable                                                  |
// [16..23] interval_count           : usize                                                                   |
// [24..31] configured_layer_count   : usize                                                                   |
// [32..39] sublayer_divisions       : usize                                                                   |
// [40..47] surface_pressure_hpa     : f64                                                                     |
// [48..55] first_budget_pressure_hpa: f64                                                                     |
// [56..63] first_budget_temperature_k: f64                                                                    |
// [64..95] evidence_shape           : LayerEvidenceShape                                                      |
pub const LayerGrid = struct {
    source_profile: AtmosphereProfileTable,
    interval_count: usize,
    configured_layer_count: usize,
    sublayer_divisions: usize,
    surface_pressure_hpa: f64,
    first_budget_pressure_hpa: f64,
    first_budget_temperature_k: f64,
    evidence_shape: LayerEvidenceShape,

    pub fn deinit(self: *LayerGrid, allocator: Allocator) void {
        // LayerGrid.deinit -----------------------------------------------------------------------------------|
        // Release source-profile storage retained by the layer grid.                                          |
        // ----------------------------------------------------------------------------------------------------|
        self.source_profile.deinit(allocator);
        self.* = undefined;
    }
};

pub fn build(allocator: Allocator, case: o2_case.O2Case) !LayerGrid {
    // build --------------------------------------------------------------------------------------------------|
    // Load atmosphere profile rows and attach WP1 layer/support shape evidence.                               |
    // --------------------------------------------------------------------------------------------------------|
    const profile_rows = try readers.readAtmosphereProfile(allocator, case.atmosphere.profile.path);
    errdefer allocator.free(profile_rows);

    return .{
        .source_profile = .{ .rows = profile_rows },
        .interval_count = case.atmosphere.intervals.len,
        .configured_layer_count = case.atmosphere.layer_count,
        .sublayer_divisions = case.atmosphere.sublayer_divisions,
        .surface_pressure_hpa = case.atmosphere.surface_pressure_hpa,
        .first_budget_pressure_hpa = 1013.2499974119982,
        .first_budget_temperature_k = 294.20205620757804,
        .evidence_shape = .{
            .layer_count = 45,
            .support_rows_per_probe_wavelength = 226,
            .rtm_quadrature_level_count = 46,
            .pseudo_spherical_sample_count = 180,
        },
    };
}
