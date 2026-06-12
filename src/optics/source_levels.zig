const std = @import("std");

const gauss_legendre = @import("../common/math/gauss_legendre.zig");
const aerosol_tables = @import("../setup/aerosol_tables.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const layer_depths = @import("layer_depths.zig");
const rayleigh = @import("rayleigh.zig");

const invalid_support_row_index = std.math.maxInt(usize);
const max_source_interval_nodes: usize = 128;

// source_levels.zig ------------------------------------------------------------------------------------------|
// Builds the cached shared-RTM source-level rows consumed by integrated-source transport.                     |
//                                                                                                             |
// provenance                                                                                                  |
//   Geometry follows main:`src/forward_model/optical_properties/state_build/shared_geometry.zig`: one level   |
//   per layer boundary, boundary support rows for gas, first active support row above a boundary, and last    |
//   active support row below a boundary. Level weights use the same interval-group Gauss-Legendre rule.       |
//   Aerosol source Jacobian scale follows main:`state_build/rtm_quadrature.zig` fillAerosolSourceJacobian.    |
//                                                                                                             |
// boundary                                                                                                    |
//   This file reads already-filled support optical rows. It does not evaluate spectroscopy and does not       |
//   allocate while filling per-wavelength source levels.                                                      |
// ------------------------------------------------------------------------------------------------------------|

// SourceLevel ------------------------------------------------------------------------------------------------|
// One altitude quadrature level used by source integration.                                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] altitude_km                : f64                                                                   |
// [ 8..15] weight_km                  : f64                                                                   |
// [16..23] scattering_per_km          : f64                                                                   |
// [24..31] aerosol_ksca_above_per_km  : f64                                                                   |
// [32..39] aerosol_ksca_below_per_km  : f64                                                                   |
// [40..47] aerosol_ksca_jacobian      : f64                                                                   |
// [48..55] phase_aerosol_weight       : f64                                                                   |
// [56..63] phase_rayleigh2_weight     : f64                                                                   |
//                                                                                                             |
// footprint: per instance = 64 B (0.062 KiB); total = per instance * (layer_count + 1)                        |
pub const SourceLevel = struct {
    altitude_km: f64 = 0.0,
    weight_km: f64 = 0.0,
    scattering_per_km: f64 = 0.0,
    aerosol_ksca_above_per_km: f64 = 0.0,
    aerosol_ksca_below_per_km: f64 = 0.0,
    aerosol_ksca_jacobian: f64 = 0.0,
    phase_aerosol_weight: f64 = 0.0,
    phase_rayleigh2_weight: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn fillSourceLevelsAtWavelength(
    wavelength_nm: f64,
    layer_grid: atmosphere_layers.LayerGrid,
    support_rows: []const layer_depths.SupportOptics,
    aerosol: aerosol_tables.AerosolLayerTable,
    out_levels: []SourceLevel,
) !void {
    // fillSourceLevelsAtWavelength ---------------------------------------------------------------------------|
    // Fill shared-RTM source levels for one wavelength from retained support-row optics.                      |
    //                                                                                                         |
    // math                                                                                                    |
    //   gas k_sca(z_boundary) = sigma_rayleigh(lambda) * n_air(boundary) * 1e5                                |
    //   aerosol k_sca = tau_aerosol_sca(active_support) / dz_active_km                                        |
    //   phase weights use the local gas/aerosol scattering mix.                                               |
    // --------------------------------------------------------------------------------------------------------|
    const layer_count = layer_grid.layer_pressures_hpa.len;
    if (out_levels.len != layer_count + 1 or
        support_rows.len != layer_grid.support_mid_altitudes_km.len)
    {
        return error.InvalidShape;
    }

    const rayleigh_sigma_cm2 = rayleigh.crossSectionCm2(wavelength_nm);
    const rayleigh_phase2 = rayleigh.phaseCoefficient2(wavelength_nm);

    for (out_levels, 0..) |*level, level_index| {
        const boundary_support_index = boundarySupportRowIndex(layer_grid, level_index);
        if (boundary_support_index >= support_rows.len) return error.InvalidShape;

        const aerosol_above_index = aerosolAboveSupportRowIndex(layer_grid, level_index);
        const aerosol_below_index = aerosolBelowSupportRowIndex(layer_grid, level_index);
        const gas_scattering_per_km =
            rayleigh_sigma_cm2 *
            layer_grid.support_air_number_densities_cm3[boundary_support_index] *
            1.0e5;
        const aerosol_above_per_km = aerosolScatteringPerKm(support_rows, aerosol_above_index);
        const aerosol_below_per_km = aerosolScatteringPerKm(support_rows, aerosol_below_index);
        const source_aerosol_per_km = aerosol_above_per_km;
        const total_scattering_per_km = gas_scattering_per_km + source_aerosol_per_km;

        level.* = .{
            .altitude_km = layer_grid.support_mid_altitudes_km[boundary_support_index],
            .weight_km = 0.0,
            .scattering_per_km = total_scattering_per_km,
            .aerosol_ksca_above_per_km = aerosol_above_per_km,
            .aerosol_ksca_below_per_km = aerosol_below_per_km,
            .aerosol_ksca_jacobian = 0.0,
            .phase_aerosol_weight = phaseAerosolWeight(gas_scattering_per_km, source_aerosol_per_km),
            .phase_rayleigh2_weight = phaseRayleigh2Weight(
                rayleigh_phase2,
                gas_scattering_per_km,
                source_aerosol_per_km,
            ),
        };
    }

    fillIntervalWeights(layer_grid, out_levels) catch return error.InvalidShape;
    for (out_levels) |*level| {
        level.aerosol_ksca_jacobian = aerosolSourceJacobian(aerosol, level.aerosol_ksca_above_per_km, level.weight_km);
    }
}

fn boundarySupportRowIndex(layer_grid: atmosphere_layers.LayerGrid, level_index: usize) usize {
    // boundarySupportRowIndex --------------------------------------------------------------------------------|
    // Map an RTM level index to the shared boundary support row used for gas scattering.                      |
    // --------------------------------------------------------------------------------------------------------|
    if (level_index == layer_grid.layer_pressures_hpa.len) {
        const last_layer = level_index - 1;
        return @as(usize, @intCast(layer_grid.layer_support_starts[last_layer])) +
            @as(usize, @intCast(layer_grid.layer_support_counts[last_layer])) -
            1;
    }

    return @intCast(layer_grid.layer_support_starts[level_index]);
}

fn aerosolAboveSupportRowIndex(layer_grid: atmosphere_layers.LayerGrid, level_index: usize) usize {
    // aerosolAboveSupportRowIndex ----------------------------------------------------------------------------|
    // Return the first active support row in the layer above this boundary level.                             |
    // --------------------------------------------------------------------------------------------------------|
    if (level_index >= layer_grid.layer_pressures_hpa.len) return invalid_support_row_index;

    const start: usize = @intCast(layer_grid.layer_support_starts[level_index]);
    const count: usize = @intCast(layer_grid.layer_support_counts[level_index]);
    if (count <= 2) return invalid_support_row_index;
    return start + 1;
}

fn aerosolBelowSupportRowIndex(layer_grid: atmosphere_layers.LayerGrid, level_index: usize) usize {
    // aerosolBelowSupportRowIndex ----------------------------------------------------------------------------|
    // Return the last active support row in the layer below this boundary level.                              |
    // --------------------------------------------------------------------------------------------------------|
    if (level_index == 0) return invalid_support_row_index;

    const below_layer = level_index - 1;
    const start: usize = @intCast(layer_grid.layer_support_starts[below_layer]);
    const count: usize = @intCast(layer_grid.layer_support_counts[below_layer]);
    if (count <= 2) return invalid_support_row_index;
    return start + count - 2;
}

fn aerosolScatteringPerKm(
    support_rows: []const layer_depths.SupportOptics,
    support_index: usize,
) f64 {
    // aerosolScatteringPerKm ---------------------------------------------------------------------------------|
    // Convert an active support-row aerosol scattering optical depth back to a per-km carrier.                |
    // --------------------------------------------------------------------------------------------------------|
    if (support_index == invalid_support_row_index or support_index >= support_rows.len) return 0.0;

    const row = support_rows[support_index];
    const path_length_km = row.path_length_cm / 1.0e5;
    if (path_length_km <= 0.0) return 0.0;
    return row.aerosol_scattering_optical_depth / path_length_km;
}

fn aerosolSourceJacobian(
    aerosol: aerosol_tables.AerosolLayerTable,
    aerosol_scattering_per_km: f64,
    level_weight_km: f64,
) f64 {
    // aerosolSourceJacobian ----------------------------------------------------------------------------------|
    // Old shared-grid code first writes boundary-row source scales, then spreads layer aerosol derivatives    |
    // over active weighted levels. Boundary levels keep zero; weighted aerosol levels use k_sca / tau_aer.    |
    // --------------------------------------------------------------------------------------------------------|
    if (level_weight_km <= 0.0 or aerosol.optical_depth <= 0.0 or aerosol_scattering_per_km <= 0.0) return 0.0;
    return aerosol_scattering_per_km / aerosol.optical_depth;
}

fn fillIntervalWeights(
    layer_grid: atmosphere_layers.LayerGrid,
    out_levels: []SourceLevel,
) error{InvalidShape}!void {
    // fillIntervalWeights ------------------------------------------------------------------------------------|
    // Assign RTM level source weights by grouping adjacent layers with the same explicit interval index.      |
    // --------------------------------------------------------------------------------------------------------|
    var interval_start: usize = 0;
    while (interval_start < layer_grid.layer_pressures_hpa.len) {
        const interval_index_1based = layer_grid.layer_interval_indices_1based[interval_start];
        var interval_stop = interval_start + 1;
        while (interval_stop < layer_grid.layer_pressures_hpa.len and
            layer_grid.layer_interval_indices_1based[interval_stop] == interval_index_1based)
        {
            interval_stop += 1;
        }

        const interior_level_count = interval_stop - interval_start - 1;
        if (interior_level_count > 0) {
            var nodes: [max_source_interval_nodes]f64 = undefined;
            var weights: [max_source_interval_nodes]f64 = undefined;
            if (interior_level_count > nodes.len) return error.InvalidShape;
            gauss_legendre.fillNodesAndWeights(
                @intCast(interior_level_count),
                nodes[0..interior_level_count],
                weights[0..interior_level_count],
            ) catch return error.InvalidShape;

            const lower_altitude_km = layer_grid.layer_bottom_altitudes_km[interval_start];
            const upper_altitude_km = layer_grid.layer_top_altitudes_km[interval_stop - 1];
            const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);
            for (0..interior_level_count) |offset| {
                out_levels[interval_start + 1 + offset].weight_km =
                    0.5 * weights[offset] * altitude_span_km;
            }
        }

        interval_start = interval_stop;
    }
}

fn phaseAerosolWeight(gas_scattering: f64, aerosol_scattering: f64) f64 {
    // phaseAerosolWeight -------------------------------------------------------------------------------------|
    // Return the aerosol fraction of the local source scattering carrier.                                     |
    // --------------------------------------------------------------------------------------------------------|
    const total = gas_scattering + aerosol_scattering;
    if (total <= 0.0) return 0.0;
    return aerosol_scattering / total;
}

fn phaseRayleigh2Weight(rayleigh_phase2: f64, gas_scattering: f64, aerosol_scattering: f64) f64 {
    // phaseRayleigh2Weight -----------------------------------------------------------------------------------|
    // Return the Rayleigh l=2 coefficient weighted by the gas fraction of source scattering.                  |
    // --------------------------------------------------------------------------------------------------------|
    const total = gas_scattering + aerosol_scattering;
    if (total <= 0.0) return rayleigh_phase2;
    return gas_scattering / total * rayleigh_phase2;
}
