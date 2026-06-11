const std = @import("std");

const cia_absorption = @import("cia_absorption.zig");
const jacobian_states = @import("../transport/jacobian_states.zig");
const rayleigh = @import("rayleigh.zig");
const spline = @import("../common/math/spline.zig");
const aerosol_tables = @import("../setup/aerosol_tables.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const cia_table = @import("../setup/cia_table.zig");

const max_collision_pair_profile_rows: usize = 64;

// main:`state_build/spectroscopy.zig` default_o2_volume_mixing_ratio.
const oxygen_volume_mixing_ratio = 0.20946;

// layer_depths.zig ------------------------------------------------------------------------------------------ |
// Converts support-row thermodynamics and caller-supplied O2 line sigma rows into optical-depth rows.         |
//                                                                                                             |
// provenance                                                                                                  |
//   Formula shape follows main:`src/forward_model/optical_properties/state_build/carrier_eval.zig`:           |
//   k_abs_gas = sigma_line * n_o2 * 1e5, k_sca_gas = sigma_R * n_air * 1e5,                                   |
//   k_cia = sigma_cia * n_pair * 1e5, then support rows multiply those per-km carriers by path length.        |
//   n_pair follows main:`layer_accumulation.zig` CollisionComplexProfileCache on the old spectroscopy         |
//   profile and falls back to n_o2^2 only when the profile cache is unusable.                                 |
//                                                                                                             |
// boundary                                                                                                    |
//   This file does not evaluate HITRAN line lists. The line sigma vector is an explicit input so spectroscopy |
//   memory owners stay outside the per-wavelength optics hot loop.                                            |
// ------------------------------------------------------------------------------------------------------------|

// SupportOptics --------------------------------------------------------------------------------------------- |
// Optical-depth contribution at one setup support row.                                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 104 B (0.102 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                          : f64                                                       |
// [ 8..15] altitude_km                            : f64                                                       |
// [16..23] path_length_cm                         : f64                                                       |
// [24..31] gas_absorption_optical_depth           : f64                                                       |
// [32..39] gas_scattering_optical_depth           : f64                                                       |
// [40..47] cia_optical_depth                      : f64                                                       |
// [48..55] aerosol_optical_depth                  : f64                                                       |
// [56..63] aerosol_scattering_optical_depth       : f64                                                       |
// [64..71] total_optical_depth                    : f64                                                       |
// [72..79] total_scattering_optical_depth         : f64                                                       |
// [80..87] single_scatter_albedo                  : f64                                                       |
// [88..91] global_sublayer_index                  : u32                                                       |
// [92..95] interval_index_1based                  : u32                                                       |
// [96..103] trailing padding                      : 8 B                                                       |
pub const SupportOptics = struct {
    wavelength_nm: f64,
    altitude_km: f64,
    path_length_cm: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    total_optical_depth: f64,
    total_scattering_optical_depth: f64,
    single_scatter_albedo: f64,
    global_sublayer_index: u32,
    interval_index_1based: u32,
};
// ------------------------------------------------------------------------------------------------------------|

// LayerOptics ----------------------------------------------------------------------------------------------- |
// LABOS layer optical-depth row reduced from active support rows.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 176 B (0.172 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 55] scalar optical-depth fields        : 7 f64                                                       |
// [ 56..127] jacobian vectors                   : 3 * [3]f64                                                  |
// [128..151] aerosol_phase_weight_jacobian      : [3]f64                                                      |
// [152..159] support_start                      : usize                                                       |
// [160..167] support_count                      : usize                                                       |
// [168..171] interval_index_1based              : u32                                                         |
// [172..175] trailing padding                   : 4 B                                                         |
//                                                                                                             |
// footprint: per instance = 176 B (0.172 KiB); total = per instance * transport layer count                   |
pub const LayerOptics = struct {
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    total_scattering_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
    optical_depth_jacobian: jacobian_states.Vector = jacobian_states.zero(),
    scattering_optical_depth_jacobian: jacobian_states.Vector = jacobian_states.zero(),
    single_scatter_albedo_jacobian: jacobian_states.Vector = jacobian_states.zero(),
    aerosol_phase_weight_jacobian: jacobian_states.Vector = jacobian_states.zero(),
    support_start: usize = 0,
    support_count: usize = 0,
    interval_index_1based: u32 = 0,
};
// ------------------------------------------------------------------------------------------------------------|

// CollisionPairProfile -------------------------------------------------------------------------------------- |
// Stack profile cache for O2-O2 collision-pair density.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 1544 B (1.508 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..   7] node_count               : usize                                                               |
// [   8.. 519] altitudes_km             : [64]f64                                                             |
// [ 520..1031] log_complex_vmr_fraction : [64]f64                                                             |
// [1032..1543] second                   : [64]f64                                                             |
//                                                                                                             |
// provenance                                                                                                  |
//   main:`layer_accumulation.zig` builds log(n_o2^2 / n_air) over the spectroscopy profile, not the dense     |
//   vertical setup profile. The WP1 diagnostic cross-section rows prove this cache is active for the O2 A     |
//   reference case.                                                                                           |
const CollisionPairProfile = struct {
    node_count: usize = 0,
    altitudes_km: [max_collision_pair_profile_rows]f64 = undefined,
    log_complex_vmr_fraction: [max_collision_pair_profile_rows]f64 = undefined,
    second: [max_collision_pair_profile_rows]f64 = undefined,

    fn init(layer_grid: atmosphere_layers.LayerGrid) CollisionPairProfile {
        // CollisionPairProfile.init ------------------------------------------------------------------------- |
        // Prepare endpoint-secant second derivatives for the old spectroscopy-profile collision complex.      |
        // ----------------------------------------------------------------------------------------------------|
        const rows = layer_grid.spectroscopy_profile.rows;
        if (rows.len < 3 or rows.len > max_collision_pair_profile_rows) return .{};

        var profile = CollisionPairProfile{ .node_count = rows.len };
        for (rows, 0..) |row, index| {
            const air_density_cm3 =
                row.pressure_hpa / @max(row.temperature_k, 1.0e-9) / 1.380658e-19;
            if (air_density_cm3 <= 0.0) return .{};

            const oxygen_density_cm3 = air_density_cm3 * oxygen_volume_mixing_ratio;
            const complex_vmr_fraction = oxygen_density_cm3 * oxygen_density_cm3 / air_density_cm3;
            if (complex_vmr_fraction <= 0.0) return .{};

            profile.altitudes_km[index] = row.altitude_km;
            profile.log_complex_vmr_fraction[index] = @log(complex_vmr_fraction);
        }

        spline.endpointSecantSecondDerivatives(
            profile.altitudes_km[0..profile.node_count],
            profile.log_complex_vmr_fraction[0..profile.node_count],
            profile.second[0..profile.node_count],
        ) catch return .{};
        return profile;
    }

    fn pairDensityCm6(
        self: CollisionPairProfile,
        altitude_km: f64,
        air_number_density_cm3: f64,
        fallback_oxygen_number_density_cm3: f64,
    ) f64 {
        // CollisionPairProfile.pairDensityCm6 --------------------------------------------------------------- |
        // Sample n_pair = exp(spline(log(n_o2^2 / n_air), z)) * n_air; fall back to n_o2^2 only on cache miss.|
        // ----------------------------------------------------------------------------------------------------|
        if (self.node_count < 3 or air_number_density_cm3 <= 0.0) {
            return fallback_oxygen_number_density_cm3 * fallback_oxygen_number_density_cm3;
        }

        const altitudes = self.altitudes_km[0..self.node_count];
        const log_fraction = self.log_complex_vmr_fraction[0..self.node_count];
        const second = self.second[0..self.node_count];

        if (altitude_km <= altitudes[0]) return @exp(log_fraction[0]) * air_number_density_cm3;
        if (altitude_km >= altitudes[self.node_count - 1]) {
            return @exp(log_fraction[self.node_count - 1]) * air_number_density_cm3;
        }

        const sampled_log_fraction = spline.sampleWithSecondDerivatives(
            altitudes,
            log_fraction,
            second,
            altitude_km,
        ) catch return fallback_oxygen_number_density_cm3 * fallback_oxygen_number_density_cm3;
        return @exp(sampled_log_fraction) * air_number_density_cm3;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn fillSupportOpticsAtWavelength(
    wavelength_nm: f64,
    layer_grid: atmosphere_layers.LayerGrid,
    line_sigma_cm2_per_molecule: []const f64,
    cia: cia_table.O2CiaTable,
    aerosol: aerosol_tables.AerosolLayerTable,
    out_support: []SupportOptics,
) !void {
    // fillSupportOpticsAtWavelength ------------------------------------------------------------------------- |
    // Fill support-row optical depths for one wavelength without allocation.                                  |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : every high-resolution radiance wavelength after spectroscopy memory has supplied sigma     |
    //   memory   : streams support arrays and caller-owned output rows                                        |
    //                                                                                                         |
    // math                                                                                                    |
    //   tau_abs_gas = sigma_line * n_o2 * path_cm                                                             |
    //   tau_rayleigh = sigma_R * n_air * path_cm                                                              |
    //   tau_cia = sigma_cia * n_o2^2 * path_cm                                                                |
    // --------------------------------------------------------------------------------------------------------|
    const support_count = layer_grid.support_mid_altitudes_km.len;
    if (line_sigma_cm2_per_molecule.len != support_count or out_support.len != support_count) {
        return error.InvalidShape;
    }
    if (aerosol.optical_depth != 0.0) return error.UnsupportedAerosolOptics;

    const rayleigh_sigma_cm2 = rayleigh.crossSectionCm2(wavelength_nm);
    const collision_pair_profile = CollisionPairProfile.init(layer_grid);
    for (out_support, 0..) |*row, support_index| {
        const path_length_cm = @max(layer_grid.support_path_lengths_cm[support_index], 0.0);
        const oxygen_density_cm3 = layer_grid.support_o2_number_densities_cm3[support_index];
        const air_density_cm3 = layer_grid.support_air_number_densities_cm3[support_index];
        const gas_absorption =
            @max(line_sigma_cm2_per_molecule[support_index], 0.0) *
            oxygen_density_cm3 *
            path_length_cm;
        const gas_scattering = rayleigh_sigma_cm2 * air_density_cm3 * path_length_cm;
        const cia_sigma_cm5 = cia_absorption.sigmaAt(
            cia,
            wavelength_nm,
            layer_grid.support_temperatures_k[support_index],
        );
        const cia_pair_density_cm6 = collision_pair_profile.pairDensityCm6(
            layer_grid.support_mid_altitudes_km[support_index],
            air_density_cm3,
            oxygen_density_cm3,
        );
        const cia_depth = cia_sigma_cm5 * cia_pair_density_cm6 * path_length_cm;
        const total_scattering = gas_scattering;
        const total_depth = gas_absorption + gas_scattering + cia_depth;

        row.* = .{
            .wavelength_nm = wavelength_nm,
            .altitude_km = layer_grid.support_mid_altitudes_km[support_index],
            .path_length_cm = path_length_cm,
            .gas_absorption_optical_depth = gas_absorption,
            .gas_scattering_optical_depth = gas_scattering,
            .cia_optical_depth = cia_depth,
            .aerosol_optical_depth = 0.0,
            .aerosol_scattering_optical_depth = 0.0,
            .total_optical_depth = total_depth,
            .total_scattering_optical_depth = total_scattering,
            .single_scatter_albedo = singleScatterAlbedo(total_scattering, total_depth),
            .global_sublayer_index = @intCast(support_index),
            .interval_index_1based = layer_grid.support_interval_indices_1based[support_index],
        };
    }
}

pub fn reduceLayerOpticsFromSupportRows(
    layer_grid: atmosphere_layers.LayerGrid,
    support_rows: []const SupportOptics,
    out_layers: []LayerOptics,
) !void {
    // reduceLayerOpticsFromSupportRows ---------------------------------------------------------------------- |
    // Sum active support rows into one LABOS transport row per layer. Boundary rows mark edges and have zero  |
    // path length, matching main:`shared_carrier.fillReducedLayerInputFromSupportRowsWithSpectroscopyCache`.  |
    // --------------------------------------------------------------------------------------------------------|
    if (out_layers.len != layer_grid.layer_pressures_hpa.len or
        support_rows.len != layer_grid.support_mid_altitudes_km.len)
    {
        return error.InvalidShape;
    }

    for (out_layers, 0..) |*layer, layer_index| {
        const support_start: usize = @intCast(layer_grid.layer_support_starts[layer_index]);
        const support_count: usize = @intCast(layer_grid.layer_support_counts[layer_index]);
        if (support_start + support_count > support_rows.len) return error.InvalidShape;

        var reduced = LayerOptics{
            .support_start = support_start,
            .support_count = support_count,
            .interval_index_1based = layer_grid.layer_interval_indices_1based[layer_index],
        };
        if (support_count >= 2) {
            for (support_rows[support_start + 1 .. support_start + support_count - 1]) |support| {
                reduced.gas_absorption_optical_depth += support.gas_absorption_optical_depth;
                reduced.gas_scattering_optical_depth += support.gas_scattering_optical_depth;
                reduced.cia_optical_depth += support.cia_optical_depth;
                reduced.aerosol_optical_depth += support.aerosol_optical_depth;
                reduced.aerosol_scattering_optical_depth += support.aerosol_scattering_optical_depth;
            }
        }
        reduced.total_scattering_optical_depth =
            reduced.gas_scattering_optical_depth +
            reduced.aerosol_scattering_optical_depth;
        reduced.total_optical_depth =
            reduced.gas_absorption_optical_depth +
            reduced.gas_scattering_optical_depth +
            reduced.cia_optical_depth +
            reduced.aerosol_optical_depth;
        reduced.single_scatter_albedo =
            singleScatterAlbedo(reduced.total_scattering_optical_depth, reduced.total_optical_depth);
        layer.* = reduced;
    }
}

fn singleScatterAlbedo(scattering_optical_depth: f64, total_optical_depth: f64) f64 {
    if (total_optical_depth <= 0.0) return 0.0;
    return std.math.clamp(scattering_optical_depth / total_optical_depth, 0.0, 1.0);
}
