const std = @import("std");
const basis = @import("basis.zig");
const common = @import("../root.zig");

const math = std.math;

// reflectance.zig --------------------------------------------------------------------------------------------|
// Converts LABOS order fields into one Fourier reflectance term, then builds aerosol Jacobian weights.        |
//                                                                                                             |
// used by                                                                                                     |
//   execute.zig calls this after orders.zig has produced UD_fc and optional UDsumLocal_fc                     |
//   root.zig exports the public reflectance and Fourier-bound helpers                                         |
//                                                                                                             |
// main paths                                                                                                  |
//   calcReflectance                                                                                           |
//     -> non-integrated rtm_config; read top-of-atmosphere U field directly                                   |
//                                                                                                             |
//   calcIntegratedReflectanceWithBasis                                                                        |
//     -> integrate level source terms into rho_m                                                              |
//     -> optional phase-row reuse from execute.zig workspace                                                  |
//     -> zero-Fourier surface/cloud direct term                                                               |
//                                                                                                             |
//   calcAerosolDerivativeWeightingWithBasis                                                                   |
//     -> paired aerosol optical-depth and layer-pressure weighting                                            |
//     -> shared phase-row cache when the active aerosol interval allows it                                    |
//                                                                                                             |
//   calcAerosolOpticalDepthWeightingWithBasis                                                                 |
//     -> aerosol optical-depth weighting only                                                                 |
//                                                                                                             |
//   calcAerosolLayerPressureShiftWeightingWithBasis                                                           |
//     -> aerosol layer-pressure weighting only                                                                |
//                                                                                                             |
// reference names                                                                                             |
//   rho_m          : refl_fc before execute.zig applies the Fourier weight                                    |
//   UD_fc          : internal upward/downward radiation fields                                                |
//   UDsumLocal_fc  : accumulated local source fields for spherical absorption weighting                       |
//   RTMweight      : altitude quadrature weight for the reflectance source integral                           |
//   wfInterfksca   : scattering-coefficient interface weighting                                               |
//   wfInterfkabs   : absorption-coefficient interface weighting                                               |
//                                                                                                             |
// math                                                                                                        |
//   rho_m += RTMweight * E_view * k_sca * (PminusD + PplusU)                                                  |
//   execute.zig later adds Fourier weight * rho_m into total reflectance                                      |
//                                                                                                             |
// reference source-function shape                                                                             |
//   dR/dz = k_sca(z) * E_view * [ P- * (E_solar + D_solar) + P+ * U_solar ]                                   |
//                                                                                                             |
//   scalar effective phase factors                                                                            |
//     P- = 0.25 * Zmin  / (mu_view * mu_source)                                                               |
//     P+ = 0.25 * Zplus / (mu_view * mu_source)                                                               |
// ------------------------------------------------------------------------------------------------------------|

// numerical floors -------------------------------------------------------------------------------------------|
// Small cutoffs used when a floating-point value is too close to zero or one.                                 |
// They keep Fourier pruning and source-weight divisions stable.                                               |
//                                                                                                             |
// phase_support_floor ignores tiny phase coefficients when choosing the highest active Fourier term.          |
// direction_cosine_floor clamps mu before 1 / mu terms for grazing directions.                                |
// near_normal_mu_delta uses the reference scalar-Fourier shortcut when mu is close to 1.                      |
// ------------------------------------------------------------------------------------------------------------|
const phase_support_floor: f64 = 1.0e-12;
const direction_cosine_floor: f64 = 1.0e-12;
const near_normal_mu_delta: f64 = 1.0e-5;

// PhaseRows --------------------------------------------------------------------------------------------------|
// Borrowed views of one phase-kernel row. The row storage is owned by a cache or stack value nearby.          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] zplus : []const f64                                                                                |
// [16..31] zmin  : []const f64                                                                                |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total also includes referenced row storage                      |
const PhaseRows = struct {
    zplus: []const f64,
    zmin: []const f64,
};
// ------------------------------------------------------------------------------------------------------------|

