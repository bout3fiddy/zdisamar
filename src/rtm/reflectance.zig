const std = @import("std");

const controls = @import("controls.zig");
const gauss_angles = @import("gauss_angles.zig");
const layer_depths = @import("../optics/layer_depths.zig");
const phase_basis = @import("phase_basis.zig");
const phase_table = @import("../setup/phase_table.zig");
const rows = @import("rows.zig");
const source_levels = @import("../optics/source_levels.zig");
const Perturbation = @import("../instrumentation/sensitivity.zig");
const Telemetry = @import("../instrumentation/telemetry.zig");
const Trace = @import("../instrumentation/trace.zig");

const math = std.math;
const direction_cosine_floor: f64 = 1.0e-12;
const phase_support_floor: f64 = 1.0e-12;
const earth_radius_km: f64 = 6371.0;

// reflectance.zig ------------------------------------------------------------------------------------------- |
// Converts LABOS order fields into Fourier reflectance terms and small solve-level reflectance helpers.       |
//                                                                                                             |
//   weighted-term perturbation, and aerosol derivative weighting.                                             |
//                                                                                                             |
// reference names                                                                                             |
//   rho_m : reflectance coefficient for one Fourier term before azimuthal weighting                           |
//   c_m   : Fourier weight, 1 for m=0 and 2*cos(m*dphi) for m>0                                               |
//   UD_fc : accumulated upward/downward radiation field from scattering orders                                |
//                                                                                                             |
// math                                                                                                        |
//   reflectance += c_m * rho_m                                                                                |
//   tail_break = m >= fourier_floor_scalar and abs(rho_m) <= fourier_tail_reflectance_epsilon                 |
// ------------------------------------------------------------------------------------------------------------|

// FourierContribution --------------------------------------------------------------------------------------- |
// One Fourier term after azimuthal weighting and tail-stop classification.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] weight     : f64                                                                                   |
// [ 8..15] rho_m      : f64                                                                                   |
// [16..23] weighted   : f64                                                                                   |
// [24..24] tail_break : bool                                                                                  |
// [25..31] padding    : 7 B                                                                                   |
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// footprint: per instance = 32 B (0.031 KiB); stack row per Fourier term                                      |
pub const FourierContribution = struct {
    weight: f64,
    rho_m: f64,
    weighted: f64,
    tail_break: bool,
};
// ------------------------------------------------------------------------------------------------------------|

// PhaseRows ------------------------------------------------------------------------------------------------- |
// Borrowed Z+/Z- row slices; storage lives in a nearby PhaseKernelRow or PhaseRowCache.                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] zplus : []const f64                                                                                |
// [16..31] zmin  : []const f64                                                                                |
//                                                                                                             |
// footprint: per instance = 32 B (0.031 KiB); referenced storage remains outside this row                     |
const PhaseRows = struct {
    zplus: []const f64,
    zmin: []const f64,
};
// ------------------------------------------------------------------------------------------------------------|

