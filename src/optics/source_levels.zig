const std = @import("std");

const gauss_legendre = @import("../common/math/gauss_legendre.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const jacobian_states = @import("../rtm/jacobian_states.zig");
const layer_depths = @import("layer_depths.zig");
const rayleigh = @import("rayleigh.zig");

const invalid_support_row_index = std.math.maxInt(usize);
const max_source_interval_nodes: usize = 128;

// source_levels.zig ------------------------------------------------------------------------------------------|
// Builds the cached shared-RTM source-level rows consumed by integrated-source transport.                     |
//                                                                                                             |
//   per layer boundary, boundary support rows for gas, first active support row above a boundary, and last    |
//   active support row below a boundary. Level weights use the same interval-group Gauss-Legendre rule.       |
//   fillSharedAerosolSourceJacobianFromLayers.                                                                |
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
    layer_rows: []const layer_depths.LayerOptics,
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
        layer_rows.len != layer_count or
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

        const has_aerosol_above_support =
            aerosol_above_index != invalid_support_row_index and aerosol_above_index < support_rows.len;
        const has_aerosol_below_support =
            aerosol_below_index != invalid_support_row_index and aerosol_below_index < support_rows.len;

        const aerosol_above_per_km =
            if (has_aerosol_above_support)
                support_rows[aerosol_above_index].aerosol_scattering_optical_depth_per_km
            else
                0.0;
        const aerosol_below_per_km =
            if (has_aerosol_below_support)
                support_rows[aerosol_below_index].aerosol_scattering_optical_depth_per_km
            else
                0.0;

        const source_aerosol_per_km = aerosol_above_per_km;
        const total_scattering_per_km = gas_scattering_per_km + source_aerosol_per_km;

        const phase_aerosol_weight, const phase_rayleigh2_weight = phase_weights: {
            if (total_scattering_per_km <= 0.0) break :phase_weights .{ 0.0, rayleigh_phase2 };

            const inv_total = 1.0 / total_scattering_per_km;
            break :phase_weights .{
                source_aerosol_per_km * inv_total,
                gas_scattering_per_km * inv_total * rayleigh_phase2,
            };
        };

        level.* = .{
            .altitude_km = layer_grid.support_mid_altitudes_km[boundary_support_index],
            .weight_km = 0.0,
            .scattering_per_km = total_scattering_per_km,
            .aerosol_ksca_above_per_km = aerosol_above_per_km,
            .aerosol_ksca_below_per_km = aerosol_below_per_km,
            .aerosol_ksca_jacobian = 0.0,
            .phase_aerosol_weight = phase_aerosol_weight,
            .phase_rayleigh2_weight = phase_rayleigh2_weight,
        };
    }

    fillIntervalWeights(layer_grid, out_levels) catch return error.InvalidShape;
    fillSharedAerosolSourceJacobiansFromLayers(layer_rows, out_levels);
}

fn boundarySupportRowIndex(layer_grid: atmosphere_layers.LayerGrid, level_index: usize) usize {
    // boundarySupportRowIndex --------------------------------------------------------------------------------|
    // Map an RTM level index to the shared boundary support row used for gas scattering.                      |
    // --------------------------------------------------------------------------------------------------------|
    if (level_index == layer_grid.layer_pressures_hpa.len) {
        const last_layer = level_index - 1;
        return @as(usize, @intCast(layer_grid.layer_support_starts[last_layer])) +
            @as(usize, @intCast(layer_grid.layer_support_count)) -
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
    const count: usize = @intCast(layer_grid.layer_support_count);
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
    const count: usize = @intCast(layer_grid.layer_support_count);
    if (count <= 2) return invalid_support_row_index;
    return start + count - 2;
}

fn fillSharedAerosolSourceJacobiansFromLayers(
    layer_rows: []const layer_depths.LayerOptics,
    out_levels: []SourceLevel,
) void {
    // fillSharedAerosolSourceJacobiansFromLayers -------------------------------------------------------------|
    // Shared RTM quadrature spreads the layer aerosol-scattering derivative over active adjacent source       |
    // weights instead of using each level's local k_sca/tau fallback scale.                                   |
    //                                                                                                         |
    // math                                                                                                    |
    //   derivative per km = sum(d tau_sca_layer / d tau_aer) / sum(active adjacent source weights)            |
    // --------------------------------------------------------------------------------------------------------|
    var total_scattering_derivative: f64 = 0.0;
    for (layer_rows) |*layer| {
        const derivative = jacobian_states.get(
            layer.scattering_optical_depth_jacobian,
            .aerosol_optical_depth,
        );
        if (derivative > 0.0) total_scattering_derivative += derivative;
    }

    if (total_scattering_derivative <= 0.0) return;

    var total_weight_km: f64 = 0.0;
    for (out_levels, 0..) |level, level_index| {
        if (level.weight_km <= 0.0) continue;
        const below_active =
            level_index > 0 and
            jacobian_states.get(
                layer_rows[level_index - 1].scattering_optical_depth_jacobian,
                .aerosol_optical_depth,
            ) > 0.0;
        const above_active =
            level_index < layer_rows.len and
            jacobian_states.get(
                layer_rows[level_index].scattering_optical_depth_jacobian,
                .aerosol_optical_depth,
            ) > 0.0;
        if (below_active or above_active) total_weight_km += level.weight_km;
    }

    if (total_weight_km <= 0.0) return;

    const derivative_per_km = total_scattering_derivative / total_weight_km;
    for (out_levels, 0..) |*level, level_index| {
        if (level.weight_km <= 0.0) continue;
        const below_active =
            level_index > 0 and
            jacobian_states.get(
                layer_rows[level_index - 1].scattering_optical_depth_jacobian,
                .aerosol_optical_depth,
            ) > 0.0;
        const above_active =
            level_index < layer_rows.len and
            jacobian_states.get(
                layer_rows[level_index].scattering_optical_depth_jacobian,
                .aerosol_optical_depth,
            ) > 0.0;
        if (below_active or above_active) level.aerosol_ksca_jacobian = derivative_per_km;
    }
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
            if (interior_level_count > max_source_interval_nodes) return error.InvalidShape;

            const lower_altitude_km = layer_grid.layer_bottom_altitudes_km[interval_start];
            const upper_altitude_km = layer_grid.layer_top_altitudes_km[interval_stop - 1];
            const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);

            if (interior_level_count <= 10) {
                const rule = gauss_legendre.rule(@intCast(interior_level_count)) catch return error.InvalidShape;
                for (0..interior_level_count) |offset| {
                    out_levels[interval_start + 1 + offset].weight_km =
                        0.5 * rule.weights[offset] * altitude_span_km;
                }
                interval_start = interval_stop;
                continue;
            }

            var nodes: [max_source_interval_nodes]f64 = undefined;
            var weights: [max_source_interval_nodes]f64 = undefined;
            gauss_legendre.fillNodesAndWeights(
                @intCast(interior_level_count),
                nodes[0..interior_level_count],
                weights[0..interior_level_count],
            ) catch return error.InvalidShape;

            for (0..interior_level_count) |offset| {
                out_levels[interval_start + 1 + offset].weight_km =
                    0.5 * weights[offset] * altitude_span_km;
            }
        }

        interval_start = interval_stop;
    }
}