// PhaseRowCache ----------------------------------------------------------------------------------------------|
// Inline cache for Zplus/Zmin rows across all stream/view/solar rows for one Fourier term.                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2408 B (2.352 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..2399] rows : [12]PhaseKernelRow                                                                      |
//             |----- [   0.. 199] rows[0]                                                                     |
//             |----- [ 200.. 399] rows[1]                                                                     |
//             |----- [2200..2399] rows[11]                                                                    |
// [2400..2407] n    : usize                                                                                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 2408 B (2.352 KiB); total = per instance * live instance count                    |
const PhaseRowCache = struct {
    rows: [basis.max_nmutot]basis.PhaseKernelRow,
    n: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// UnitPhase --------------------------------------------------------------------------------------------------|
// Aerosol phase coefficients plus the highest coefficient that can contribute.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] coefficients : *const [basis.max_phase_coef]f64                                                    |
// [ 8..15] max_index    : usize                                                                               |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes referenced coefficient storage              |
const UnitPhase = struct {
    coefficients: *const [basis.max_phase_coef]f64,
    max_index: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// AerosolDerivativeWeighting ---------------------------------------------------------------------------------|
// Paired integrated-source aerosol Jacobian contribution for the common two-state retrieval path.             |
// Pressure-to-altitude scaling happens after the forward product is assembled.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] aerosol_optical_depth            : f64                                                             |
// [ 8..15] aerosol_layer_mid_pressure_hpa   : f64                                                             |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = one stack value per paired Fourier weighting            |
pub const AerosolDerivativeWeighting = struct {
    aerosol_optical_depth: f64 = 0.0,
    aerosol_layer_mid_pressure_hpa: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

// ScatteringSourceRowSums ------------------------------------------------------------------------------------|
// Solar-column contractions reused by scattering-source weighting for one output row.                         |
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
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count                      |
const ScatteringSourceRowSums = struct {
    pplusplus_ed: f64,
    pminplus_ed: f64,
    pminmin_u: f64,
    pplusmin_u: f64,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn calcReflectance(
    ud: []const basis.UDField,
    end_level: usize,
    geo: *const basis.Geometry,
) f64 {
    // calcReflectance ----------------------------------------------------------------------------------------|
    // Non-integrated LABOS reflectance for one Fourier term.                                                  |
    //                                                                                                         |
    // zdisamar matches `CalcReflectance` when `integrateSourceFunction` is false:                             |
    // read the ordinary upward field at the top level, solar column, viewing direction.                       |
    // --------------------------------------------------------------------------------------------------------|

    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    return ud[end_level].U.col[solar_col].get(view_idx);
}

pub fn calcReflectanceTangent(
    ud_tangent: []const basis.UDField,
    end_level: usize,
    geo: *const basis.Geometry,
) f64 {
    // calcReflectanceTangent ---------------------------------------------------------------------------------|
    // Same top-level read as calcReflectance, but the input field is the derivative field.                    |
    // This keeps tangent call sites explicit even though the indexing is identical.                           |
    // --------------------------------------------------------------------------------------------------------|

    return calcReflectance(ud_tangent, end_level, geo);
}

pub fn calcIntegratedReflectance(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    end_level: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
) f64 {
    // calcIntegratedReflectance ------------------------------------------------------------------------------|
    // Allocation-light wrapper for callers that have not already built the Plm basis.                         |
    // Chooses the phase ceiling, builds Plm once, then calls the workspace-friendly implementation.           |
    // --------------------------------------------------------------------------------------------------------|

    const max_phase_index = if (rtm_quadrature.isValidFor(layers.len))
        @max(maxFourierIndex(layers), maxFourierIndexQuadrature(rtm_quadrature))
    else
        @max(maxFourierIndex(layers), maxFourierIndexInterfaces(source_interfaces));
    const plm_basis = basis.FourierPlmBasis.init(i_fourier, max_phase_index, geo);
    return calcIntegratedReflectanceWithBasis(
        layers,
        source_interfaces,
        rtm_quadrature,
        ud,
        end_level,
        i_fourier,
        geo,
        &plm_basis,
        null,
        null,
        null,
    );
}

pub fn calcIntegratedReflectanceWithBasis(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    end_level: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    adjacent_layer_phase_max_indices: ?[]const usize,
    layer_phase_row_cache: ?[]const basis.PhaseKernelRow,
    layer_phase_row_valid: ?[]const bool,
) f64 {
    // calcIntegratedReflectanceWithBasis ---------------------------------------------------------------------|
    // Turns one Fourier order field into rho_m by integrating source terms over RTM levels. Steps:            |
    //                                                                                                         |
    //   1. choose RTM quadrature data or source-interface data for each level                                 |
    //   2. skip levels whose phase expansion cannot contribute to this Fourier term                           |
    //   3. reuse a prepared phase row when the interface matches a layer phase                                |
    //   4. contract Zminus/Zplus rows with downward and upward solar fields                                   |
    //   5. add RTMweight * E_view * k_sca * source term into rho_m                                            |
    //   6. add the zero-Fourier direct surface/cloud term                                                     |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : every retained Fourier term when integrated-source reflection is active                    |
    //   costly   : source-level loop                                                                          |
    //              phase-row construction or cache lookup                                                     |
    //              Gauss stream reductions                                                                    |
    //   memory   : optional row cache supplied by execute.zig workspace                                       |
    //                                                                                                         |
    // calls                                                                                                   |
    //   sourceInterfaceAtLevelPtr                                                                             |
    //   fillRtmQuadraturePhaseRow or fillZplusZminRowFromWeightedPhaseLimited                                 |
    //   reuseLayerKernelIndex                                                                                 |
    //                                                                                                         |
    // math                                                                                                    |
    //   rho_m += RTMweight * E_view * k_sca * (PminusD + PplusU)                                              |
    //                                                                                                         |
    //   Pminus = 0.25 * Zmin  / (mu_view * mu_source)                                                         |
    //   Pplus  = 0.25 * Zplus / (mu_view * mu_source)                                                         |
    //                                                                                                         |
    //   PminusD = sum_mu Pminus(view, mu) * D_solar(mu)                                                       |
    //           + Pminus(view, solar) * E_solar                                                               |
    //                                                                                                         |
    //   PplusU  = sum_mu Pplus(view, mu) * U_solar(mu)                                                        |
    //                                                                                                         |
    // source                                                                                                  |
    //   zdisamar follows LabosModule.f90 CalcReflectance integrated-source branch                             |
    // --------------------------------------------------------------------------------------------------------|

    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const view_mu = @max(geo.u[view_idx], direction_cosine_floor);
    var reflectance: f64 = 0.0;
    const use_rtm_quadrature = rtm_quadrature.isValidFor(layers.len);

    for (0..end_level + 1) |ilevel| {

        // Source data choice ---------------------------------------------------------------------------------|
        // RTM quadrature levels carry their own source weights and phase mixture.                             |
        // Source-interface inputs are used only when the RTM grid is absent.                                  |
        // On the RTM rtm_config this is null.                                                                 |
        // ----------------------------------------------------------------------------------------------------|

        var fallback_source_interface: common.SourceInterfaceInput = undefined;
        const source_interface = choose_source_interface: {
            if (use_rtm_quadrature) break :choose_source_interface null;

            if (sourceInterfaceAtLevelPtr(layers, source_interfaces, ilevel)) |source| {
                break :choose_source_interface source;
            }

            fallback_source_interface = common.sourceInterfaceFromLayers(layers, ilevel);
            break :choose_source_interface &fallback_source_interface;
        };

        // Source strength ------------------------------------------------------------------------------------|
        // Prefer RTM quadrature source data when present. Otherwise use prepared interface quadrature with    |
        // positive weight and scattering coefficient, then fall back to the legacy interface weight.          |
        // ----------------------------------------------------------------------------------------------------|

        const use_source_interface_quadrature =
            !use_rtm_quadrature and
            source_interface.?.rtm_weight > 0.0 and
            source_interface.?.ksca_above > 0.0;

        var source_rtm_weight: f64 = undefined;
        var source_ksca: f64 = undefined;
        if (use_rtm_quadrature) {
            source_rtm_weight = rtm_quadrature.levels[ilevel].weight;
            source_ksca = rtm_quadrature.levels[ilevel].ksca;
        } else if (use_source_interface_quadrature) {
            source_rtm_weight = source_interface.?.rtm_weight;
            source_ksca = source_interface.?.ksca_above;
        } else {
            source_rtm_weight = source_interface.?.source_weight;
            source_ksca = 1.0;
        }
        if (source_rtm_weight <= 0.0 or source_ksca <= 0.0) {
            continue;
        }

        // Phase ceiling --------------------------------------------------------------------------------------|
        // Do not build a source row for Fourier orders that cannot be present at this level.                  |
        // Workspace-prepared adjacent limits are cheapest; otherwise derive the ceiling from layers, RTM      |
        // quadrature data, or source-interface data.                                                          |
        // ----------------------------------------------------------------------------------------------------|

        const source_max_phase_index = choose_source_phase_limit: {
            if (adjacent_layer_phase_max_indices) |indices| {
                break :choose_source_phase_limit indices[ilevel];
            }

            if (layers.len != 0) {
                break :choose_source_phase_limit adjacentLayerPhaseCoefficientIndex(layers, ilevel);
            }

            if (use_rtm_quadrature) {
                break :choose_source_phase_limit maxRtmQuadraturePhaseCoefficientIndex(
                    &rtm_quadrature.levels[ilevel],
                    rtm_quadrature,
                );
            }

            break :choose_source_phase_limit maxInterfacePhaseCoefficientIndex(layers, source_interfaces, ilevel);
        };

        // zdisamar uses the same reference gate: an integrated-source level
        // is skipped when adjacent layers cannot support this Fourier order.
        if (i_fourier > source_max_phase_index) continue;

        // Integrated-source weighting needs one phase row for this source level.
        // Reuse the row already built for RT_fc when the source level matches an RT layer.
        // Keep computed_row outside the block so a row built here stays available below.
        var computed_row: basis.PhaseKernelRow = undefined;
        const phase_rows: PhaseRows = choose_source_phase_rows: {
            const reusable_layer_index = if (!use_rtm_quadrature)
                reuseLayerKernelIndex(layers, source_interface.?, ilevel)
            else
                null;

            // calcRTlayersIntoWithBasis stores layer N in slot N + 1.
            // Slot 0 belongs to the top boundary.
            const cache_index = if (reusable_layer_index) |index| index + 1 else 0;
            const cached_rows: []const basis.PhaseKernelRow = layer_phase_row_cache orelse &.{};
            const cached_row_valid: []const bool = layer_phase_row_valid orelse &.{};
            const can_reuse_cached_phase_row =
                reusable_layer_index != null and
                cache_index < cached_rows.len and
                cache_index < cached_row_valid.len and
                cached_row_valid[cache_index];

            if (can_reuse_cached_phase_row) {
                const row = &cached_rows[cache_index];
                break :choose_source_phase_rows PhaseRows{
                    .zplus = row.zplus[0..row.n],
                    .zmin = row.zmin[0..row.n],
                };
            }

            // No saved RT-layer row matches this source level, so build the row here.
            if (use_rtm_quadrature) {
                computed_row = fillRtmQuadraturePhaseRow(
                    rtm_quadrature,
                    &rtm_quadrature.levels[ilevel],
                    i_fourier,
                    source_max_phase_index,
                    geo,
                    plm_basis,
                    view_idx,
                );
            } else {
                computed_row = basis.fillZplusZminRowFromWeightedPhaseLimited(
                    i_fourier,
                    source_interface.?.phase_above.aerosol_weight,
                    source_interface.?.phase_above.rayleigh2_weight,
                    source_interface.?.phase_above.aerosol_phase_coefficients,
                    source_max_phase_index,
                    geo,
                    plm_basis,
                    view_idx,
                );
            }
            break :choose_source_phase_rows PhaseRows{
                .zplus = computed_row.zplus[0..computed_row.n],
                .zmin = computed_row.zmin[0..computed_row.n],
            };
        };

        var pmin_ed: f64 = 0.0;

        const level = ud[ilevel];
        const level_d = level.D.col[solar_col].data;
        const level_u = level.U.col[solar_col].data;
        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], direction_cosine_floor);
            const pmin = (0.25 * phase_rows.zmin[imu] / view_mu) / mu;

            // Downward source term from diffuse light arriving at this level.
            pmin_ed += pmin * level_d[imu];
        }

        const solar_mu = @max(geo.u[solar_idx], direction_cosine_floor);
        const pmin_direct = (0.25 * phase_rows.zmin[solar_idx] / view_mu) / solar_mu;

        // Direct solar beam uses the same Pminus source term.
        pmin_ed += pmin_direct * level.E.data[solar_idx];

        var pplusst_u: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], direction_cosine_floor);
            const pplusst = (0.25 * phase_rows.zplus[imu] / view_mu) / mu;

            // Upward source term from diffuse light leaving this level.
            pplusst_u += pplusst * level_u[imu];
        }

        // zdisamar keeps the reference source split: first E * ksca * (...),
        // then RTMweight in a separate altitude reduction.
        const contribution = level.E.data[view_idx] *
            source_ksca *
            (pmin_ed + pplusst_u);
        reflectance += source_rtm_weight * contribution;
    }

    // Keep the reference scalar direct term in the zero-Fourier closure.
    if (i_fourier == 0) {
        reflectance += ud[0].E.get(view_idx) * ud[0].U.col[solar_col].get(view_idx);
    }

    return reflectance;
}