// PhaseRowCache --------------------------------------------------------------------------------------------- |
// Inline Z+/Z- row cache for one Fourier term's aerosol weighting.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2408 B (2.352 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..2399] rows : [12]PhaseKernelRow                                                                      |
// [2400..2407] n    : usize                                                                                   |
//                                                                                                             |
// footprint: per instance = 2408 B (2.352 KiB); one stack value for paired aerosol derivative weighting       |
const PhaseRowCache = struct {
    rows: [gauss_angles.max_stream_count]phase_basis.PhaseKernelRow,
    n: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// UnitPhase ------------------------------------------------------------------------------------------------- |
// Aerosol phase coefficient row plus its active coefficient ceiling.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] coefficients : *const [151]f64                                                                     |
// [ 8..15] max_index    : usize                                                                               |
//                                                                                                             |
// footprint: per instance = 16 B (0.016 KiB); coefficient storage is borrowed from PhaseTable                 |
const UnitPhase = struct {
    coefficients: *const [phase_table.coefficient_count]f64,
    max_index: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// AerosolDerivativeWeighting -------------------------------------------------------------------------------- |
// Paired integrated-source aerosol Jacobian contribution for one Fourier term.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] aerosol_optical_depth          : f64                                                               |
// [ 8..15] aerosol_layer_mid_pressure_hpa : f64                                                               |
//                                                                                                             |
// footprint: per instance = 16 B (0.016 KiB); stack return value                                              |
pub const AerosolDerivativeWeighting = struct {
    aerosol_optical_depth: f64 = 0.0,
    aerosol_layer_mid_pressure_hpa: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

// ScatteringSourceRowSums ----------------------------------------------------------------------------------- |
// Solar-column contractions reused by aerosol scattering-source weighting.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] pplusplus_ed : f64                                                                                 |
// [ 8..15] pminplus_ed  : f64                                                                                 |
// [16..23] pminmin_u    : f64                                                                                 |
// [24..31] pplusmin_u   : f64                                                                                 |
//                                                                                                             |
// footprint: per instance = 32 B (0.031 KiB); one stack row per phase/source contraction                      |
const ScatteringSourceRowSums = struct {
    pplusplus_ed: f64,
    pminplus_ed: f64,
    pminmin_u: f64,
    pplusmin_u: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// AerosolIntervalBounds ------------------------------------------------------------------------------------- |
// Bounding source-level interfaces around the active aerosol derivative levels.                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] bottom : usize                                                                                      |
// [8..15] top    : usize                                                                                      |
//                                                                                                             |
// footprint: per instance = 16 B (0.016 KiB); one stack row per active aerosol interval                       |
const AerosolIntervalBounds = struct {
    bottom: usize,
    top: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// InterfaceWeighting ---------------------------------------------------------------------------------------- |
// Scattering-coefficient and absorption terms for the same aerosol interface.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] scattering_coefficient : f64                                                                       |
// [ 8..15] absorption             : f64                                                                       |
//                                                                                                             |
// footprint: per instance = 16 B (0.016 KiB); one stack row per interface weighting                           |
const InterfaceWeighting = struct {
    scattering_coefficient: f64,
    absorption: f64,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn topReflectanceCoefficient(
    ud: []const rows.UDField,
    top_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
) f64 {
    // topReflectanceCoefficient ----------------------------------------------------------------------------- |
    // Non-integrated LABOS reflectance for one Fourier term.                                                  |
    //                                                                                                         |
    // zdisamar matches `CalcReflectance`: read upward U at the top level, solar column, viewing stream.       |
    // --------------------------------------------------------------------------------------------------------|
    const solar_column: usize = 1;
    return ud[top_level].U.col[solar_column].get(geometry.viewIndex());
}

pub fn integratedSourceCoefficient(
    layers: []const layer_depths.LayerOptics,
    levels: []const source_levels.SourceLevel,
    ud: []const rows.UDField,
    top_level: usize,
    fourier_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const phase_basis.FourierPlmBasis,
    phase: phase_table.PhaseTable,
    source_phase_max_indices: []const usize,
) f64 {
    // integratedSourceCoefficient --------------------------------------------------------------------------- |
    // Integrated-source LABOS reflectance for one Fourier term.                                               |
    //                                                                                                         |
    //   `SourceLevel` rows. This route uses the RTM-quadrature branch: level weight, scattering carrier, |
    //   and source phase mixture are already explicit on each source level.                                   |
    //                                                                                                         |
    // math                                                                                                    |
    //   rho_m += weight_km * E_view * k_sca * (PminusD + PplusU)                                              |
    //                                                                                                         |
    //   Pminus = 0.25 * Zmin  / (mu_view * mu_source)                                                         |
    //   Pplus  = 0.25 * Zplus / (mu_view * mu_source)                                                         |
    // --------------------------------------------------------------------------------------------------------|
    _ = layers;
    if (levels.len < top_level + 1 or
        ud.len < top_level + 1 or
        source_phase_max_indices.len < top_level + 1)
    {
        return 0.0;
    }

    const solar_column: usize = 1;
    const view_index = geometry.viewIndex();
    const solar_index = geometry.solarIndex();
    const view_mu = @max(geometry.u[view_index], direction_cosine_floor);
    var reflectance: f64 = 0.0;

    for (0..top_level + 1) |level_index| {
        const source = levels[level_index];
        if (source.weight_km <= 0.0 or source.scattering_per_km <= 0.0) continue;

        const source_max_phase_index = source_phase_max_indices[level_index];
        if (fourier_index > source_max_phase_index) continue;

        const phase_row = phase_basis.fillZplusZminRowFromWeightedPhaseLimited(
            fourier_index,
            source.phase_aerosol_weight,
            source.phase_rayleigh2_weight,
            &phase.aerosol_phase_coefficients,
            source_max_phase_index,
            geometry,
            plm_basis,
            view_index,
        );
        const level = ud[level_index];
        const level_d = level.D.col[solar_column].data;
        const level_u = level.U.col[solar_column].data;

        var pminus_down: f64 = 0.0;
        for (0..geometry.n_gauss) |gauss_index| {
            const mu = @max(geometry.u[gauss_index], direction_cosine_floor);
            const pminus = (0.25 * phase_row.zmin[gauss_index] / view_mu) / mu;
            pminus_down += pminus * level_d[gauss_index];
        }

        const solar_mu = @max(geometry.u[solar_index], direction_cosine_floor);
        const pminus_direct = (0.25 * phase_row.zmin[solar_index] / view_mu) / solar_mu;
        pminus_down += pminus_direct * level.E.data[solar_index];

        var pplus_up: f64 = 0.0;
        for (0..geometry.n_gauss) |gauss_index| {
            const mu = @max(geometry.u[gauss_index], direction_cosine_floor);
            const pplus = (0.25 * phase_row.zplus[gauss_index] / view_mu) / mu;
            pplus_up += pplus * level_u[gauss_index];
        }

        const contribution = level.E.data[view_index] *
            source.scattering_per_km *
            (pminus_down + pplus_up);
        reflectance += source.weight_km * contribution;
    }

    if (fourier_index == 0) {
        reflectance += ud[0].E.get(view_index) * ud[0].U.col[solar_column].get(view_index);
    }

    return reflectance;
}

pub fn integratedAerosolDerivativeWeighting(
    layers: []const layer_depths.LayerOptics,
    levels: []const source_levels.SourceLevel,
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
    top_level: usize,
    fourier_index: usize,
    use_pseudo_spherical: bool,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const phase_basis.FourierPlmBasis,
    phase: phase_table.PhaseTable,
) AerosolDerivativeWeighting {
    // integratedAerosolDerivativeWeighting ------------------------------------------------------------------ |
    // Paired integrated-source aerosol Jacobian weighting for AOD and aerosol layer pressure.                 |
    //                                                                                                         |
    //   `SourceLevel` carries the RTM quadrature aerosol k_sca carriers and dksca/dtau row.                   |
    // --------------------------------------------------------------------------------------------------------|
    if (!validSourceGrid(levels, ud, top_level)) return .{};

    const bounds = activeAerosolInteriorBounds(levels, top_level) orelse return .{
        .aerosol_optical_depth = integratedAerosolOpticalDepthWeighting(
            layers,
            levels,
            ud,
            ud_sum_local,
            top_level,
            fourier_index,
            use_pseudo_spherical,
            geometry,
            plm_basis,
            phase,
        ),
    };

    var phase_row_storage: PhaseRowCache = undefined;
    const phase_rows = cachedCommonAerosolPhaseRows(
        levels,
        bounds,
        fourier_index,
        geometry,
        plm_basis,
        phase,
        &phase_row_storage,
    ) orelse return .{
        .aerosol_optical_depth = integratedAerosolOpticalDepthWeighting(
            layers,
            levels,
            ud,
            ud_sum_local,
            top_level,
            fourier_index,
            use_pseudo_spherical,
            geometry,
            plm_basis,
            phase,
        ),
        .aerosol_layer_mid_pressure_hpa = integratedAerosolLayerPressureShiftWeighting(
            layers,
            levels,
            ud,
            ud_sum_local,
            top_level,
            fourier_index,
            use_pseudo_spherical,
            geometry,
            plm_basis,
            phase,
        ),
    };

    return .{
        .aerosol_optical_depth = aerosolOpticalDepthWeightingFromPhaseRows(
            layers,
            levels,
            ud,
            ud_sum_local,
            bounds,
            use_pseudo_spherical,
            geometry,
            phase_rows,
        ),
        .aerosol_layer_mid_pressure_hpa = aerosolLayerPressureShiftWeightingFromPhaseRows(
            layers,
            levels,
            ud,
            ud_sum_local,
            bounds,
            use_pseudo_spherical,
            geometry,
            phase_rows,
        ),
    };
}

pub fn integratedAerosolOpticalDepthWeighting(
    layers: []const layer_depths.LayerOptics,
    levels: []const source_levels.SourceLevel,
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
    top_level: usize,
    fourier_index: usize,
    use_pseudo_spherical: bool,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const phase_basis.FourierPlmBasis,
    phase: phase_table.PhaseTable,
) f64 {
    // integratedAerosolOpticalDepthWeighting ---------------------------------------------------------------- |
    // Integrated-source aerosol optical-depth Jacobian weighting for one Fourier term.                        |
    //                                                                                                         |
    //                                                                                                         |
    // math                                                                                                    |
    //   AOD weighting = integral(interface weighting dz) / aerosol layer thickness                            |
    //   fallback += weight_km * dksca/dtau * (source weighting + absorption weighting)                        |
    // --------------------------------------------------------------------------------------------------------|
    if (!validSourceGrid(levels, ud, top_level)) return 0.0;

    if (activeAerosolInteriorBounds(levels, top_level)) |bounds| {
        if (bounds.top <= bounds.bottom + 1) return 0.0;

        const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);
        const needs_absorption_weighting = (1.0 - aerosol_ssa) != 0.0;
        const denominator = levels[bounds.top - 1].altitude_km - levels[bounds.bottom].altitude_km;
        if (denominator <= 0.0) return 0.0;

        const cached_phase_rows: ?PhaseRowCache = choose_phase_cache: {
            const unit_phase = commonActiveAerosolUnitPhase(levels, bounds, &phase) orelse
                break :choose_phase_cache null;
            if (fourier_index > unit_phase.max_index) return 0.0;

            break :choose_phase_cache buildPhaseRowCache(
                unit_phase.coefficients,
                unit_phase.max_index,
                fourier_index,
                geometry,
                plm_basis,
            );
        };

        var integral: f64 = 0.0;
        const previous_scattering = choose_bottom_scattering: {
            if (cached_phase_rows) |phase_rows| {
                break :choose_bottom_scattering scatteringCoefficientInterfaceWeightingFromPhaseRows(
                    &phase_rows,
                    ud,
                    ud_sum_local,
                    levels,
                    bounds.bottom,
                    use_pseudo_spherical,
                    geometry,
                );
            }

            break :choose_bottom_scattering scatteringCoefficientInterfaceWeighting(
                levels[bounds.bottom].aerosol_ksca_above_per_km,
                ud,
                ud_sum_local,
                levels,
                bounds.bottom,
                fourier_index,
                use_pseudo_spherical,
                geometry,
                plm_basis,
                phase,
            );
        };
        const previous_absorption = choose_bottom_absorption: {
            if (!needs_absorption_weighting) break :choose_bottom_absorption 0.0;
            break :choose_bottom_absorption absorptionInterfaceWeighting(
                ud,
                ud_sum_local,
                levels,
                bounds.bottom,
                use_pseudo_spherical,
                geometry,
            );
        };
        var previous = aerosolTotalExtinctionInterfaceWeighting(
            previous_scattering,
            previous_absorption,
            aerosol_ssa,
        );

        for (bounds.bottom + 1..bounds.top) |level_index| {
            const current_scattering = choose_level_scattering: {
                if (cached_phase_rows) |phase_rows| {
                    break :choose_level_scattering scatteringCoefficientInterfaceWeightingFromPhaseRows(
                        &phase_rows,
                        ud,
                        ud_sum_local,
                        levels,
                        level_index,
                        use_pseudo_spherical,
                        geometry,
                    );
                }

                break :choose_level_scattering scatteringCoefficientInterfaceWeighting(
                    levels[level_index].aerosol_ksca_above_per_km,
                    ud,
                    ud_sum_local,
                    levels,
                    level_index,
                    fourier_index,
                    use_pseudo_spherical,
                    geometry,
                    plm_basis,
                    phase,
                );
            };

            const current_absorption = choose_level_absorption: {
                if (!needs_absorption_weighting) break :choose_level_absorption 0.0;

                break :choose_level_absorption absorptionInterfaceWeighting(
                    ud,
                    ud_sum_local,
                    levels,
                    level_index,
                    use_pseudo_spherical,
                    geometry,
                );
            };

            const current = aerosolTotalExtinctionInterfaceWeighting(
                current_scattering,
                current_absorption,
                aerosol_ssa,
            );

            const dz = levels[level_index].altitude_km - levels[level_index - 1].altitude_km;
            if (dz > 0.0) integral += 0.5 * (previous + current) * dz;

            previous = current;
        }

        return integral / denominator;
    }

    var weighting: f64 = 0.0;
    const unit_phase = unitAerosolPhase(&phase) orelse return 0.0;
    for (0..top_level + 1) |level_index| {
        const source = levels[level_index];
        if (source.weight_km <= 0.0 or source.aerosol_ksca_jacobian == 0.0) continue;
        if (fourier_index > unit_phase.max_index) continue;

        const d_sca_d_tau = source.aerosol_ksca_jacobian;
        const source_weighting = d_sca_d_tau * scatteringSourceWeightingFromScaledPhase(
            unit_phase.coefficients,
            unit_phase.max_index,
            ud,
            level_index,
            fourier_index,
            geometry,
            plm_basis,
        );
        const extinction_weighting = d_sca_d_tau * absorptionInterfaceWeighting(
            ud,
            ud_sum_local,
            levels,
            level_index,
            use_pseudo_spherical,
            geometry,
        );
        weighting += source.weight_km * (source_weighting + extinction_weighting);
    }
    return weighting;
}

pub fn integratedAerosolLayerPressureShiftWeighting(
    layers: []const layer_depths.LayerOptics,
    levels: []const source_levels.SourceLevel,
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
    top_level: usize,
    fourier_index: usize,
    use_pseudo_spherical: bool,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const phase_basis.FourierPlmBasis,
    phase: phase_table.PhaseTable,
) f64 {
    // integratedAerosolLayerPressureShiftWeighting ---------------------------------------------------------- |
    // Integrated-source aerosol layer-pressure weighting for one Fourier term.                                |
    //                                                                                                         |
    //   `calcAerosolLayerPressureShiftWeightingWithBasis`.                                                    |
    //                                                                                                         |
    // math                                                                                                    |
    //   k_abs = k_sca * (1 - SSA) / SSA                                                                       |
    //   pressure weighting = (top_sca - bottom_sca) * k_sca + (top_abs - bottom_abs) * k_abs                  |
    // --------------------------------------------------------------------------------------------------------|
    if (!validSourceGrid(levels, ud, top_level)) return 0.0;

    const bounds = activeAerosolInteriorBounds(levels, top_level) orelse return 0.0;
    const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);
    const top_sca_weighting = scatteringCoefficientInterfaceWeighting(
        levels[bounds.top].aerosol_ksca_below_per_km,
        ud,
        ud_sum_local,
        levels,
        bounds.top,
        fourier_index,
        use_pseudo_spherical,
        geometry,
        plm_basis,
        phase,
    );
    const bottom_sca_weighting = scatteringCoefficientInterfaceWeighting(
        levels[bounds.bottom].aerosol_ksca_above_per_km,
        ud,
        ud_sum_local,
        levels,
        bounds.bottom,
        fourier_index,
        use_pseudo_spherical,
        geometry,
        plm_basis,
        phase,
    );

    const ksca = levels[bounds.top].aerosol_ksca_below_per_km;
    const kabs = if (aerosol_ssa > 0.0) ksca * (1.0 - aerosol_ssa) / aerosol_ssa else 0.0;
    const scattering_pressure_weighting = (top_sca_weighting - bottom_sca_weighting) * ksca;
    if (kabs == 0.0) return scattering_pressure_weighting;

    const top_abs_weighting = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        levels,
        bounds.top,
        use_pseudo_spherical,
        geometry,
    );
    const bottom_abs_weighting = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        levels,
        bounds.bottom,
        use_pseudo_spherical,
        geometry,
    );
    return scattering_pressure_weighting + (top_abs_weighting - bottom_abs_weighting) * kabs;
}

fn validSourceGrid(
    levels: []const source_levels.SourceLevel,
    ud: []const rows.UDField,
    top_level: usize,
) bool {
    // validSourceGrid --------------------------------------------------------------------------------------- |
    // Check the integrated-source slices before helpers index top_level.                                      |
    // --------------------------------------------------------------------------------------------------------|
    return levels.len >= top_level + 1 and ud.len >= top_level + 1;
}

fn activeAerosolInteriorBounds(
    levels: []const source_levels.SourceLevel,
    top_level: usize,
) ?AerosolIntervalBounds {
    // activeAerosolInteriorBounds --------------------------------------------------------------------------  |
    // Find active aerosol derivative levels and expand to their bounding interfaces.                          |
    // --------------------------------------------------------------------------------------------------------|
    var first_active: ?usize = null;
    var last_active: ?usize = null;

    for (0..top_level + 1) |level_index| {
        if (levels[level_index].aerosol_ksca_jacobian <= 0.0) continue;
        if (first_active == null) first_active = level_index;
        last_active = level_index;
    }

    const first = first_active orelse return null;
    const last = last_active orelse return null;
    if (first == 0 or last + 1 > top_level) return null;
    return .{ .bottom = first - 1, .top = last + 1 };
}

fn aerosolSingleScatteringAlbedo(layers: []const layer_depths.LayerOptics) f64 {
    // aerosolSingleScatteringAlbedo ------------------------------------------------------------------------  |
    // Collapse layer aerosol extinction and scattering totals into one effective aerosol SSA.                 |
    // --------------------------------------------------------------------------------------------------------|
    var aerosol_optical_depth: f64 = 0.0;
    var aerosol_scattering_optical_depth: f64 = 0.0;
    for (layers) |*layer| {
        aerosol_optical_depth += @max(layer.aerosol_optical_depth, 0.0);
        aerosol_scattering_optical_depth += @max(layer.aerosol_scattering_optical_depth, 0.0);
    }
    if (aerosol_optical_depth <= 0.0) return 1.0;
    return math.clamp(aerosol_scattering_optical_depth / aerosol_optical_depth, 0.0, 1.0);
}

fn unitAerosolPhase(phase: *const phase_table.PhaseTable) ?UnitPhase {
    // unitAerosolPhase -------------------------------------------------------------------------------------  |
    // Return the aerosol phase expansion when the coefficient row is active.                                  |
    // --------------------------------------------------------------------------------------------------------|
    if (phase.aerosol_phase_coefficients[0] <= 0.0) return null;
    return .{
        .coefficients = &phase.aerosol_phase_coefficients,
        .max_index = phase.aerosol_phase_max_index,
    };
}

fn commonActiveAerosolUnitPhase(
    levels: []const source_levels.SourceLevel,
    bounds: AerosolIntervalBounds,
    phase: *const phase_table.PhaseTable,
) ?UnitPhase {
    // commonActiveAerosolUnitPhase -------------------------------------------------------------------------  |
    // Return the common aerosol phase row when any active interface carries aerosol scattering.               |
    // --------------------------------------------------------------------------------------------------------|
    for (bounds.bottom..bounds.top) |level_index| {
        if (levels[level_index].aerosol_ksca_above_per_km > 0.0) return unitAerosolPhase(phase);
    }
    return null;
}

fn buildPhaseRowCache(
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    fourier_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const phase_basis.FourierPlmBasis,
) PhaseRowCache {
    // buildPhaseRowCache -----------------------------------------------------------------------------------  |
    // Build Z+/Z- rows for every active stream/view/solar row used by aerosol weighting.                      |
    // --------------------------------------------------------------------------------------------------------|
    var cache = PhaseRowCache{
        .rows = undefined,
        .n = geometry.stream_count,
    };
    for (0..geometry.stream_count) |row_index| {
        cache.rows[row_index] = phase_basis.fillZplusZminRowFromBasisLimited(
            fourier_index,
            phase_coefficients,
            max_phase_index,
            geometry,
            plm_basis,
            row_index,
        );
        cache.n = cache.rows[row_index].n;
    }
    return cache;
}

fn cachedCommonAerosolPhaseRows(
    levels: []const source_levels.SourceLevel,
    bounds: AerosolIntervalBounds,
    fourier_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const phase_basis.FourierPlmBasis,
    phase: phase_table.PhaseTable,
    storage: *PhaseRowCache,
) ?*const PhaseRowCache {
    // cachedCommonAerosolPhaseRows -------------------------------------------------------------------------  |
    // Build a shared aerosol phase-row cache only when this Fourier term can contribute.                      |
    // --------------------------------------------------------------------------------------------------------|
    const unit_phase = commonActiveAerosolUnitPhase(levels, bounds, &phase) orelse return null;
    if (fourier_index > unit_phase.max_index) return null;
    storage.* = buildPhaseRowCache(unit_phase.coefficients, unit_phase.max_index, fourier_index, geometry, plm_basis);
    return storage;
}

fn aerosolOpticalDepthWeightingFromPhaseRows(
    layers: []const layer_depths.LayerOptics,
    levels: []const source_levels.SourceLevel,
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
    bounds: AerosolIntervalBounds,
    use_pseudo_spherical: bool,
    geometry: *const gauss_angles.GaussGeometry,
    phase_rows: *const PhaseRowCache,
) f64 {
    // aerosolOpticalDepthWeightingFromPhaseRows ------------------------------------------------------------  |
    // Cached-row AOD weighting over the active aerosol interval.                                              |
    // --------------------------------------------------------------------------------------------------------|
    if (bounds.top <= bounds.bottom + 1) return 0.0;
    const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);
    const needs_absorption_weighting = (1.0 - aerosol_ssa) != 0.0;
    const denominator = levels[bounds.top - 1].altitude_km - levels[bounds.bottom].altitude_km;
    if (denominator <= 0.0) return 0.0;

    var integral: f64 = 0.0;

    const previous_weighting = interfaceWeightingFromPhaseRows(
        phase_rows,
        ud,
        ud_sum_local,
        levels,
        bounds.bottom,
        use_pseudo_spherical,
        geometry,
    );

    var previous = aerosolTotalExtinctionInterfaceWeighting(
        previous_weighting.scattering_coefficient,
        if (needs_absorption_weighting) previous_weighting.absorption else 0.0,
        aerosol_ssa,
    );
    for (bounds.bottom + 1..bounds.top) |level_index| {
        const current_weighting = interfaceWeightingFromPhaseRows(
            phase_rows,
            ud,
            ud_sum_local,
            levels,
            level_index,
            use_pseudo_spherical,
            geometry,
        );

        const current = aerosolTotalExtinctionInterfaceWeighting(
            current_weighting.scattering_coefficient,
            if (needs_absorption_weighting) current_weighting.absorption else 0.0,
            aerosol_ssa,
        );
        const dz = levels[level_index].altitude_km - levels[level_index - 1].altitude_km;
        if (dz > 0.0) integral += 0.5 * (previous + current) * dz;

        previous = current;
    }

    return integral / denominator;
}

fn aerosolLayerPressureShiftWeightingFromPhaseRows(
    layers: []const layer_depths.LayerOptics,
    levels: []const source_levels.SourceLevel,
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
    bounds: AerosolIntervalBounds,
    use_pseudo_spherical: bool,
    geometry: *const gauss_angles.GaussGeometry,
    phase_rows: *const PhaseRowCache,
) f64 {
    // aerosolLayerPressureShiftWeightingFromPhaseRows ------------------------------------------------------  |
    // Cached-row pressure-shift weighting from top-minus-bottom interface sensitivity.                        |
    // --------------------------------------------------------------------------------------------------------|
    const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);
    const top_has_scattering = levels[bounds.top].aerosol_ksca_below_per_km > 0.0;
    const bottom_has_scattering = levels[bounds.bottom].aerosol_ksca_above_per_km > 0.0;

    const top_interface: ?InterfaceWeighting = choose_top_interface: {
        if (!top_has_scattering) break :choose_top_interface null;

        break :choose_top_interface interfaceWeightingFromPhaseRows(
            phase_rows,
            ud,
            ud_sum_local,
            levels,
            bounds.top,
            use_pseudo_spherical,
            geometry,
        );
    };

    const bottom_interface: ?InterfaceWeighting = choose_bottom_interface: {
        if (!bottom_has_scattering) break :choose_bottom_interface null;

        break :choose_bottom_interface interfaceWeightingFromPhaseRows(
            phase_rows,
            ud,
            ud_sum_local,
            levels,
            bounds.bottom,
            use_pseudo_spherical,
            geometry,
        );
    };

    const top_sca_weighting = if (top_interface) |weighting| weighting.scattering_coefficient else 0.0;
    const bottom_sca_weighting = if (bottom_interface) |weighting| weighting.scattering_coefficient else 0.0;
    const ksca = levels[bounds.top].aerosol_ksca_below_per_km;
    const kabs = if (aerosol_ssa > 0.0) ksca * (1.0 - aerosol_ssa) / aerosol_ssa else 0.0;
    const scattering_pressure_weighting = (top_sca_weighting - bottom_sca_weighting) * ksca;
    if (kabs == 0.0) return scattering_pressure_weighting;

    const top_abs_weighting = choose_top_absorption: {
        if (top_interface) |weighting| break :choose_top_absorption weighting.absorption;

        break :choose_top_absorption absorptionInterfaceWeighting(
            ud,
            ud_sum_local,
            levels,
            bounds.top,
            use_pseudo_spherical,
            geometry,
        );
    };

    const bottom_abs_weighting = choose_bottom_absorption: {
        if (bottom_interface) |weighting| break :choose_bottom_absorption weighting.absorption;

        break :choose_bottom_absorption absorptionInterfaceWeighting(
            ud,
            ud_sum_local,
            levels,
            bounds.bottom,
            use_pseudo_spherical,
            geometry,
        );
    };

    return scattering_pressure_weighting + (top_abs_weighting - bottom_abs_weighting) * kabs;
}

