const std = @import("std");

const cia_absorption = @import("cia_absorption.zig");
const jacobian_states = @import("../rtm/jacobian_states.zig");
const CostTiming = @import("../instrumentation/cost_timing.zig");
const rayleigh = @import("rayleigh.zig");
const spline = @import("../common/math/spline.zig");
const aerosol_tables = @import("../setup/aerosol_tables.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const cia_table = @import("../setup/cia_table.zig");

const max_collision_pair_profile_rows: usize = 64;
const centimeters_per_kilometer = 1.0e5;

const oxygen_volume_mixing_ratio = 0.20946;

// AerosolSupportDepth --------------------------------------------------------------------------------------- |
// Wavelength-scaled aerosol carrier values for one support row.                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] optical_depth_per_km    : f64                                                                       |
// [8..15] scattering_depth_per_km : f64                                                                       |
const AerosolSupportDepth = struct {
    optical_depth_per_km: f64 = 0.0,
    scattering_depth_per_km: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

// layer_depths.zig ------------------------------------------------------------------------------------------ |
// Converts support-row thermodynamics and caller-supplied O2 line sigma rows into optical-depth rows.         |
//                                                                                                             |
//   k_abs_gas = sigma_line * n_o2 * 1e5, k_sca_gas = sigma_R * n_air * 1e5,                                   |
//   k_cia = sigma_cia * n_pair * 1e5, then support rows multiply those per-km carriers by path length.        |
//   profile and falls back to n_o2^2 only when the profile cache is unusable.                                 |
//   time.                                                                                                     |
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
// [64..71] aerosol_scattering_optical_depth_per_km: f64                                                       |
// [72..79] total_optical_depth                    : f64                                                       |
// [80..87] total_scattering_optical_depth         : f64                                                       |
// [88..95] single_scatter_albedo                  : f64                                                       |
// [96..99] global_sublayer_index                  : u32                                                       |
// [100..103] interval_index_1based                : u32                                                       |
pub const SupportOptics = struct {
    wavelength_nm: f64,
    altitude_km: f64,
    path_length_cm: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    aerosol_scattering_optical_depth_per_km: f64,
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
// size: 152 B (0.148 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 63] scalar optical-depth fields        : 8 f64                                                       |
// [ 64..127] jacobian vectors                   : 4 * [2]f64                                                  |
// [128..135] support_start                      : usize                                                       |
// [136..143] support_count                      : usize                                                       |
// [144..147] interval_index_1based              : u32                                                         |
// [148..151] trailing padding                   : 4 B                                                         |
//                                                                                                             |
// footprint: per instance = 152 B (0.148 KiB); total = per instance * RTM layer count                         |
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
//   vertical setup profile. The O2 A diagnostic cross-section rows prove this cache is active for the O2 A    |
//   reference scene.                                                                                          |
pub const CollisionPairProfile = struct {
    node_count: usize = 0,
    altitudes_km: [max_collision_pair_profile_rows]f64 = undefined,
    log_complex_vmr_fraction: [max_collision_pair_profile_rows]f64 = undefined,
    second: [max_collision_pair_profile_rows]f64 = undefined,

    pub fn init(layer_grid: atmosphere_layers.LayerGrid) CollisionPairProfile {
        // CollisionPairProfile.init ------------------------------------------------------------------------- |
        // Prepare endpoint-secant second derivatives for the spectroscopy-profile collision complex.          |
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
        self: *const CollisionPairProfile,
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
    collision_pair_profile: *const CollisionPairProfile,
    cia: cia_table.CiaTable,
    aerosol: aerosol_tables.AerosolLayerTable,
    noalias out_support: []SupportOptics,
    stage_cost: ?CostTiming.Active,
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

    const timing_start = CostTiming.start(stage_cost);
    defer CostTiming.finish(stage_cost, timing_start, "optics_assembly");

    const rayleigh_sigma_cm2 = rayleigh.crossSectionCm2(wavelength_nm);
    const cia_coefficients = cia_absorption.interpolateCoefficients(cia.rows, wavelength_nm);
    const aerosol_weight_sum_km = aerosolSupportWeightSumKm(layer_grid, aerosol);
    const aerosol_wavelength_scale = aerosolWavelengthScale(aerosol, wavelength_nm);
    const profile_aerosol_active = aerosol.profile.len != 0;

    for (out_support, 0..) |*row, support_index| {
        const path_length_cm = @max(layer_grid.support_path_lengths_cm[support_index], 0.0);
        const weight_km = path_length_cm / centimeters_per_kilometer;
        const oxygen_density_cm3 = layer_grid.support_o2_number_densities_cm3[support_index];
        const air_density_cm3 = layer_grid.support_air_number_densities_cm3[support_index];
        const gas_absorption_per_km =
            @max(line_sigma_cm2_per_molecule[support_index], 0.0) *
            oxygen_density_cm3 *
            centimeters_per_kilometer;
        const gas_absorption = gas_absorption_per_km * weight_km;
        const gas_scattering =
            rayleigh_sigma_cm2 *
            air_density_cm3 *
            centimeters_per_kilometer *
            weight_km;
        const gas_scattering_per_km =
            rayleigh_sigma_cm2 *
            air_density_cm3 *
            centimeters_per_kilometer;
        const cia_sigma_cm5 = cia_absorption.sigmaFromCoefficients(
            cia,
            cia_coefficients,
            layer_grid.support_temperatures_k[support_index],
        );
        const cia_pair_density_cm6 = collision_pair_profile.pairDensityCm6(
            layer_grid.support_mid_altitudes_km[support_index],
            air_density_cm3,
            oxygen_density_cm3,
        );
        const cia_depth_per_km =
            cia_sigma_cm5 *
            cia_pair_density_cm6 *
            centimeters_per_kilometer;
        const cia_depth = cia_depth_per_km * weight_km;
        const aerosol_support_depth = choose_aerosol_depth: {
            if (profile_aerosol_active) {
                break :choose_aerosol_depth profileAerosolDepthAtSupport(
                    layer_grid,
                    aerosol,
                    support_index,
                    wavelength_nm,
                );
            }

            break :choose_aerosol_depth scalarAerosolDepthAtSupport(
                layer_grid,
                aerosol,
                support_index,
                aerosol_weight_sum_km,
                aerosol_wavelength_scale,
            );
        };
        const aerosol_optical_depth_per_km = aerosol_support_depth.optical_depth_per_km;
        const aerosol_depth = aerosol_optical_depth_per_km * weight_km;
        const aerosol_scattering_per_km = aerosol_support_depth.scattering_depth_per_km;
        const aerosol_scattering = aerosol_scattering_per_km * weight_km;
        const total_scattering =
            (gas_scattering_per_km + aerosol_scattering_per_km) *
            weight_km;
        const total_depth =
            (gas_absorption_per_km +
                gas_scattering_per_km +
                cia_depth_per_km +
                aerosol_optical_depth_per_km) *
            weight_km;

        row.* = .{
            .wavelength_nm = wavelength_nm,
            .altitude_km = layer_grid.support_mid_altitudes_km[support_index],
            .path_length_cm = path_length_cm,
            .gas_absorption_optical_depth = gas_absorption,
            .gas_scattering_optical_depth = gas_scattering,
            .cia_optical_depth = cia_depth,
            .aerosol_optical_depth = aerosol_depth,
            .aerosol_scattering_optical_depth = aerosol_scattering,
            .aerosol_scattering_optical_depth_per_km = aerosol_scattering_per_km,
            .total_optical_depth = total_depth,
            .total_scattering_optical_depth = total_scattering,
            .single_scatter_albedo = singleScatterAlbedo(total_scattering, total_depth),
            .global_sublayer_index = @intCast(support_index),
            .interval_index_1based = layer_grid.support_interval_indices_1based[support_index],
        };
    }
}

fn aerosolSupportWeightSumKm(
    layer_grid: atmosphere_layers.LayerGrid,
    aerosol: aerosol_tables.AerosolLayerTable,
) f64 {
    // aerosolSupportWeightSumKm ----------------------------------------------------------------------------- |
    // Sum explicit-interval support weights for scalar aerosol placement.                                     |
    //                                                                                                         |
    //   parent interval matches placement.interval_index_1based, then normalizes by max(support_weight, 0).   |
    // --------------------------------------------------------------------------------------------------------|
    if (aerosol.optical_depth <= 0.0 or aerosol.interval_index_1based == 0) return 0.0;

    var total_weight_km: f64 = 0.0;
    for (layer_grid.support_path_lengths_km, layer_grid.support_interval_indices_1based) |
        path_length_km,
        interval_index_1based,
    | {
        if (interval_index_1based != aerosol.interval_index_1based) continue;

        total_weight_km += @max(path_length_km, 0.0);
    }

    return total_weight_km;
}

fn scalarAerosolDepthAtSupport(
    layer_grid: atmosphere_layers.LayerGrid,
    aerosol: aerosol_tables.AerosolLayerTable,
    support_index: usize,
    aerosol_weight_sum_km: f64,
    wavelength_scale: f64,
) AerosolSupportDepth {
    // scalarAerosolDepthAtSupport ----------------------------------------------------------------------------|
    // Return the canonical wavelength-scaled scalar particle carriers for one support row.                    |
    //                                                                                                         |
    // math                                                                                                    |
    //   k_i(lambda) = tau_ref * (support_weight_i / sum_support_weights) / support_weight_i * scale(lambda)   |
    // --------------------------------------------------------------------------------------------------------|
    if (aerosol_weight_sum_km <= 0.0 or support_index >= layer_grid.support_path_lengths_cm.len) return .{};
    if (layer_grid.support_interval_indices_1based[support_index] != aerosol.interval_index_1based) return .{};

    const support_weight_cm = @max(layer_grid.support_path_lengths_cm[support_index], 0.0);
    const support_weight_km = @max(layer_grid.support_path_lengths_km[support_index], 0.0);
    if (support_weight_cm <= 0.0 or support_weight_km <= 0.0) return .{};

    const reference_depth = aerosol.optical_depth * (support_weight_km / aerosol_weight_sum_km);
    const path_span_km = @max(support_weight_cm / centimeters_per_kilometer, 0.0);
    const depth_per_km = if (path_span_km > 0.0) reference_depth / path_span_km else 0.0;
    const scaled_depth_per_km = if (depth_per_km == 0.0) 0.0 else depth_per_km * wavelength_scale;
    return .{
        .optical_depth_per_km = scaled_depth_per_km,
        .scattering_depth_per_km = scaled_depth_per_km * aerosol.single_scatter_albedo,
    };
}

fn aerosolWavelengthScale(aerosol: aerosol_tables.AerosolLayerTable, wavelength_nm: f64) f64 {
    // aerosolWavelengthScale -------------------------------------------------------------------------------- |
    // Apply the Angstrom reference-wavelength scaling for aerosol optical depth.                              |
    //                                                                                                         |
    //   particleWavelengthScale use the same safe wavelength/reference guard.                                 |
    // --------------------------------------------------------------------------------------------------------|
    if (aerosol.angstrom_exponent == 0.0 or aerosol.reference_wavelength_nm == wavelength_nm) return 1.0;

    const safe_wavelength_nm = @max(wavelength_nm, 1.0);
    const safe_reference_nm = @max(aerosol.reference_wavelength_nm, 1.0);
    return std.math.pow(f64, safe_reference_nm / safe_wavelength_nm, aerosol.angstrom_exponent);
}

fn profileAerosolDepthAtSupport(
    layer_grid: atmosphere_layers.LayerGrid,
    aerosol: aerosol_tables.AerosolLayerTable,
    support_index: usize,
    wavelength_nm: f64,
) AerosolSupportDepth {
    // profileAerosolDepthAtSupport ---------------------------------------------------------------------------|
    // Distribute explicit profile optical depth onto the active support rows of the owning setup layer.       |
    //                                                                                                         |
    //   profile pressure bounds with vertical-grid pressure bounds, scales each contribution by Angstrom law  |
    //   at wavelength time, and weights scattering by each row's single-scatter albedo.                       |
    //                                                                                                         |
    // math                                                                                                    |
    //   layer_tau_i = profile_tau_i * pressure_overlap_i / profile_pressure_span_i                            |
    //   support_tau_i = layer_tau_i * support_weight_km / active_layer_weight_km                              |
    //   k_tau = sum(scale(support_tau_i, wavelength_nm)) / support_weight_km                                  |
    //   k_sca = sum(scale(support_tau_i, wavelength_nm) * ssa_i) / support_weight_km                          |
    // --------------------------------------------------------------------------------------------------------|
    const owner_layer_index = findSupportOwnerLayer(layer_grid, support_index) orelse return .{};
    const support_weight_km = @max(layer_grid.support_path_lengths_km[support_index], 0.0);
    if (support_weight_km <= 0.0) return .{};

    const active_weight_sum_km = activeSupportWeightSumKm(layer_grid, owner_layer_index);
    if (active_weight_sum_km <= 0.0) return .{};

    const layer_top_pressure_hpa = layer_grid.layer_top_pressures_hpa[owner_layer_index];
    const layer_bottom_pressure_hpa = layer_grid.layer_bottom_pressures_hpa[owner_layer_index];
    var optical_depth: f64 = 0.0;
    var scattering_depth: f64 = 0.0;

    for (aerosol.profile) |profile_layer| {
        const profile_span_hpa = profile_layer.bottom_pressure_hpa - profile_layer.top_pressure_hpa;
        if (profile_span_hpa <= 0.0 or profile_layer.optical_depth <= 0.0) continue;

        const overlap_hpa = pressureOverlapHpa(
            profile_layer.top_pressure_hpa,
            profile_layer.bottom_pressure_hpa,
            layer_top_pressure_hpa,
            layer_bottom_pressure_hpa,
        );
        if (overlap_hpa <= 0.0) continue;

        const layer_reference_depth = profile_layer.optical_depth * (overlap_hpa / profile_span_hpa);
        const support_reference_depth = layer_reference_depth * (support_weight_km / active_weight_sum_km);
        const support_scaled_depth = scaleOpticalDepth(
            support_reference_depth,
            profile_layer.reference_wavelength_nm,
            profile_layer.angstrom_exponent,
            wavelength_nm,
        );
        optical_depth += support_scaled_depth;
        scattering_depth += support_scaled_depth * profile_layer.single_scatter_albedo;
    }

    return .{
        .optical_depth_per_km = optical_depth / support_weight_km,
        .scattering_depth_per_km = scattering_depth / support_weight_km,
    };
}

fn findSupportOwnerLayer(layer_grid: atmosphere_layers.LayerGrid, support_index: usize) ?usize {
    // findSupportOwnerLayer ----------------------------------------------------------------------------------|
    // Locate the setup layer whose support range owns this active support row. Boundary rows have zero path.  |
    // --------------------------------------------------------------------------------------------------------|
    const support_count: usize = @intCast(layer_grid.layer_support_count);
    for (layer_grid.layer_support_starts, 0..) |
        support_start_u32,
        layer_index,
    | {
        const support_start: usize = @intCast(support_start_u32);
        const support_end = support_start + support_count;
        if (support_index <= support_start or support_index + 1 >= support_end) continue;
        return layer_index;
    }

    return null;
}

fn activeSupportWeightSumKm(layer_grid: atmosphere_layers.LayerGrid, layer_index: usize) f64 {
    // activeSupportWeightSumKm ------------------------------------------------------------------------------ |
    // Sum non-boundary support weights for one setup layer.                                                   |
    // --------------------------------------------------------------------------------------------------------|
    const support_start: usize = @intCast(layer_grid.layer_support_starts[layer_index]);
    const support_count: usize = @intCast(layer_grid.layer_support_count);
    if (support_count <= 2) return 0.0;

    var total_weight_km: f64 = 0.0;
    for (layer_grid.support_path_lengths_km[support_start + 1 .. support_start + support_count - 1]) |
        support_weight_km,
    | {
        total_weight_km += @max(support_weight_km, 0.0);
    }
    return total_weight_km;
}

fn pressureOverlapHpa(
    left_top_hpa: f64,
    left_bottom_hpa: f64,
    right_top_hpa: f64,
    right_bottom_hpa: f64,
) f64 {
    // pressureOverlapHpa -------------------------------------------------------------------------------------|
    // Return the positive overlap of two pressure-bounded layers.                                             |
    // --------------------------------------------------------------------------------------------------------|
    return @max(@min(left_bottom_hpa, right_bottom_hpa) - @max(left_top_hpa, right_top_hpa), 0.0);
}

fn scaleOpticalDepth(
    optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    wavelength_nm: f64,
) f64 {
    // scaleOpticalDepth --------------------------------------------------------------------------------------|
    // Apply aerosol Angstrom scaling with the same safe wavelength/reference guard.                           |
    // --------------------------------------------------------------------------------------------------------|
    if (optical_depth == 0.0 or angstrom_exponent == 0.0 or reference_wavelength_nm == wavelength_nm) {
        return optical_depth;
    }

    const safe_wavelength_nm = @max(wavelength_nm, 1.0);
    const safe_reference_nm = @max(reference_wavelength_nm, 1.0);
    return optical_depth * std.math.pow(f64, safe_reference_nm / safe_wavelength_nm, angstrom_exponent);
}

pub fn reduceLayerOpticsFromSupportRows(
    layer_grid: atmosphere_layers.LayerGrid,
    support_rows: []const SupportOptics,
    out_layers: []LayerOptics,
    stage_cost: ?CostTiming.Active,
) !void {
    // reduceLayerOpticsFromSupportRows ---------------------------------------------------------------------- |
    // Sum active support rows into one LABOS transport row per layer. Boundary rows mark edges and have zero  |
    // --------------------------------------------------------------------------------------------------------|
    if (out_layers.len != layer_grid.layer_pressures_hpa.len or
        support_rows.len != layer_grid.support_mid_altitudes_km.len)
    {
        return error.InvalidShape;
    }

    const timing_start = CostTiming.start(stage_cost);
    defer CostTiming.finish(stage_cost, timing_start, "quadrature_build");

    for (out_layers, 0..) |*layer, layer_index| {
        const support_start: usize = @intCast(layer_grid.layer_support_starts[layer_index]);
        const support_count: usize = @intCast(layer_grid.layer_support_count);
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

pub fn fillLayerAerosolJacobians(
    aerosol: aerosol_tables.AerosolLayerTable,
    layers: []LayerOptics,
) void {
    // fillLayerAerosolJacobians ----------------------------------------------------------------------------- |
    // Fill aerosol optical-depth derivative lanes on already-reduced layer rows.                              |
    //                                                                                                         |
    //   route writes total optical depth, scattering optical depth, and single-scatter albedo derivatives     |
    //   beside each LayerInput row. It has no layer aerosol phase-weight derivative field, so that vector     |
    //   remains zero here.                                                                                    |
    //                                                                                                         |
    // math                                                                                                    |
    //   d_tau / d_tau_aer = tau_aerosol_layer / tau_aer                                                       |
    //   d_sca / d_tau_aer = sca_aerosol_layer / tau_aer                                                       |
    //   d_ssa / d_tau_aer = (d_sca * tau_total - sca_total * d_tau) / tau_total^2                             |
    // --------------------------------------------------------------------------------------------------------|
    for (layers) |*layer| {
        layer.optical_depth_jacobian = jacobian_states.zero();
        layer.scattering_optical_depth_jacobian = jacobian_states.zero();
        layer.single_scatter_albedo_jacobian = jacobian_states.zero();
        layer.aerosol_phase_weight_jacobian = jacobian_states.zero();
    }

    if (aerosol.profile.len != 0) return;
    if (aerosol.optical_depth <= 0.0) return;

    for (layers) |*layer| {
        const optical_derivative = layer.aerosol_optical_depth / aerosol.optical_depth;
        const scattering_derivative = layer.aerosol_scattering_optical_depth / aerosol.optical_depth;
        jacobian_states.set(
            &layer.optical_depth_jacobian,
            .aerosol_optical_depth,
            optical_derivative,
        );
        jacobian_states.set(
            &layer.scattering_optical_depth_jacobian,
            .aerosol_optical_depth,
            scattering_derivative,
        );

        if (layer.total_optical_depth <= 0.0) continue;

        const ssa_derivative =
            (scattering_derivative * layer.total_optical_depth -
                layer.total_scattering_optical_depth * optical_derivative) /
            (layer.total_optical_depth * layer.total_optical_depth);
        jacobian_states.set(
            &layer.single_scatter_albedo_jacobian,
            .aerosol_optical_depth,
            ssa_derivative,
        );
    }
}

fn singleScatterAlbedo(scattering_optical_depth: f64, total_optical_depth: f64) f64 {
    // singleScatterAlbedo ------------------------------------------------------------------------------------|
    // Clamp the local scattering fraction to the physical single-scatter-albedo interval.                     |
    // --------------------------------------------------------------------------------------------------------|
    if (total_optical_depth <= 0.0) return 0.0;
    return std.math.clamp(scattering_optical_depth / total_optical_depth, 0.0, 1.0);
}