pub fn calcAerosolDerivativeWeightingWithBasis(
    layers: []const common.LayerInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    end_level: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) AerosolDerivativeWeighting {
    // calcAerosolDerivativeWeightingWithBasis ----------------------------------------------------------------|
    // Paired aerosol Jacobian weighting for AOD and layer pressure. Steps:                                    |
    //                                                                                                         |
    //   1. require the RTM quadrature grid                                                                    |
    //   2. find the active aerosol interval                                                                   |
    //   3. build one common aerosol phase-row cache for this Fourier term when possible                       |
    //   4. compute AOD weighting and pressure-shift weighting from the shared rows                            |
    //   5. fall back to separate routes when the paired cache is not valid                                    |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : when execute.zig requests both aerosol derivative lanes                                    |
    //   costly   : phase-row cache build                                                                      |
    //              active-interface weighting                                                                 |
    //   memory   : one PhaseRowCache stack value shared by both derivative lanes                              |
    //                                                                                                         |
    // calls                                                                                                   |
    //   calcAerosolOpticalDepthWeightingFromPhaseRows                                                         |
    //   calcAerosolLayerPressureShiftWeightingFromPhaseRows                                                   |
    // --------------------------------------------------------------------------------------------------------|

    if (!rtm_quadrature.isValidFor(layers.len)) return .{};
    const bounds = activeAerosolInteriorBounds(rtm_quadrature, end_level) orelse return .{
        .aerosol_optical_depth = calcAerosolOpticalDepthWeightingWithBasis(
            layers,
            rtm_quadrature,
            ud,
            ud_sum_local,
            end_level,
            i_fourier,
            use_pseudo_spherical,
            geo,
            plm_basis,
            null,
        ),
    };

    var phase_row_storage: PhaseRowCache = undefined;
    const phase_rows = cachedCommonAerosolPhaseRows(
        rtm_quadrature,
        bounds,
        i_fourier,
        geo,
        plm_basis,
        &phase_row_storage,
    ) orelse return .{
        .aerosol_optical_depth = calcAerosolOpticalDepthWeightingWithBasis(
            layers,
            rtm_quadrature,
            ud,
            ud_sum_local,
            end_level,
            i_fourier,
            use_pseudo_spherical,
            geo,
            plm_basis,
            null,
        ),
        .aerosol_layer_mid_pressure_hpa = calcAerosolLayerPressureShiftWeightingWithBasis(
            layers,
            rtm_quadrature,
            ud,
            ud_sum_local,
            end_level,
            i_fourier,
            use_pseudo_spherical,
            geo,
            plm_basis,
        ),
    };

    return .{
        .aerosol_optical_depth = calcAerosolOpticalDepthWeightingFromPhaseRows(
            layers,
            rtm_quadrature,
            ud,
            ud_sum_local,
            bounds,
            use_pseudo_spherical,
            geo,
            phase_rows,
        ),
        .aerosol_layer_mid_pressure_hpa = calcAerosolLayerPressureShiftWeightingFromPhaseRows(
            layers,
            rtm_quadrature,
            ud,
            ud_sum_local,
            bounds,
            use_pseudo_spherical,
            geo,
            phase_rows,
        ),
    };
}

pub fn calcAerosolOpticalDepthWeightingWithBasis(
    layers: []const common.LayerInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    end_level: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    adjacent_layer_phase_max_indices: ?[]const usize,
) f64 {
    // calcAerosolOpticalDepthWeightingWithBasis --------------------------------------------------------------|
    // Aerosol optical-depth Jacobian weighting for one Fourier term. Steps:                                   |
    //                                                                                                         |
    //   1. require the RTM quadrature grid; otherwise no integrated-source aerosol weighting is available     |
    //   2. prefer the active aerosol interval rtm_config when top and bottom interfaces are known             |
    //   3. reuse common aerosol phase rows across all active interfaces when possible                         |
    //   4. integrate interface weighting over altitude and divide by layer thickness                          |
    //   5. fall back to level.weight * dksca/dtau weighting when no interior interval is available            |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : requested AOD Jacobian lane for every retained Fourier term                                |
    //   costly   : interface absorption weighting                                                             |
    //              scattering-source weighting                                                                |
    //              optional phase-row cache build                                                             |
    //                                                                                                         |
    // calls                                                                                                   |
    //   activeAerosolInteriorBounds                                                                           |
    //   scatteringCoefficientInterfaceWeighting*                                                              |
    //   absorptionInterfaceWeighting                                                                          |
    //                                                                                                         |
    // math                                                                                                    |
    //   AOD weighting = integral(interface weighting dz) / aerosol layer thickness                            |
    //   fallback += level.weight * dksca/dtau * (source weighting + absorption weighting)                     |
    // --------------------------------------------------------------------------------------------------------|

    _ = adjacent_layer_phase_max_indices;
    if (!rtm_quadrature.isValidFor(layers.len)) return 0.0;

    if (activeAerosolInteriorBounds(rtm_quadrature, end_level)) |bounds| {
        if (bounds.top <= bounds.bottom + 1) return 0.0;

        const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);
        const needs_absorption_weighting = (1.0 - aerosol_ssa) != 0.0;
        const denominator =
            rtm_quadrature.levels[bounds.top - 1].altitude_km -
            rtm_quadrature.levels[bounds.bottom].altitude_km;
        if (denominator <= 0.0) return 0.0;

        const cached_phase_rows: ?PhaseRowCache = choose_phase_cache: {
            const unit_phase = commonActiveAerosolUnitPhase(rtm_quadrature, bounds) orelse
                break :choose_phase_cache null;
            if (i_fourier > unit_phase.max_index) return 0.0;

            break :choose_phase_cache buildPhaseRowCache(
                unit_phase.coefficients,
                unit_phase.max_index,
                i_fourier,
                geo,
                plm_basis,
            );
        };

        var integral: f64 = 0.0;

        const previous_scattering_weighting = choose_bottom_scattering: {
            if (cached_phase_rows) |phase_rows| {
                break :choose_bottom_scattering scatteringCoefficientInterfaceWeightingFromPhaseRows(
                    &phase_rows,
                    ud,
                    ud_sum_local,
                    rtm_quadrature,
                    bounds.bottom,
                    use_pseudo_spherical,
                    geo,
                );
            }

            break :choose_bottom_scattering scatteringCoefficientInterfaceWeighting(
                rtm_quadrature.levels[bounds.bottom].aerosol_ksca_above_per_km,
                ud,
                ud_sum_local,
                rtm_quadrature,
                bounds.bottom,
                i_fourier,
                use_pseudo_spherical,
                geo,
                plm_basis,
            );
        };
        const previous_absorption_weighting = choose_bottom_absorption: {
            if (!needs_absorption_weighting) break :choose_bottom_absorption 0.0;

            break :choose_bottom_absorption absorptionInterfaceWeighting(
                ud,
                ud_sum_local,
                rtm_quadrature,
                bounds.bottom,
                use_pseudo_spherical,
                geo,
            );
        };
        var previous = aerosolTotalExtinctionInterfaceWeighting(
            previous_scattering_weighting,
            previous_absorption_weighting,
            aerosol_ssa,
        );

        for (bounds.bottom + 1..bounds.top) |ilevel| {
            const current_scattering_weighting = choose_level_scattering: {
                if (cached_phase_rows) |phase_rows| {
                    break :choose_level_scattering scatteringCoefficientInterfaceWeightingFromPhaseRows(
                        &phase_rows,
                        ud,
                        ud_sum_local,
                        rtm_quadrature,
                        ilevel,
                        use_pseudo_spherical,
                        geo,
                    );
                }

                break :choose_level_scattering scatteringCoefficientInterfaceWeighting(
                    rtm_quadrature.levels[ilevel].aerosol_ksca_above_per_km,
                    ud,
                    ud_sum_local,
                    rtm_quadrature,
                    ilevel,
                    i_fourier,
                    use_pseudo_spherical,
                    geo,
                    plm_basis,
                );
            };
            const current_absorption_weighting = choose_level_absorption: {
                if (!needs_absorption_weighting) break :choose_level_absorption 0.0;

                break :choose_level_absorption absorptionInterfaceWeighting(
                    ud,
                    ud_sum_local,
                    rtm_quadrature,
                    ilevel,
                    use_pseudo_spherical,
                    geo,
                );
            };
            const current = aerosolTotalExtinctionInterfaceWeighting(
                current_scattering_weighting,
                current_absorption_weighting,
                aerosol_ssa,
            );
            const dz = rtm_quadrature.levels[ilevel].altitude_km -
                rtm_quadrature.levels[ilevel - 1].altitude_km;

            // Trapezoid rule over altitude. Final division by interval thickness is below the loop.
            if (dz > 0.0) {
                integral += 0.5 * (previous + current) * dz;
            }

            previous = current;
        }
        return integral / denominator;
    }

    var weighting: f64 = 0.0;
    const unit_phase = unitAerosolPhase(rtm_quadrature) orelse return 0.0;
    for (0..end_level + 1) |ilevel| {
        const level = &rtm_quadrature.levels[ilevel];
        if (level.weight <= 0.0) {
            continue;
        }

        const d_sca_d_tau = level.aerosol_ksca_jacobian;
        if (d_sca_d_tau == 0.0) {
            continue;
        }

        const source_max_phase_index = unit_phase.max_index;
        if (i_fourier > source_max_phase_index) {
            continue;
        }

        const source_weighting = d_sca_d_tau * scatteringSourceWeightingFromScaledPhase(
            unit_phase.coefficients,
            source_max_phase_index,
            ud,
            ilevel,
            i_fourier,
            geo,
            plm_basis,
        );
        const extinction_weighting = d_sca_d_tau * absorptionInterfaceWeighting(
            ud,
            ud_sum_local,
            rtm_quadrature,
            ilevel,
            use_pseudo_spherical,
            geo,
        );

        // Fallback path uses per-level quadrature weights directly.
        weighting += level.weight * (source_weighting + extinction_weighting);
    }
    return weighting;
}