fn scatteringCoefficientInterfaceWeighting(
    aerosol_ksca_per_km: f64,
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
    levels: []const source_levels.SourceLevel,
    level_index: usize,
    fourier_index: usize,
    use_pseudo_spherical: bool,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const phase_basis.FourierPlmBasis,
    phase: phase_table.PhaseTable,
) f64 {
    // scatteringCoefficientInterfaceWeighting --------------------------------------------------------------  |
    // Source plus absorption weighting for one aerosol scattering-coefficient perturbation.                   |
    // --------------------------------------------------------------------------------------------------------|
    if (aerosol_ksca_per_km <= 0.0) return 0.0;

    const unit_phase = unitAerosolPhase(&phase) orelse return 0.0;
    if (fourier_index > unit_phase.max_index) return 0.0;

    const source_weighting = scatteringSourceWeightingFromScaledPhase(
        unit_phase.coefficients,
        unit_phase.max_index,
        ud,
        level_index,
        fourier_index,
        geometry,
        plm_basis,
    );
    const absorption_weighting = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        levels,
        level_index,
        use_pseudo_spherical,
        geometry,
    );
    return source_weighting + absorption_weighting;
}

fn scatteringCoefficientInterfaceWeightingFromPhaseRows(
    phase_rows: *const PhaseRowCache,
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
    levels: []const source_levels.SourceLevel,
    level_index: usize,
    use_pseudo_spherical: bool,
    geometry: *const gauss_angles.GaussGeometry,
) f64 {
    // scatteringCoefficientInterfaceWeightingFromPhaseRows -------------------------------------------------  |
    // Cached-row source plus absorption weighting for one aerosol scattering interface.                       |
    // --------------------------------------------------------------------------------------------------------|
    const weighting = interfaceWeightingFromPhaseRows(
        phase_rows,
        ud,
        ud_sum_local,
        levels,
        level_index,
        use_pseudo_spherical,
        geometry,
    );
    return weighting.scattering_coefficient;
}