pub fn calcAerosolLayerPressureShiftWeightingWithBasis(
    layers: []const common.LayerInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    end_level: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) f64 {
    // calcAerosolLayerPressureShiftWeightingWithBasis --------------------------------------------------------|
    // Aerosol layer-pressure Jacobian weighting for one Fourier term. Steps:                                  |
    //                                                                                                         |
    //   1. require the RTM quadrature grid and an active aerosol interval                                     |
    //   2. evaluate scattering-coefficient weighting at the top and bottom interfaces                         |
    //   3. convert aerosol SSA to absorption coefficient for the same interval                                |
    //   4. add the absorption top-minus-bottom term when absorption is present                                |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : requested pressure Jacobian lane for every retained Fourier term                           |
    //   costly   : top and bottom interface weighting                                                         |
    //              absorption weighting when k_abs is nonzero                                                 |
    //                                                                                                         |
    // math                                                                                                    |
    //   k_abs = k_sca * (1 - SSA) / SSA        when SSA > 0                                                   |
    //   pressure weighting = (top_sca - bottom_sca) * k_sca                                                   |
    //                    + (top_abs - bottom_abs) * k_abs                                                     |
    // --------------------------------------------------------------------------------------------------------|

    if (!rtm_quadrature.isValidFor(layers.len)) return 0.0;

    const bounds = activeAerosolInteriorBounds(rtm_quadrature, end_level) orelse return 0.0;
    const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);

    const top_sca_weighting = scatteringCoefficientInterfaceWeighting(
        rtm_quadrature.levels[bounds.top].aerosol_ksca_below_per_km,
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.top,
        i_fourier,
        use_pseudo_spherical,
        geo,
        plm_basis,
    );

    const bottom_sca_weighting = scatteringCoefficientInterfaceWeighting(
        rtm_quadrature.levels[bounds.bottom].aerosol_ksca_above_per_km,
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.bottom,
        i_fourier,
        use_pseudo_spherical,
        geo,
        plm_basis,
    );

    const ksca = rtm_quadrature.levels[bounds.top].aerosol_ksca_below_per_km;
    const kabs = if (aerosol_ssa > 0.0) ksca * (1.0 - aerosol_ssa) / aerosol_ssa else 0.0;
    const scattering_pressure_weighting = (top_sca_weighting - bottom_sca_weighting) * ksca;
    if (kabs == 0.0) return scattering_pressure_weighting;

    const top_abs_weighting = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.top,
        use_pseudo_spherical,
        geo,
    );

    const bottom_abs_weighting = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.bottom,
        use_pseudo_spherical,
        geo,
    );
    const absorption_pressure_weighting = (top_abs_weighting - bottom_abs_weighting) * kabs;
    return scattering_pressure_weighting + absorption_pressure_weighting;
}

pub fn resolvedPhaseCoefficientMax(input: common.ForwardInput) usize {
    // resolvedPhaseCoefficientMax ----------------------------------------------------------------------------|
    // Highest phase coefficient required by the chosen reflectance source data.                               |
    // --------------------------------------------------------------------------------------------------------|

    var max_index = maxFourierIndex(input.layers);
    if (input.rtm_quadrature.isValidFor(input.layers.len)) {
        max_index = @max(max_index, maxFourierIndexQuadrature(input.rtm_quadrature));
    } else if (input.source_interfaces.len == input.layers.len + 1) {
        max_index = @max(max_index, maxFourierIndexInterfaces(input.source_interfaces));
    }
    return max_index;
}

pub fn resolvedFourierMax(input: common.ForwardInput, controls: common.RadiativeTransferControls) usize {
    // resolvedFourierMax -------------------------------------------------------------------------------------|
    // Fourier loop bound for one LABOS forward sample. Steps:                                                 |
    //                                                                                                         |
    //   1. return only m = 0 for empty layers or near-normal geometry                                         |
    //   2. choose the phase ceiling from RTM quadrature, source interfaces, or layer phases                   |
    //   3. apply the performance cap from radiative-transfer controls                                         |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : once before the Fourier loop in execute.zig                                                |
    //   costly   : scans phase coefficient maxima                                                             |
    //                                                                                                         |
    // math                                                                                                    |
    //   Fourier maximum = min(highest active phase coefficient, fourier_order_cap)                            |
    // --------------------------------------------------------------------------------------------------------|

    if (input.layers.len == 0) return 0;

    // Near-nadir and near-normal geometries collapse to the scalar Fourier
    // term in the reference path.
    if ((1.0 - input.muv) < near_normal_mu_delta or
        (1.0 - input.mu0) < near_normal_mu_delta)
    {
        return 0;
    }

    const resolved_max = choose_fourier_limit: {
        if (input.rtm_quadrature.isValidFor(input.layers.len)) {
            break :choose_fourier_limit maxFourierIndexQuadrature(input.rtm_quadrature);
        }

        if (input.source_interfaces.len == input.layers.len + 1) {
            break :choose_fourier_limit maxFourierIndexInterfaces(input.source_interfaces);
        }

        break :choose_fourier_limit maxFourierIndex(input.layers);
    };
    return controls.performance_thresholds.cappedFourierMax(resolved_max);
}

pub fn fillAdjacentLayerPhaseMaxIndices(
    source_phase_max_indices: []usize,
    layer_phase_max_indices: []const usize,
) void {
    // fillAdjacentLayerPhaseMaxIndices -----------------------------------------------------------------------|
    // Fill source-interface Fourier ceilings from layer Fourier ceilings.                                     |
    //                                                                                                         |
    // Each interior interface can be illuminated by the layer above or below, so it keeps the larger          |
    // neighboring phase ceiling. Top and bottom interfaces only have one adjacent layer.                      |
    // --------------------------------------------------------------------------------------------------------|

    const nlayer = layer_phase_max_indices.len;
    std.debug.assert(source_phase_max_indices.len >= nlayer + 1);
    if (nlayer == 0) {
        if (source_phase_max_indices.len != 0) source_phase_max_indices[0] = 0;
        return;
    }

    source_phase_max_indices[0] = layer_phase_max_indices[0];
    for (1..nlayer) |ilevel| {

        // Interior interface ceiling is max(layer above ceiling, layer below ceiling).
        source_phase_max_indices[ilevel] = @max(
            layer_phase_max_indices[ilevel - 1],
            layer_phase_max_indices[ilevel],
        );
    }
    source_phase_max_indices[nlayer] = layer_phase_max_indices[nlayer - 1];
}

pub fn totalScatteringOpticalDepth(layers: []const common.LayerInput) f64 {
    // totalScatteringOpticalDepth ----------------------------------------------------------------------------|
    // Sum positive layer scattering optical depth for the LABOS order/Fourier decisions.                      |
    //                                                                                                         |
    // call path                                                                                               |
    //   execute.zig uses this before ordersScat to choose the scattering-order cap.                           |
    //   root.zig also exports it for callers that need the same transport-layer total.                        |
    //                                                                                                         |
    // memory                                                                                                  |
    //   LayerInput is a 176 B transport row. This scan reads one f64 by pointer, so rows are not copied.      |
    //   The same layer slice is immediately consumed by LABOS transport; a side column would need sync proof. |
    //                                                                                                         |
    // math                                                                                                    |
    //   total scattering optical depth = sum(max(layer scattering optical depth, 0))                          |
    // --------------------------------------------------------------------------------------------------------|

    var total: f64 = 0.0;
    for (layers) |*layer| total += @max(layer.scattering_optical_depth, 0.0);
    return total;
}

fn sourceInterfaceAtLevelPtr(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    ilevel: usize,
) ?*const common.SourceInterfaceInput {
    // sourceInterfaceAtLevelPtr ------------------------------------------------------------------------------|
    // Return the prepared source-interface row for this level when the caller supplied one.                   |
    // --------------------------------------------------------------------------------------------------------|

    if (source_interfaces.len == layers.len + 1 and ilevel < source_interfaces.len) {
        return &source_interfaces[ilevel];
    }
    return null;
}

fn maxPhaseCoefficientIndex(phase_coefficients: *const [basis.max_phase_coef]f64) usize {
    // maxPhaseCoefficientIndex -------------------------------------------------------------------------------|
    // Find the last nonzero phase coefficient so higher Fourier terms can be skipped.                         |
    // --------------------------------------------------------------------------------------------------------|

    var max_index: usize = 0;
    for (1..basis.max_phase_coef) |idx| {
        if (@abs(phase_coefficients[idx]) > phase_support_floor) {
            max_index = idx;
        }
    }
    return max_index;
}

fn maxWeightedPhaseCoefficientIndex(
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefficients: *const [basis.max_phase_coef]f64,
) usize {
    // maxWeightedPhaseCoefficientIndex -----------------------------------------------------------------------|
    // Combine aerosol and Rayleigh phase support into one Fourier ceiling.                                    |
    // Rayleigh only needs coefficients through index 2. Aerosol may need the prepared aerosol ceiling.        |
    // --------------------------------------------------------------------------------------------------------|

    var max_index: usize = 0;
    if (@abs(rayleigh2_weight) > phase_support_floor) max_index = 2;
    if (@abs(aerosol_weight) > phase_support_floor) {
        max_index = @max(max_index, maxPhaseCoefficientIndex(aerosol_phase_coefficients));
    }
    return max_index;
}

fn maxRtmQuadraturePhaseCoefficientIndex(
    level: *const common.RtmQuadratureLevel,
    rtm_quadrature: common.RtmQuadratureGrid,
) usize {
    // maxRtmQuadraturePhaseCoefficientIndex ------------------------------------------------------------------|
    // Return the Fourier ceiling for one RTM quadrature level's gas/aerosol phase mixture.                    |
    // --------------------------------------------------------------------------------------------------------|

    return maxWeightedPhaseCoefficientIndex(
        level.phase_aerosol_weight,
        level.phase_rayleigh2_weight,
        rtm_quadrature.aerosol_phase_coefficients,
    );
}

fn fillRtmQuadraturePhaseRow(
    rtm_quadrature: common.RtmQuadratureGrid,
    level: *const common.RtmQuadratureLevel,
    i_fourier: usize,
    max_phase_index: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    row_index: usize,
) basis.PhaseKernelRow {
    // fillRtmQuadraturePhaseRow ------------------------------------------------------------------------------|
    // Build one Zplus/Zmin row from the RTM quadrature level's aerosol/Rayleigh phase mixture.                |
    // --------------------------------------------------------------------------------------------------------|

    return basis.fillZplusZminRowFromWeightedPhaseLimited(
        i_fourier,
        level.phase_aerosol_weight,
        level.phase_rayleigh2_weight,
        rtm_quadrature.aerosol_phase_coefficients,
        max_phase_index,
        geo,
        plm_basis,
        row_index,
    );
}

fn maxInterfacePhaseCoefficientIndex(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    ilevel: usize,
) usize {
    // maxInterfacePhaseCoefficientIndex ----------------------------------------------------------------------|
    // Highest Fourier term needed by source-interface phase data. Steps:                                      |
    //                                                                                                         |
    //   1. use prepared source-interface data when it exists                                                  |
    //   2. otherwise derive one source interface from the layer data                                          |
    //   3. keep the larger phase ceiling from the layer above or below this interface                         |
    // --------------------------------------------------------------------------------------------------------|

    var fallback_source_interface: common.SourceInterfaceInput = undefined;
    const source_interface = choose_source_interface: {
        if (sourceInterfaceAtLevelPtr(layers, source_interfaces, ilevel)) |source| {
            break :choose_source_interface source;
        }

        fallback_source_interface = common.sourceInterfaceFromLayers(layers, ilevel);
        break :choose_source_interface &fallback_source_interface;
    };

    const above_max = source_interface.phase_max_index_above;
    const below_max = source_interface.phase_max_index_below;

    // A source interface can be fed by phase terms from either side.
    // Keep the larger ceiling so neither side is pruned too early.
    const phase_limit = @max(above_max, below_max);
    return phase_limit;
}

fn adjacentLayerPhaseCoefficientIndex(
    layers: []const common.LayerInput,
    ilevel: usize,
) usize {
    // adjacentLayerPhaseCoefficientIndex ---------------------------------------------------------------------|
    // Return the highest phase coefficient from the layer above or below this interface.                      |
    // --------------------------------------------------------------------------------------------------------|

    if (layers.len == 0) return 0;
    if (ilevel == 0) return layers[0].phase.maxIndex();
    if (ilevel >= layers.len) return layers[layers.len - 1].phase.maxIndex();
    return @max(
        layers[ilevel - 1].phase.maxIndex(),
        layers[ilevel].phase.maxIndex(),
    );
}

fn reuseLayerKernelIndex(
    layers: []const common.LayerInput,
    source_interface: *const common.SourceInterfaceInput,
    ilevel: usize,
) ?usize {
    // reuseLayerKernelIndex ----------------------------------------------------------------------------------|
    // Reuse a layer phase row when the source interface carries the same phase mixture as that layer.         |
    // --------------------------------------------------------------------------------------------------------|

    if (layers.len == 0) return null;
    const above_index = @min(ilevel, layers.len - 1);
    if (!source_interface.phase_above.eql(layers[above_index].phase)) return null;
    return above_index;
}

fn absorptionInterfaceWeighting(
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    rtm_quadrature: common.RtmQuadratureGrid,
    ilevel: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
) f64 {
    // absorptionInterfaceWeighting ---------------------------------------------------------------------------|
    // Absorption interface weighting used by aerosol Jacobian columns. Steps:                                 |
    //                                                                                                         |
    //   1. subtract diffuse U/D pair products across Gauss streams                                            |
    //   2. subtract the direct view path                                                                      |
    //   3. when spherical correction is active, replace the direct solar path with the curved-path sum        |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : per active aerosol interface and Fourier term                                              |
    //   costly   : Gauss stream reduction                                                                     |
    //              optional pseudo-spherical level loop                                                       |
    //   memory   : reads UD_fc and optional UDsumLocal_fc; writes one scalar                                  |
    //                                                                                                         |
    // math                                                                                                    |
    //   absorption -= (U_view * D_solar + D_view * U_solar) / mu                                              |
    //   absorption -= direct beam terms                                                                       |
    //                                                                                                         |
    //   pseudo-spherical direct path uses                                                                     |
    //                      y_k                                                                                |
    //   ---------------------------------------                                                               |
    //      sqrt(y_k^2 - y_l^2 * (1 - mu0^2))                                                                  |
    //                                                                                                         |
    // source                                                                                                  |
    //   zdisamar follows LabosModule.f90 CalcDerivdRdkabs                                                     |
    // --------------------------------------------------------------------------------------------------------|

    const view_col: usize = 0;
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const level = ud[ilevel];

    var sum: f64 = 0.0;
    for (0..geo.n_gauss) |i_gauss| {
        const mu = @max(geo.u[i_gauss], direction_cosine_floor);

        // Diffuse absorption term from upward/view and downward/solar field pairs.
        sum -= (level.U.col[view_col].get(i_gauss) * level.D.col[solar_col].get(i_gauss) +
            level.D.col[view_col].get(i_gauss) * level.U.col[solar_col].get(i_gauss)) / mu;
    }

    // Direct view path to the detector.
    sum -= level.U.col[solar_col].get(view_idx) * level.E.get(view_idx) /
        @max(geo.u[view_idx], direction_cosine_floor);

    const can_use_pseudo_spherical_direct_path =
        use_pseudo_spherical and
        ud_sum_local.len >= ud.len and
        rtm_quadrature.levels.len >= ud.len;

    if (can_use_pseudo_spherical_direct_path) {
        const earth_radius_km = 6371.0;
        const solar_mu = @max(geo.u[solar_idx], direction_cosine_floor);
        const y_k = earth_radius_km + rtm_quadrature.levels[ilevel].altitude_km;
        var pseudo_direct_sum: f64 = 0.0;
        var level_index = ilevel + 1;

        while (level_index > 0) {
            level_index -= 1;

            // Curved solar path ------------------------------------------------------------------------------|
            // y_k is the radius of the interface being weighted. y_l is the radius of the absorbing level.    |
            // The fraction below is the spherical slant-path inverse used for the direct solar beam.          |
            //                                                                                                 |
            //                         y_k                                                                     |
            //   -------------------------------------------------                                             |
            //         sqrt(y_k^2 - y_l^2 * (1 - solar_mu^2))                                                  |
            // ------------------------------------------------------------------------------------------------|

            const y_l = earth_radius_km + rtm_quadrature.levels[level_index].altitude_km;
            const denominator = @sqrt(@abs(y_k * y_k - y_l * y_l * (1.0 - solar_mu * solar_mu)));
            const solar_slant_inverse = if (denominator > 0.0) y_k / denominator else 0.0;

            const local_upward_view = ud_sum_local[level_index].U.col[view_col].get(solar_idx);
            const direct_solar_at_level = ud[level_index].E.get(solar_idx);
            const curved_direct_path =
                local_upward_view *
                direct_solar_at_level *
                solar_slant_inverse;

            pseudo_direct_sum += curved_direct_path;
        }

        sum -= pseudo_direct_sum;
    } else {
        sum -= level.U.col[view_col].get(solar_idx) * level.E.get(solar_idx) /
            @max(geo.u[solar_idx], direction_cosine_floor);
    }

    return sum;
}