fn interfaceWeightingFromPhaseRows(
    phase_rows: *const PhaseRowCache,
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
    levels: []const source_levels.SourceLevel,
    level_index: usize,
    use_pseudo_spherical: bool,
    geometry: *const gauss_angles.GaussGeometry,
) InterfaceWeighting {
    // interfaceWeightingFromPhaseRows ----------------------------------------------------------------------  |
    // Evaluate scattering-source and absorption terms once for paired aerosol Jacobians.                      |
    // --------------------------------------------------------------------------------------------------------|
    const source = scatteringSourceWeightingFromPhaseRows(
        phase_rows,
        ud,
        level_index,
        geometry,
    );
    const absorption = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        levels,
        level_index,
        use_pseudo_spherical,
        geometry,
    );
    return .{
        .scattering_coefficient = source + absorption,
        .absorption = absorption,
    };
}

fn aerosolTotalExtinctionInterfaceWeighting(
    scattering_weighting: f64,
    absorption_weighting: f64,
    aerosol_ssa: f64,
) f64 {
    // aerosolTotalExtinctionInterfaceWeighting -------------------------------------------------------------  |
    // Blend scattering and absorption terms using aerosol single-scattering albedo.                           |
    // --------------------------------------------------------------------------------------------------------|
    return aerosol_ssa * scattering_weighting + (1.0 - aerosol_ssa) * absorption_weighting;
}

fn scatteringSourceWeightingFromPhaseRows(
    phase_rows: *const PhaseRowCache,
    ud: []const rows.UDField,
    level_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
) f64 {
    // scatteringSourceWeightingFromPhaseRows ---------------------------------------------------------------  |
    // Cached-row scattering-source weighting for one interface.                                               |
    // --------------------------------------------------------------------------------------------------------|
    const view_column: usize = 0;
    const view_index = geometry.viewIndex();
    const level = &ud[level_index];
    var sum: f64 = 0.0;

    for (0..geometry.n_gauss) |row_index| {
        const cached_row = &phase_rows.rows[row_index];
        const row = scatteringSourceRowSumsFromRows(
            .{
                .zplus = cached_row.zplus[0..phase_rows.n],
                .zmin = cached_row.zmin[0..phase_rows.n],
            },
            level,
            geometry,
            row_index,
        );
        sum += level.D.col[view_column].get(row_index) * (row.pminplus_ed + row.pminmin_u) +
            level.U.col[view_column].get(row_index) * (row.pplusplus_ed + row.pplusmin_u);
    }

    const cached_view_row = &phase_rows.rows[view_index];
    const view_row = scatteringSourceRowSumsFromRows(
        .{
            .zplus = cached_view_row.zplus[0..phase_rows.n],
            .zmin = cached_view_row.zmin[0..phase_rows.n],
        },
        level,
        geometry,
        view_index,
    );
    sum += level.E.get(view_index) * (view_row.pminplus_ed + view_row.pminmin_u);
    return sum;
}