inline fn scatteringSourceRowSums(
    scaled_phase_coefficients: *const [basis.max_phase_coef]f64,
    max_phase_index: usize,
    level: *const basis.UDField,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    row_index: usize,
) ScatteringSourceRowSums {
    // scatteringSourceRowSums --------------------------------------------------------------------------------|
    // Build the four solar-column source sums for one output row from scaled phase coefficients.              |
    //                                                                                                         |
    // This builds the scalar version of the four reference aerosol-weighting phase contractions:              |
    //                                                                                                         |
    //   PplusplusD : Zplus row against downward solar diffuse field plus direct solar beam                    |
    //   PminplusD  : Zmin  row against downward solar diffuse field plus direct solar beam                    |
    //   PminminU   : Zplus row against upward diffuse field in scalar mode                                    |
    //   PplusminU  : Zmin  row against upward diffuse field in scalar mode                                    |
    //                                                                                                         |
    // The full polarized reference path applies top/bottom Stokes transforms. zdisamar's scalar O2 A path     |
    // collapses those transforms to the same Zplus/Zmin rows used here.                                       |
    // --------------------------------------------------------------------------------------------------------|

    const solar_col: usize = 1;
    const solar_idx = geo.n_gauss + 1;
    const rows = basis.fillZplusZminRowFromBasisLimited(
        i_fourier,
        scaled_phase_coefficients,
        max_phase_index,
        geo,
        plm_basis,
        row_index,
    );
    const mu_row = @max(geo.u[row_index], direction_cosine_floor);
    var sums = ScatteringSourceRowSums{
        .pplusplus_ed = 0.0,
        .pminplus_ed = 0.0,
        .pminmin_u = 0.0,
        .pplusmin_u = 0.0,
    };
    for (0..geo.n_gauss) |imu| {
        const mu_col = @max(geo.u[imu], direction_cosine_floor);
        const pplus = (0.25 * rows.zplus[imu] / mu_row) / mu_col;
        const pmin = (0.25 * rows.zmin[imu] / mu_row) / mu_col;

        // Pair Pplus/Pminus phase factors with D_solar and U_solar fields.
        sums.pplusplus_ed += pplus * level.D.col[solar_col].get(imu);
        sums.pminplus_ed += pmin * level.D.col[solar_col].get(imu);
        sums.pminmin_u += pplus * level.U.col[solar_col].get(imu);
        sums.pplusmin_u += pmin * level.U.col[solar_col].get(imu);
    }
    const mu_solar = @max(geo.u[solar_idx], direction_cosine_floor);
    const pplus_direct = (0.25 * rows.zplus[solar_idx] / mu_row) / mu_solar;
    const pmin_direct = (0.25 * rows.zmin[solar_idx] / mu_row) / mu_solar;
    sums.pplusplus_ed += pplus_direct * level.E.get(solar_idx);
    sums.pminplus_ed += pmin_direct * level.E.get(solar_idx);
    return sums;
}

fn scatteringSourceWeightingFromScaledPhase(
    scaled_phase_coefficients: *const [basis.max_phase_coef]f64,
    max_phase_index: usize,
    ud: []const basis.UDField,
    ilevel: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) f64 {
    // scatteringSourceWeightingFromScaledPhase ---------------------------------------------------------------|
    // Scattering-source weighting for one interface when rows are built on demand. Steps:                     |
    //                                                                                                         |
    //   1. build source row sums for each Gauss row                                                           |
    //   2. contract them with view-column D and U fields                                                      |
    //   3. add the direct view-row source term                                                                |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : fallback aerosol weighting when a phase-row cache is not available                         |
    //   costly   : phase-row builds inside the Gauss row loop                                                 |
    //              source contractions                                                                        |
    //                                                                                                         |
    // math                                                                                                    |
    //   source += D_view * (PminplusD + PminminU)                                                             |
    //           + U_view * (PplusplusD + PplusminU)                                                           |
    //   source += E_view * (PminplusD + PminminU) for the direct view row                                     |
    // --------------------------------------------------------------------------------------------------------|

    const view_col: usize = 0;
    const view_idx = geo.viewIdx();
    const level = &ud[ilevel];

    var sum: f64 = 0.0;
    for (0..geo.n_gauss) |row_index| {
        const row = scatteringSourceRowSums(
            scaled_phase_coefficients,
            max_phase_index,
            level,
            i_fourier,
            geo,
            plm_basis,
            row_index,
        );

        // Diffuse view field times solar-column source sums.
        sum += level.D.col[view_col].get(row_index) * (row.pminplus_ed + row.pminmin_u) +
            level.U.col[view_col].get(row_index) * (row.pplusplus_ed + row.pplusmin_u);
    }
    const view_row = scatteringSourceRowSums(
        scaled_phase_coefficients,
        max_phase_index,
        level,
        i_fourier,
        geo,
        plm_basis,
        view_idx,
    );
    sum += level.E.get(view_idx) * (view_row.pminplus_ed + view_row.pminmin_u);
    return sum;
}

fn aerosolInterfaceWeightingFromScaledPhase(
    scaled_phase_coefficients: *const [basis.max_phase_coef]f64,
    ud: []const basis.UDField,
    ilevel: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) f64 {
    // aerosolInterfaceWeightingFromScaledPhase ---------------------------------------------------------------|
    // Non-RTM-quadrature aerosol altitude weighting for one interface.                                        |
    // --------------------------------------------------------------------------------------------------------|

    const d_sca_d_altitude = scaled_phase_coefficients[0];
    if (d_sca_d_altitude == 0.0) return 0.0;
    const max_phase_index = maxPhaseCoefficientIndex(scaled_phase_coefficients);
    if (i_fourier > max_phase_index) return 0.0;

    // Altitude interface weighting combines scattering source and absorption terms.
    return scatteringSourceWeightingFromScaledPhase(
        scaled_phase_coefficients,
        max_phase_index,
        ud,
        ilevel,
        i_fourier,
        geo,
        plm_basis,
    ) + d_sca_d_altitude * absorptionInterfaceWeighting(ud, &.{}, .{}, ilevel, false, geo);
}

// AerosolIntervalBounds --------------------------------------------------------------------------------------|
// Interior RTM level range where aerosol scattering Jacobian terms are active.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] bottom : usize                                                                                     |
// [ 8..15] top    : usize                                                                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                      |
const AerosolIntervalBounds = struct {
    bottom: usize,
    top: usize,
};
// ------------------------------------------------------------------------------------------------------------|

fn activeAerosolInteriorBounds(
    rtm_quadrature: common.RtmQuadratureGrid,
    end_level: usize,
) ?AerosolIntervalBounds {
    // activeAerosolInteriorBounds ----------------------------------------------------------------------------|
    // Find the aerosol Jacobian interval and expand it to include the bounding interfaces.                    |
    // --------------------------------------------------------------------------------------------------------|

    var first_active: ?usize = null;
    var last_active: ?usize = null;

    for (0..end_level + 1) |ilevel| {
        if (rtm_quadrature.levels[ilevel].aerosol_ksca_jacobian <= 0.0) {
            continue;
        }

        if (first_active == null) {
            first_active = ilevel;
        }

        last_active = ilevel;
    }

    const first = first_active orelse return null;
    const last = last_active orelse return null;
    if (first == 0 or last + 1 > end_level) {
        return null;
    }

    return .{ .bottom = first - 1, .top = last + 1 };
}