fn scatteringSourceWeightingFromScaledPhase(
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    ud: []const rows.UDField,
    level_index: usize,
    fourier_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const phase_basis.FourierPlmBasis,
) f64 {
    // scatteringSourceWeightingFromScaledPhase -------------------------------------------------------------  |
    // Build source weighting directly from the aerosol phase row when no shared row cache is available.       |
    // --------------------------------------------------------------------------------------------------------|
    const view_column: usize = 0;
    const view_index = geometry.viewIndex();
    const level = &ud[level_index];
    var sum: f64 = 0.0;

    for (0..geometry.n_gauss) |row_index| {
        const row = scatteringSourceRowSums(
            phase_coefficients,
            max_phase_index,
            level,
            fourier_index,
            geometry,
            plm_basis,
            row_index,
        );
        sum += level.D.col[view_column].get(row_index) * (row.pminplus_ed + row.pminmin_u) +
            level.U.col[view_column].get(row_index) * (row.pplusplus_ed + row.pplusmin_u);
    }

    const view_row = scatteringSourceRowSums(
        phase_coefficients,
        max_phase_index,
        level,
        fourier_index,
        geometry,
        plm_basis,
        view_index,
    );
    sum += level.E.get(view_index) * (view_row.pminplus_ed + view_row.pminmin_u);
    return sum;
}

fn scatteringSourceRowSums(
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    level: *const rows.UDField,
    fourier_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const phase_basis.FourierPlmBasis,
    row_index: usize,
) ScatteringSourceRowSums {
    // scatteringSourceRowSums ------------------------------------------------------------------------------  |
    // Build the four solar-column source sums for one output row from scaled phase coefficients.              |
    // --------------------------------------------------------------------------------------------------------|
    const phase_row = phase_basis.fillZplusZminRowFromBasisLimited(
        fourier_index,
        phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        row_index,
    );
    return scatteringSourceRowSumsFromRows(
        .{
            .zplus = phase_row.zplus[0..phase_row.n],
            .zmin = phase_row.zmin[0..phase_row.n],
        },
        level,
        geometry,
        row_index,
    );
}

fn scatteringSourceRowSumsFromRows(
    phase_row: PhaseRows,
    level: *const rows.UDField,
    geometry: *const gauss_angles.GaussGeometry,
    row_index: usize,
) ScatteringSourceRowSums {
    // scatteringSourceRowSumsFromRows ----------------------------------------------------------------------  |
    // Contract one cached Z+/Z- row with solar-column diffuse and direct fields.                              |
    // --------------------------------------------------------------------------------------------------------|
    const solar_column: usize = 1;
    const solar_index = geometry.solarIndex();
    const row_mu = @max(geometry.u[row_index], direction_cosine_floor);
    var sums = ScatteringSourceRowSums{
        .pplusplus_ed = 0.0,
        .pminplus_ed = 0.0,
        .pminmin_u = 0.0,
        .pplusmin_u = 0.0,
    };

    for (0..geometry.n_gauss) |gauss_index| {
        const column_mu = @max(geometry.u[gauss_index], direction_cosine_floor);
        const pplus = (0.25 * phase_row.zplus[gauss_index] / row_mu) / column_mu;
        const pmin = (0.25 * phase_row.zmin[gauss_index] / row_mu) / column_mu;
        sums.pplusplus_ed += pplus * level.D.col[solar_column].get(gauss_index);
        sums.pminplus_ed += pmin * level.D.col[solar_column].get(gauss_index);
        sums.pminmin_u += pplus * level.U.col[solar_column].get(gauss_index);
        sums.pplusmin_u += pmin * level.U.col[solar_column].get(gauss_index);
    }

    const solar_mu = @max(geometry.u[solar_index], direction_cosine_floor);
    const pplus_direct = (0.25 * phase_row.zplus[solar_index] / row_mu) / solar_mu;
    const pmin_direct = (0.25 * phase_row.zmin[solar_index] / row_mu) / solar_mu;
    sums.pplusplus_ed += pplus_direct * level.E.get(solar_index);
    sums.pminplus_ed += pmin_direct * level.E.get(solar_index);
    return sums;
}