fn aerosolSingleScatteringAlbedo(layers: []const common.LayerInput) f64 {
    // aerosolSingleScatteringAlbedo --------------------------------------------------------------------------|
    // Collapse layer aerosol extinction and aerosol scattering into one effective aerosol SSA.                |
    //                                                                                                         |
    // call path                                                                                               |
    //   Aerosol Jacobian weighting calls this before optical-depth and pressure contributions are split.      |
    //                                                                                                         |
    // memory                                                                                                  |
    //   Reads two f64 fields from each LayerInput by pointer.                                                 |
    //   The scan stays on the transport layer slice, so weighting uses the rows that produced reflectance.    |
    //                                                                                                         |
    // math                                                                                                    |
    //   aerosol SSA = aerosol scattering optical depth / aerosol optical depth                                |
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

fn unitAerosolPhase(rtm_quadrature: common.RtmQuadratureGrid) ?UnitPhase {
    // unitAerosolPhase ---------------------------------------------------------------------------------------|
    // Return the unit aerosol phase expansion when aerosol phase coefficients are present.                    |
    // --------------------------------------------------------------------------------------------------------|

    const coefficients = rtm_quadrature.aerosol_phase_coefficients;
    if (coefficients[0] <= 0.0) return null;
    return .{
        .coefficients = coefficients,
        .max_index = maxPhaseCoefficientIndex(coefficients),
    };
}

fn commonActiveAerosolUnitPhase(
    rtm_quadrature: common.RtmQuadratureGrid,
    bounds: AerosolIntervalBounds,
) ?UnitPhase {
    // commonActiveAerosolUnitPhase ---------------------------------------------------------------------------|
    // Return the common aerosol phase expansion when any active level above the bottom needs it.              |
    // --------------------------------------------------------------------------------------------------------|

    for (bounds.bottom..bounds.top) |ilevel| {
        if (rtm_quadrature.levels[ilevel].aerosol_ksca_above_per_km > 0.0) return unitAerosolPhase(rtm_quadrature);
    }
    return null;
}

fn buildPhaseRowCache(
    phase_coefficients: *const [basis.max_phase_coef]f64,
    max_phase_index: usize,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) PhaseRowCache {
    // buildPhaseRowCache -------------------------------------------------------------------------------------|
    // Build Zplus/Zmin rows for every stream/view/solar row used by reflectance and weighting functions.      |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : once per aerosol Fourier term when rows can be shared                                      |
    //   costly   : PhaseKernelRow construction for every geometry row                                         |
    //   memory   : returns one 2.352 KiB stack value                                                          |
    //                                                                                                         |
    // calls                                                                                                   |
    //   fillZplusZminRowFromBasisLimited                                                                      |
    // --------------------------------------------------------------------------------------------------------|

    var cache = PhaseRowCache{
        .rows = undefined,
        .n = geo.nmutot,
    };
    for (0..geo.nmutot) |row_index| {
        cache.rows[row_index] = basis.fillZplusZminRowFromBasisLimited(
            i_fourier,
            phase_coefficients,
            max_phase_index,
            geo,
            plm_basis,
            row_index,
        );
    }
    return cache;
}

inline fn scatteringSourceRowSumsFromRows(
    rows: PhaseRows,
    level: *const basis.UDField,
    geo: *const basis.Geometry,
    row_index: usize,
) ScatteringSourceRowSums {
    // scatteringSourceRowSumsFromRows ------------------------------------------------------------------------|
    // Same source sums as scatteringSourceRowSums, but reuses a cached Zplus/Zmin row.                        |
    // --------------------------------------------------------------------------------------------------------|

    const solar_col: usize = 1;
    const solar_idx = geo.n_gauss + 1;
    const mu_row = @max(geo.u[row_index], direction_cosine_floor);
    var sums = ScatteringSourceRowSums{
        .pplusplus_ed = 0.0,
        .pminplus_ed = 0.0,
        .pminmin_u = 0.0,
        .pplusmin_u = 0.0,
    };
    for (0..geo.n_gauss) |imu| {
        const mu_col = @max(geo.u[imu], direction_cosine_floor);
        const pplus = (0.25 * rows.zplus[imu] / mu_row) / mu_col;
        const pmin = (0.25 * rows.zmin[imu] / mu_row) / mu_col;

        // Pair cached Pplus/Pminus factors with D_solar and U_solar fields.
        sums.pplusplus_ed += pplus * level.D.col[solar_col].get(imu);
        sums.pminplus_ed += pmin * level.D.col[solar_col].get(imu);
        sums.pminmin_u += pplus * level.U.col[solar_col].get(imu);
        sums.pplusmin_u += pmin * level.U.col[solar_col].get(imu);
    }
    const mu_solar = @max(geo.u[solar_idx], direction_cosine_floor);
    const pplus_direct = (0.25 * rows.zplus[solar_idx] / mu_row) / mu_solar;
    const pmin_direct = (0.25 * rows.zmin[solar_idx] / mu_row) / mu_solar;
    sums.pplusplus_ed += pplus_direct * level.E.get(solar_idx);
    sums.pminplus_ed += pmin_direct * level.E.get(solar_idx);
    return sums;
}

fn scatteringCoefficientInterfaceWeighting(
    aerosol_ksca_per_km: f64,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    rtm_quadrature: common.RtmQuadratureGrid,
    ilevel: usize,
    i_fourier: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
) f64 {
    // scatteringCoefficientInterfaceWeighting ----------------------------------------------------------------|
    // Scattering-coefficient interface weighting when phase rows are built on demand.                         |
    // Adds the matching absorption weighting because scattering coefficient changes total extinction too.     |
    // --------------------------------------------------------------------------------------------------------|

    if (aerosol_ksca_per_km <= 0.0) {
        return 0.0;
    }

    const unit_phase = unitAerosolPhase(rtm_quadrature) orelse return 0.0;
    const max_phase_index = unit_phase.max_index;
    if (i_fourier > max_phase_index) {
        return 0.0;
    }

    const source_weighting = scatteringSourceWeightingFromScaledPhase(
        unit_phase.coefficients,
        max_phase_index,
        ud,
        ilevel,
        i_fourier,
        geo,
        plm_basis,
    );
    const absorption_weighting = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        ilevel,
        use_pseudo_spherical,
        geo,
    );

    return source_weighting + absorption_weighting;
}

fn scatteringCoefficientInterfaceWeightingFromPhaseRows(
    phase_rows: *const PhaseRowCache,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    rtm_quadrature: common.RtmQuadratureGrid,
    ilevel: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
) f64 {
    // scatteringCoefficientInterfaceWeightingFromPhaseRows ---------------------------------------------------|
    // Cached-row version when the caller already built the aerosol phase rows for this Fourier term.          |
    // --------------------------------------------------------------------------------------------------------|

    const weighting = interfaceWeightingFromPhaseRows(
        phase_rows,
        ud,
        ud_sum_local,
        rtm_quadrature,
        ilevel,
        use_pseudo_spherical,
        geo,
    );
    return weighting.scattering_coefficient;
}

// InterfaceWeighting -----------------------------------------------------------------------------------------|
// Keeps scattering-coefficient and absorption interface terms together when both aerosol lanes need them.     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] scattering_coefficient  : f64                                                                      |
// [ 8..15] absorption              : f64                                                                      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = one stack value per aerosol interface weighting         |
const InterfaceWeighting = struct {
    scattering_coefficient: f64,
    absorption: f64,
};
// ------------------------------------------------------------------------------------------------------------|

fn interfaceWeightingFromPhaseRows(
    phase_rows: *const PhaseRowCache,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    rtm_quadrature: common.RtmQuadratureGrid,
    ilevel: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
) InterfaceWeighting {
    // interfaceWeightingFromPhaseRows ------------------------------------------------------------------------|
    // Evaluate scattering-source and absorption terms once for paired aerosol Jacobians. Steps:               |
    //                                                                                                         |
    //   1. compute scattering-source weighting from cached phase rows                                         |
    //   2. compute absorption weighting for the same interface                                                |
    //   3. return source + absorption for scattering coefficient and raw absorption separately                |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : active aerosol interfaces in paired derivative rtm_config                                  |
    //   memory   : reuses PhaseRowCache instead of rebuilding Zplus/Zmin rows                                 |
    //                                                                                                         |
    // math                                                                                                    |
    //   scattering coefficient weighting = scattering source weighting + absorption weighting                 |
    // --------------------------------------------------------------------------------------------------------|

    const source = scatteringSourceWeightingFromPhaseRows(
        phase_rows,
        ud,
        ilevel,
        geo,
    );
    const absorption = absorptionInterfaceWeighting(
        ud,
        ud_sum_local,
        rtm_quadrature,
        ilevel,
        use_pseudo_spherical,
        geo,
    );
    return .{
        .scattering_coefficient = source + absorption,
        .absorption = absorption,
    };
}

fn scatteringCoefficientInterfaceWeightingFromPhaseRowsIfActive(
    aerosol_ksca_per_km: f64,
    phase_rows: *const PhaseRowCache,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    rtm_quadrature: common.RtmQuadratureGrid,
    ilevel: usize,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
) f64 {
    // scatteringCoefficientInterfaceWeightingFromPhaseRowsIfActive -------------------------------------------|
    // Skip inactive aerosol interfaces before using cached phase rows.                                        |
    // --------------------------------------------------------------------------------------------------------|

    if (aerosol_ksca_per_km <= 0.0) return 0.0;
    return scatteringCoefficientInterfaceWeightingFromPhaseRows(
        phase_rows,
        ud,
        ud_sum_local,
        rtm_quadrature,
        ilevel,
        use_pseudo_spherical,
        geo,
    );
}

fn aerosolTotalExtinctionInterfaceWeighting(
    scattering_weighting: f64,
    absorption_weighting: f64,
    aerosol_ssa: f64,
) f64 {
    // aerosolTotalExtinctionInterfaceWeighting ---------------------------------------------------------------|
    // Blend scattering and absorption terms using aerosol single-scattering albedo.                           |
    //                                                                                                         |
    // math                                                                                                    |
    //   aerosol extinction weighting = SSA * scattering weighting + (1 - SSA) * absorption weighting          |
    // --------------------------------------------------------------------------------------------------------|

    return aerosol_ssa * scattering_weighting + (1.0 - aerosol_ssa) * absorption_weighting;
}

fn scatteringSourceWeightingFromPhaseRows(
    phase_rows: *const PhaseRowCache,
    ud: []const basis.UDField,
    ilevel: usize,
    geo: *const basis.Geometry,
) f64 {
    // scatteringSourceWeightingFromPhaseRows -----------------------------------------------------------------|
    // Cached-row scattering-source weighting for one interface. Steps:                                        |
    //                                                                                                         |
    //   1. read cached Zplus/Zmin rows                                                                        |
    //   2. build solar-column row sums                                                                        |
    //   3. contract them with view-column D, U, and direct E fields                                           |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : active aerosol interfaces when a shared row cache is available                             |
    //   costly   : Gauss stream reduction                                                                     |
    //   memory   : reads PhaseRowCache; no phase-row rebuild                                                  |
    //                                                                                                         |
    // math                                                                                                    |
    //   source += D_view * (PminplusD + PminminU)                                                             |
    //           + U_view * (PplusplusD + PplusminU)                                                           |
    //   source += E_view * (PminplusD + PminminU) for the direct view row                                     |
    // --------------------------------------------------------------------------------------------------------|

    const view_col: usize = 0;
    const view_idx = geo.viewIdx();
    const level = &ud[ilevel];

    var sum: f64 = 0.0;
    for (0..geo.n_gauss) |row_index| {
        const cached_row = &phase_rows.rows[row_index];
        const row = scatteringSourceRowSumsFromRows(
            .{
                .zplus = cached_row.zplus[0..phase_rows.n],
                .zmin = cached_row.zmin[0..phase_rows.n],
            },
            level,
            geo,
            row_index,
        );

        // Diffuse view field times cached solar-column source sums.
        sum += level.D.col[view_col].get(row_index) * (row.pminplus_ed + row.pminmin_u) +
            level.U.col[view_col].get(row_index) * (row.pplusplus_ed + row.pplusmin_u);
    }
    const cached_view_row = &phase_rows.rows[view_idx];
    const view_row = scatteringSourceRowSumsFromRows(
        .{
            .zplus = cached_view_row.zplus[0..phase_rows.n],
            .zmin = cached_view_row.zmin[0..phase_rows.n],
        },
        level,
        geo,
        view_idx,
    );

    // Direct view contribution uses the cached row at view_idx.
    sum += level.E.get(view_idx) * (view_row.pminplus_ed + view_row.pminmin_u);
    return sum;
}

fn cachedCommonAerosolPhaseRows(
    rtm_quadrature: common.RtmQuadratureGrid,
    bounds: AerosolIntervalBounds,
    i_fourier: usize,
    geo: *const basis.Geometry,
    plm_basis: *const basis.FourierPlmBasis,
    storage: *PhaseRowCache,
) ?*const PhaseRowCache {
    // cachedCommonAerosolPhaseRows ---------------------------------------------------------------------------|
    // Build a shared aerosol phase-row cache only when this Fourier term can contribute.                      |
    // --------------------------------------------------------------------------------------------------------|

    const unit_phase = commonActiveAerosolUnitPhase(rtm_quadrature, bounds) orelse return null;
    if (i_fourier > unit_phase.max_index) return null;
    storage.* = buildPhaseRowCache(unit_phase.coefficients, unit_phase.max_index, i_fourier, geo, plm_basis);
    return storage;
}

fn calcAerosolOpticalDepthWeightingFromPhaseRows(
    layers: []const common.LayerInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    bounds: AerosolIntervalBounds,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
    phase_rows: *const PhaseRowCache,
) f64 {
    // calcAerosolOpticalDepthWeightingFromPhaseRows ----------------------------------------------------------|
    // Cached-row aerosol optical-depth weighting over the active aerosol interval. Steps:                     |
    //                                                                                                         |
    //   1. get aerosol SSA from the layer totals                                                              |
    //   2. evaluate interface weighting at each active RTM level                                              |
    //   3. integrate the interface weighting over altitude with the trapezoid rule                            |
    //   4. divide by aerosol interval thickness                                                               |
    //                                                                                                         |
    // math                                                                                                    |
    //   AOD weighting = integral(interface weighting dz) / aerosol layer thickness                            |
    // --------------------------------------------------------------------------------------------------------|

    if (bounds.top <= bounds.bottom + 1) return 0.0;
    const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);
    const needs_absorption_weighting = (1.0 - aerosol_ssa) != 0.0;
    const denominator =
        rtm_quadrature.levels[bounds.top - 1].altitude_km -
        rtm_quadrature.levels[bounds.bottom].altitude_km;
    if (denominator <= 0.0) return 0.0;

    var integral: f64 = 0.0;
    const previous_weighting = interfaceWeightingFromPhaseRows(
        phase_rows,
        ud,
        ud_sum_local,
        rtm_quadrature,
        bounds.bottom,
        use_pseudo_spherical,
        geo,
    );
    var previous = aerosolTotalExtinctionInterfaceWeighting(
        previous_weighting.scattering_coefficient,
        if (needs_absorption_weighting)
            previous_weighting.absorption
        else
            0.0,
        aerosol_ssa,
    );
    for (bounds.bottom + 1..bounds.top) |ilevel| {
        const current_weighting = interfaceWeightingFromPhaseRows(
            phase_rows,
            ud,
            ud_sum_local,
            rtm_quadrature,
            ilevel,
            use_pseudo_spherical,
            geo,
        );
        const current = aerosolTotalExtinctionInterfaceWeighting(
            current_weighting.scattering_coefficient,
            if (needs_absorption_weighting)
                current_weighting.absorption
            else
                0.0,
            aerosol_ssa,
        );
        const dz = rtm_quadrature.levels[ilevel].altitude_km -
            rtm_quadrature.levels[ilevel - 1].altitude_km;

        // Trapezoid rule over altitude. Final division by interval thickness is below the loop.
        if (dz > 0.0) integral += 0.5 * (previous + current) * dz;
        previous = current;
    }
    return integral / denominator;
}

fn calcAerosolLayerPressureShiftWeightingFromPhaseRows(
    layers: []const common.LayerInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
    bounds: AerosolIntervalBounds,
    use_pseudo_spherical: bool,
    geo: *const basis.Geometry,
    phase_rows: *const PhaseRowCache,
) f64 {
    // calcAerosolLayerPressureShiftWeightingFromPhaseRows ----------------------------------------------------|
    // Cached-row pressure-shift weighting from top-minus-bottom interface sensitivity.                        |
    //                                                                                                         |
    // math                                                                                                    |
    //   pressure weighting = (top_sca - bottom_sca) * k_sca                                                   |
    //                    + (top_abs - bottom_abs) * k_abs                                                     |
    // --------------------------------------------------------------------------------------------------------|

    const aerosol_ssa = aerosolSingleScatteringAlbedo(layers);
    const top_has_scattering = rtm_quadrature.levels[bounds.top].aerosol_ksca_below_per_km > 0.0;
    const bottom_has_scattering = rtm_quadrature.levels[bounds.bottom].aerosol_ksca_above_per_km > 0.0;

    const top_interface: ?InterfaceWeighting = choose_top_interface: {
        if (!top_has_scattering) break :choose_top_interface null;

        break :choose_top_interface interfaceWeightingFromPhaseRows(
            phase_rows,
            ud,
            ud_sum_local,
            rtm_quadrature,
            bounds.top,
            use_pseudo_spherical,
            geo,
        );
    };
    const bottom_interface: ?InterfaceWeighting = choose_bottom_interface: {
        if (!bottom_has_scattering) break :choose_bottom_interface null;

        break :choose_bottom_interface interfaceWeightingFromPhaseRows(
            phase_rows,
            ud,
            ud_sum_local,
            rtm_quadrature,
            bounds.bottom,
            use_pseudo_spherical,
            geo,
        );
    };

    const top_sca_weighting = if (top_interface) |weighting| weighting.scattering_coefficient else 0.0;
    const bottom_sca_weighting = if (bottom_interface) |weighting| weighting.scattering_coefficient else 0.0;
    const ksca = rtm_quadrature.levels[bounds.top].aerosol_ksca_below_per_km;
    const kabs = if (aerosol_ssa > 0.0) ksca * (1.0 - aerosol_ssa) / aerosol_ssa else 0.0;
    const scattering_pressure_weighting = (top_sca_weighting - bottom_sca_weighting) * ksca;
    if (kabs == 0.0) return scattering_pressure_weighting;

    const top_abs_weighting = choose_top_absorption: {
        if (top_interface) |weighting| break :choose_top_absorption weighting.absorption;

        break :choose_top_absorption absorptionInterfaceWeighting(
            ud,
            ud_sum_local,
            rtm_quadrature,
            bounds.top,
            use_pseudo_spherical,
            geo,
        );
    };
    const bottom_abs_weighting = choose_bottom_absorption: {
        if (bottom_interface) |weighting| break :choose_bottom_absorption weighting.absorption;

        break :choose_bottom_absorption absorptionInterfaceWeighting(
            ud,
            ud_sum_local,
            rtm_quadrature,
            bounds.bottom,
            use_pseudo_spherical,
            geo,
        );
    };
    const absorption_pressure_weighting = (top_abs_weighting - bottom_abs_weighting) * kabs;
    return scattering_pressure_weighting + absorption_pressure_weighting;
}

fn maxFourierIndex(layers: []const common.LayerInput) usize {
    // maxFourierIndex ----------------------------------------------------------------------------------------|
    // Highest phase coefficient index present in layer phase functions.                                       |
    // --------------------------------------------------------------------------------------------------------|

    var max_index: usize = 0;
    for (layers) |*layer| {
        max_index = @max(max_index, layer.phase.maxIndex());
    }
    return max_index;
}

fn maxFourierIndexInterfaces(source_interfaces: []const common.SourceInterfaceInput) usize {
    // maxFourierIndexInterfaces ------------------------------------------------------------------------------|
    // Highest phase coefficient index present on source interfaces.                                           |
    // --------------------------------------------------------------------------------------------------------|

    var max_index: usize = 0;
    for (source_interfaces) |*source_interface| {
        max_index = @max(max_index, source_interface.phase_max_index_above);
        max_index = @max(max_index, source_interface.phase_max_index_below);
    }
    return max_index;
}

fn maxFourierIndexQuadrature(rtm_quadrature: common.RtmQuadratureGrid) usize {
    // maxFourierIndexQuadrature ------------------------------------------------------------------------------|
    // Highest phase coefficient index present on active RTM quadrature levels.                                |
    // --------------------------------------------------------------------------------------------------------|

    var max_index: usize = 0;
    for (rtm_quadrature.levels) |*level| {
        if (level.weight <= 0.0 or level.ksca <= 0.0) continue;
        max_index = @max(max_index, maxRtmQuadraturePhaseCoefficientIndex(level, rtm_quadrature));
    }
    return max_index;
}