fn absorptionInterfaceWeighting(
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
    levels: []const source_levels.SourceLevel,
    level_index: usize,
    use_pseudo_spherical: bool,
    geometry: *const gauss_angles.GaussGeometry,
) f64 {
    // absorptionInterfaceWeighting -------------------------------------------------------------------------  |
    // Absorption interface weighting used by integrated-source aerosol Jacobian columns.                      |
    //                                                                                                         |
    //   `earth_radius_km = 6371.0` is the same spherical direct-beam radius used by that routine.             |
    //                                                                                                         |
    // math                                                                                                    |
    //   absorption -= (U_view * D_solar + D_view * U_solar) / mu                                              |
    //   spherical direct path uses y_k / sqrt(y_k^2 - y_l^2 * (1 - mu0^2))                                    |
    // --------------------------------------------------------------------------------------------------------|
    const view_column: usize = 0;
    const solar_column: usize = 1;
    const view_index = geometry.viewIndex();
    const solar_index = geometry.solarIndex();
    const level = ud[level_index];

    var sum: f64 = 0.0;
    for (0..geometry.n_gauss) |gauss_index| {
        const mu = @max(geometry.u[gauss_index], direction_cosine_floor);
        sum -= (level.U.col[view_column].get(gauss_index) * level.D.col[solar_column].get(gauss_index) +
            level.D.col[view_column].get(gauss_index) * level.U.col[solar_column].get(gauss_index)) / mu;
    }

    sum -= level.U.col[solar_column].get(view_index) * level.E.get(view_index) /
        @max(geometry.u[view_index], direction_cosine_floor);

    const can_use_pseudo_spherical_direct_path =
        use_pseudo_spherical and
        ud_sum_local.len >= ud.len and
        levels.len >= ud.len;
    if (can_use_pseudo_spherical_direct_path) {
        const solar_mu = @max(geometry.u[solar_index], direction_cosine_floor);
        const interface_radius_km = earth_radius_km + levels[level_index].altitude_km;
        var pseudo_direct_sum: f64 = 0.0;
        var source_level_index = level_index + 1;

        while (source_level_index > 0) {
            source_level_index -= 1;

            const source_radius_km = earth_radius_km + levels[source_level_index].altitude_km;
            const denominator = @sqrt(@abs(
                interface_radius_km * interface_radius_km -
                    source_radius_km * source_radius_km * (1.0 - solar_mu * solar_mu),
            ));
            const solar_slant_inverse = if (denominator > 0.0) interface_radius_km / denominator else 0.0;
            pseudo_direct_sum +=
                ud_sum_local[source_level_index].U.col[view_column].get(solar_index) *
                ud[source_level_index].E.get(solar_index) *
                solar_slant_inverse;
        }

        sum -= pseudo_direct_sum;
    } else {
        sum -= level.U.col[view_column].get(solar_index) * level.E.get(solar_index) /
            @max(geometry.u[solar_index], direction_cosine_floor);
    }

    return sum;
}

pub fn fourierWeight(fourier_index: usize, relative_azimuth_rad: f64) f64 {
    // fourierWeight ----------------------------------------------------------------------------------------- |
    // Return c_m for the LABOS Fourier reflectance sum.                                                       |
    // --------------------------------------------------------------------------------------------------------|
    if (fourier_index == 0) return 1.0;
    return 2.0 * math.cos(@as(f64, @floatFromInt(fourier_index)) * relative_azimuth_rad);
}

pub fn weightedFourierContribution(
    fourier_index: usize,
    relative_azimuth_rad: f64,
    rho_m: f64,
    thresholds: controls.PerformanceThresholds,
) FourierContribution {
    // weightedFourierContribution --------------------------------------------------------------------------- |
    // Apply Fourier azimuthal weight, perturbation hook, telemetry, and tail-stop decision.                   |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   Perturbation can replace the weighted term and the tail decision at the same LABOS gates.             |
    // --------------------------------------------------------------------------------------------------------|
    const weight = fourierWeight(fourier_index, relative_azimuth_rad);
    const coord = Perturbation.Coord{ .fourier_index = @intCast(fourier_index) };

    // instrumentation: perturbation: reflectance term --------------------------------------------------------|
    // captures: c_m * rho_m before adding it to total reflectance                                             |
    // why: test whether late Fourier terms can be pruned by tolerance.                                        |
    const weighted = Perturbation.scalar(
        .fourier_weighted_reflectance,
        coord,
        weight * rho_m,
    );
    // end instrumentation: perturbation: reflectance term ----------------------------------------------------|

    const tail_break = fourierTailBreak(fourier_index, rho_m, thresholds, coord);

    // instrumentation: calculation telemetry: Fourier contribution -------------------------------------------|
    // captures: Fourier contribution size and tail-break decision                                             |
    // why: compare tolerance pruning against each retained term.                                              |
    Telemetry.fourierContribution(
        fourier_index,
        weight,
        rho_m,
        weighted,
        thresholds.fourier_tail_reflectance_epsilon,
        tail_break,
    );
    // end instrumentation: calculation telemetry: Fourier contribution ---------------------------------------|

    return .{
        .weight = weight,
        .rho_m = rho_m,
        .weighted = weighted,
        .tail_break = tail_break,
    };
}

pub fn fourierTailBreak(
    fourier_index: usize,
    rho_m: f64,
    thresholds: controls.PerformanceThresholds,
    coord: Perturbation.Coord,
) bool {
    // fourierTailBreak -------------------------------------------------------------------------------------- |
    // Evaluate the Fourier tail-stop gate.                                                                    |
    //                                                                                                         |
    // tradeoff: Fourier tail stop                                                                             |
    // Stop the Fourier loop when the current unweighted term is below the configured epsilon.                 |
    // The stop is only allowed after fourier_floor_scalar.                                                    |
    // --------------------------------------------------------------------------------------------------------|

    // instrumentation: telemetry and perturbation: tail break ------------------------------------------------|
    // captures: Fourier tail-stop decision and term magnitude                                                 |
    // why: compare current convergence threshold against forced early stops.                                  |
    const tail_break_base =
        fourier_index >= thresholds.fourier_floor_scalar and
        @abs(rho_m) <= thresholds.fourier_tail_reflectance_epsilon;
    const tail_break = Perturbation.decision(.fourier_tail_break, coord, tail_break_base);
    // end instrumentation: telemetry and perturbation: tail break --------------------------------------------|

    if (tail_break) {

        // instrumentation: trace counter: tail break ---------------------------------------------------------|
        // captures: Fourier tail breaks                                                                       |
        // why: validate the tail-pruning threshold against observed exits.                                    |
        Trace.plotU("fourier_tail_breaks", 1);
        // end instrumentation: trace counter: tail break -----------------------------------------------------|

    }

    return tail_break;
}

pub fn clampPublicReflectance(reflectance: f64) f64 {
    // clampPublicReflectance -------------------------------------------------------------------------------- |
    // Clamp raw LABOS reflectance to the public forward-model output range.                                   |
    // --------------------------------------------------------------------------------------------------------|
    return math.clamp(reflectance, 0.0, 2.0);
}
