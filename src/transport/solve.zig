const std = @import("std");

const attenuation = @import("attenuation.zig");
const controls = @import("controls.zig");
const curved_sun_path = @import("../optics/curved_sun_path.zig");
const gauss_angles = @import("gauss_angles.zig");
const jacobian_states = @import("jacobian_states.zig");
const layer_depths = @import("../optics/layer_depths.zig");
const layer_reflect_transmit = @import("layer_reflect_transmit.zig");
const phase_basis = @import("phase_basis.zig");
const phase_table = @import("../setup/phase_table.zig");
const reflectance_helpers = @import("reflectance.zig");
const rows = @import("rows.zig");
const scattering_orders = @import("scattering_orders.zig");
const source_levels = @import("../optics/source_levels.zig");
const Perturbation = @import("../instrumentation/sensitivity.zig");

const math = std.math;

const direct_direction_cosine_floor: f64 = 0.05;

pub const Error = controls.PrepareError || attenuation.Error || gauss_angles.Error || error{
    InvalidShape,
};

// solve.zig ------------------------------------------------------------------------------------------------- |
// Transport-solve dispatch for explicit WP3 optical rows.                                                     |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports the non-integrated branch of main:`src/forward_model/radiative_transfer/labos/execute.zig`:         |
//   `directSurfaceOnly`, geometry setup, attenuation fill, RT layer build, scattering-order propagation,      |
//   Fourier weighting, tail stop, public clamp, and zero-Fourier surface-albedo tangent.                      |
//                                                                                                             |
// boundary                                                                                                    |
//   Inputs are explicit rows and scalars: angles, surface albedo, layer optics, source levels, curved-path    |
//   samples, and prepared transport controls. This file stores no scene, request, product storage, or cache.  |
//                                                                                                             |
// direct route                                                                                                |
//   The old scalar direct path used one total optical depth. The new explicit boundary has layer rows, so the |
//   direct route sums layer total optical depths before applying the same scalar formula.                     |
//                                                                                                             |
// allocation                                                                                                  |
//   This file allocates nothing. Callers pass borrowed work arrays sized before the per-wavelength solve.     |
// ------------------------------------------------------------------------------------------------------------|

// ViewAngles ------------------------------------------------------------------------------------------------ |
// Direction cosines and relative azimuth for one transport solve.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] solar_mu             : f64                                                                         |
// [ 8..15] view_mu              : f64                                                                         |
// [16..23] relative_azimuth_rad : f64                                                                         |
//                                                                                                             |
// footprint: per instance = 24 B (0.023 KiB); one stack value per high-resolution wavelength                  |
pub const ViewAngles = struct {
    solar_mu: f64,
    view_mu: f64,
    relative_azimuth_rad: f64 = 0.0,
};
// ReflectanceResult ----------------------------------------------------------------------------------------  |
// One top-of-atmosphere reflectance result and fixed state-order Jacobian vector.                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] reflectance : f64                                                                                  |
// [ 8..31] jacobian    : [3]f64                                                                               |
//                                                                                                             |
// footprint: per instance = 32 B (0.031 KiB); returned by value                                               |
pub const ReflectanceResult = struct {
    reflectance: f64,
    jacobian: jacobian_states.Vector = jacobian_states.zero(),
};
// ------------------------------------------------------------------------------------------------------------|

// TransportWorkArrays --------------------------------------------------------------------------------------  |
// Borrowed transport scratch passed to solveReflectance.                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// normal build: size 360 B (0.352 KiB), align 8                                                               |
// trace build : size 368 B (0.359 KiB), align 8                                                               |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] geometry                     : *GaussGeometry                                                    |
// [  8.. 23] dynamic_attenuation_data     : []f64                                                             |
// [ 24.. 39] dynamic_attenuation_tangent_data: []f64                                                          |
// [ 40.. 55] layer_transmittance          : []f64                                                             |
// [ 56.. 71] top_to_level_attenuation     : []f64                                                             |
// [ 72.. 87] rt_layers                    : []LayerRT                                                         |
// [ 88..103] rt_layers_tangent            : []LayerRT                                                         |
// [104..119] layer_phase_max_indices      : []usize                                                           |
// [120..135] effective_scattering_suffixes: []f64                                                             |
// [136..151] source_phase_max_indices     : []usize                                                           |
// [152..167] phase_row_cache              : []PhaseKernelRow                                                  |
// [168..183] phase_row_valid              : []bool                                                            |
// [184..199] curved_level_starts          : []const usize                                                     |
// [200..215] curved_level_altitudes_km    : []const f64                                                       |
// [216..327] normal build: orders         : OrdersWorkArrays                                                  |
// [328..343] normal build: plm_basis_cache: []FourierPlmBasis                                                 |
// [344..359] normal build: valid flags    : []bool                                                            |
// [328..335] trace build only: orders extra trace field                                                       |
// [336..351] trace build : plm_basis_cache: []FourierPlmBasis                                                 |
// [352..367] trace build : valid flags    : []bool                                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   Every slice borrows caller-owned memory, normally from TransportWorkerMemory.                             |
//   This view owns no heap allocation and stores no physics inputs or controls.                               |
pub const TransportWorkArrays = struct {
    geometry: *gauss_angles.GaussGeometry,
    dynamic_attenuation_data: []f64,
    dynamic_attenuation_tangent_data: []f64,
    layer_transmittance: []f64,
    top_to_level_attenuation: []f64,
    rt_layers: []rows.LayerRT,
    rt_layers_tangent: []rows.LayerRT,
    layer_phase_max_indices: []usize,
    effective_scattering_suffixes: []f64,
    source_phase_max_indices: []usize,
    phase_row_cache: []phase_basis.PhaseKernelRow,
    phase_row_valid: []bool,
    curved_level_starts: []const usize,
    curved_level_altitudes_km: []const f64,
    orders: scattering_orders.OrdersWorkArrays,
    plm_basis_cache: []phase_basis.FourierPlmBasis,
    plm_basis_cache_valid: []bool,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn solveReflectance(
    angles: ViewAngles,
    surface_albedo: f64,
    layers: []const layer_depths.LayerOptics,
    level_sources: []const source_levels.SourceLevel,
    curved_samples: []const curved_sun_path.CurvedSunPathSample,
    phase: phase_table.PhaseTable,
    rayleigh_phase_coefficient2: f64,
    prepared_config: controls.SolveConfig,
    work: *TransportWorkArrays,
) Error!ReflectanceResult {
    // solveReflectance -------------------------------------------------------------------------------------  |
    // Dispatch one explicit transport solve. The direct route follows old LABOS scalar behavior; the          |
    // scattering route wires the non-integrated Fourier path through caller-owned work arrays.                |
    //                                                                                                         |
    // direct math                                                                                             |
    //   direct path = exp(-tau / max(mu0, 0.05)) * exp(-tau / max(muv, 0.05))                                 |
    //   reflectance = surface_albedo * direct path                                                            |
    //                                                                                                         |
    // unsupported routes                                                                                      |
    //   Pressure derivatives require the integrated-source RTM quadrature weighting route.                    |
    // --------------------------------------------------------------------------------------------------------|
    const config = try controls.prepareSolveConfig(prepared_config);
    if (config.controls.scattering == .none) {
        if (config.controls.use_spherical_correction) return error.UnsupportedRadiativeTransferControls;
        return directSurfaceOnly(
            angles,
            surface_albedo,
            totalLayerOpticalDepth(layers),
            config.derivative_mode,
            config.derivative_state_mask,
        );
    }

    const wants_aerosol_layer_pressure =
        config.derivative_mode != .none and
        jacobian_states.includes(config.derivative_state_mask, .aerosol_layer_mid_pressure_hpa);
    const use_integrated_source =
        config.controls.integrate_source_function and
        layers.len > 1 and
        level_sources.len == layers.len + 1;
    if (config.controls.integrate_source_function and !use_integrated_source) {
        return error.UnsupportedRadiativeTransferControls;
    }
    if (!use_integrated_source and wants_aerosol_layer_pressure) {
        return error.UnsupportedDerivativeMode;
    }

    const curved_grid = attenuation.CurvedSunPathGrid{
        .samples = curved_samples,
        .level_sample_starts = work.curved_level_starts,
        .level_altitudes_km = work.curved_level_altitudes_km,
    };

    return solveLayerResolvedScattering(
        angles,
        surface_albedo,
        layers,
        phase,
        rayleigh_phase_coefficient2,
        level_sources,
        curved_grid,
        use_integrated_source,
        config,
        work,
    );
}

pub fn directSurfaceOnly(
    angles: ViewAngles,
    surface_albedo: f64,
    total_optical_depth: f64,
    derivative_mode: controls.DerivativeMode,
    derivative_state_mask: jacobian_states.StateMask,
) ReflectanceResult {
    // directSurfaceOnly ------------------------------------------------------------------------------------  |
    // Scalar direct-surface path from old LABOS execute.zig.                                                  |
    //                                                                                                         |
    // math                                                                                                    |
    //   direct path = exp(-tau / mu0) * exp(-tau / muv)                                                       |
    //   reflectance = surface_albedo * direct path                                                            |
    //                                                                                                         |
    // numerical guard                                                                                         |
    //   `0.05` is the old LABOS direct-route cosine floor. It prevents grazing directions from producing      |
    //   unstable direct-beam exponentials.                                                                    |
    // --------------------------------------------------------------------------------------------------------|
    const mu0 = @max(angles.solar_mu, direct_direction_cosine_floor);
    const muv = @max(angles.view_mu, direct_direction_cosine_floor);
    const direct = math.exp(-total_optical_depth / mu0) * math.exp(-total_optical_depth / muv);
    const raw_reflectance = surface_albedo * direct;
    const wants_surface_albedo =
        derivative_mode != .none and
        jacobian_states.includes(derivative_state_mask, .surface_albedo);

    var jacobian = jacobian_states.zero();
    if (wants_surface_albedo and raw_reflectance >= 0.0 and raw_reflectance < 2.0) {
        jacobian_states.set(&jacobian, .surface_albedo, direct);
    }

    return .{
        .reflectance = math.clamp(raw_reflectance, 0.0, 2.0),
        .jacobian = jacobian,
    };
}

fn totalLayerOpticalDepth(layers: []const layer_depths.LayerOptics) f64 {
    // totalLayerOpticalDepth -------------------------------------------------------------------------------  |
    // Reduce explicit layer rows into the scalar tau consumed by the old direct-surface formula.              |
    // --------------------------------------------------------------------------------------------------------|
    var total: f64 = 0.0;
    for (layers) |layer| total += layer.total_optical_depth;
    return total;
}

fn solveLayerResolvedScattering(
    angles: ViewAngles,
    surface_albedo: f64,
    layers: []const layer_depths.LayerOptics,
    phase: phase_table.PhaseTable,
    rayleigh_phase_coefficient2: f64,
    level_sources: []const source_levels.SourceLevel,
    curved_grid: attenuation.CurvedSunPathGrid,
    use_integrated_source: bool,
    config: controls.SolveConfig,
    work: *TransportWorkArrays,
) Error!ReflectanceResult {
    // solveLayerResolvedScattering -----------------------------------------------------------------------    |
    // Run the old layer-resolved LABOS Fourier route with caller-owned storage.                               |
    //                                                                                                         |
    // steps                                                                                                   |
    //   1. build direction geometry and direct-beam attenuation                                               |
    //   2. prepare per-layer phase limits and layer-doubling suffix rows                                      |
    //   3. loop retained Fourier terms: PLM basis -> RT layers -> scattering orders -> rho_m                  |
    //   4. add Fourier-weighted rho_m and requested supported tangents                                        |
    //   5. stop at the old Fourier tail gate and clamp the public reflectance                                 |
    //                                                                                                         |
    // aerosol Jacobians                                                                                       |
    //   Non-integrated AOD uses the old tangent-order solve. Integrated-source AOD and pressure use the old   |
    //   RTM-quadrature weighting route over source levels and local order sums.                               |
    // --------------------------------------------------------------------------------------------------------|
    if (layers.len == 0) return .{ .reflectance = 0.0 };

    const mu0 = @max(angles.solar_mu, direct_direction_cosine_floor);
    const muv = @max(angles.view_mu, direct_direction_cosine_floor);
    work.geometry.* = try gauss_angles.GaussGeometry.init(config.controls.nGauss(), mu0, muv);
    const geometry = work.geometry;
    const layer_count = layers.len;
    const level_count = layer_count + 1;

    if (work.rt_layers.len < level_count or
        work.rt_layers_tangent.len < level_count or
        work.layer_phase_max_indices.len < layer_count or
        work.phase_row_cache.len < level_count or
        work.phase_row_valid.len < level_count or
        work.orders.ud.len < level_count or
        work.orders.ud_orde.len < level_count or
        work.orders.ud_local.len < level_count or
        work.orders.ud_tangent_orde.len < level_count or
        work.orders.ud_tangent_local.len < level_count or
        work.orders.rt_active.len < level_count)
    {
        return error.InvalidShape;
    }

    var dynamic_attenuation: ?attenuation.DynamicAttenuation = null;
    var runtime_attenuation: ?attenuation.RuntimeAttenuation = null;
    if (use_integrated_source) {
        runtime_attenuation = try attenuation.fillRuntimeInBuffers(
            work.layer_transmittance,
            work.top_to_level_attenuation,
            layers,
            curved_grid,
            geometry,
            config.controls.use_spherical_correction,
        );
    } else {
        dynamic_attenuation = try attenuation.fillDynamicWithLayerCache(
            work.dynamic_attenuation_data,
            work.layer_transmittance,
            layers,
            curved_grid,
            geometry,
            config.controls.use_spherical_correction,
        );
    }

    const layer_phase_max_indices = work.layer_phase_max_indices[0..layer_count];
    layer_reflect_transmit.fillLayerPhaseMaxIndices(
        layer_phase_max_indices,
        layers,
        phase,
        rayleigh_phase_coefficient2,
    );
    const source_phase_max_indices = work.source_phase_max_indices[0..level_count];
    fillSourcePhaseMaxIndicesFromLayers(source_phase_max_indices, layer_phase_max_indices);

    const phase_max = maxLayerPhaseIndex(layer_phase_max_indices);
    const fourier_max = config.controls.performance_thresholds.cappedFourierMax(phase_max);
    const phase_suffix_stride = @min(phase_max, fourier_max) + 1;
    const suffix_required = layer_count * phase_suffix_stride;
    if (work.effective_scattering_suffixes.len < suffix_required) return error.InvalidShape;
    const effective_scattering_suffixes = work.effective_scattering_suffixes[0..suffix_required];
    layer_reflect_transmit.fillLayerEffectiveScatteringSuffixes(
        effective_scattering_suffixes,
        layers,
        phase,
        rayleigh_phase_coefficient2,
        layer_phase_max_indices,
        phase_suffix_stride,
    );

    const rt_layers = work.rt_layers[0..level_count];
    const order_count: usize = @intCast(config.controls.resolvedNumOrdersMax(totalScatteringOpticalDepth(layers)));
    const wants_surface_albedo =
        config.derivative_mode != .none and
        jacobian_states.includes(config.derivative_state_mask, .surface_albedo);
    const wants_aerosol_optical_depth =
        config.derivative_mode != .none and
        jacobian_states.includes(config.derivative_state_mask, .aerosol_optical_depth);
    const wants_aerosol_layer_pressure =
        config.derivative_mode != .none and
        jacobian_states.includes(config.derivative_state_mask, .aerosol_layer_mid_pressure_hpa);
    const wants_any_jacobian =
        config.derivative_mode != .none and
        jacobian_states.activeStateCount(config.derivative_state_mask) != 0;
    const layer_phase_row_cache = work.phase_row_cache[0..level_count];
    const layer_phase_row_valid = work.phase_row_valid[0..level_count];

    var result_reflectance: f64 = 0.0;
    var surface_albedo_tangent: f64 = 0.0;
    var aerosol_optical_depth_tangent: f64 = 0.0;
    var aerosol_layer_pressure_tangent: f64 = 0.0;
    for (0..fourier_max + 1) |fourier_index| {
        const plm_basis = try cachedPlmBasis(
            fourier_index,
            phase_max,
            geometry,
            work.plm_basis_cache,
            work.plm_basis_cache_valid,
        );

        layer_reflect_transmit.fillLayerReflectTransmitRowsWithBasis(
            rt_layers,
            layers,
            fourier_index,
            geometry,
            config.controls,
            phase,
            rayleigh_phase_coefficient2,
            plm_basis,
            layer_phase_max_indices,
            effective_scattering_suffixes,
            phase_suffix_stride,
            if (use_integrated_source) layer_phase_row_cache else null,
            if (use_integrated_source) layer_phase_row_valid else null,
            work.orders.rt_active,
            null,
        );
        rt_layers[0] = layer_reflect_transmit.fillSurface(fourier_index, surface_albedo, geometry);
        work.orders.rt_active[0] = fourier_index == 0 and surface_albedo != 0.0;

        const orders_view = choose_orders_view: {
            if (use_integrated_source) {
                if (wants_any_jacobian) {
                    break :choose_orders_view scattering_orders.solveOrdersWithActiveLocalSum(
                        &work.orders,
                        0,
                        layer_count,
                        geometry,
                        runtime_attenuation.?,
                        rt_layers,
                        config.controls,
                        order_count,
                    );
                }

                break :choose_orders_view scattering_orders.solveOrdersWithActive(
                    &work.orders,
                    0,
                    layer_count,
                    geometry,
                    runtime_attenuation.?,
                    rt_layers,
                    config.controls,
                    order_count,
                );
            }

            break :choose_orders_view scattering_orders.solveOrdersWithActive(
                &work.orders,
                0,
                layer_count,
                geometry,
                dynamic_attenuation.?,
                rt_layers,
                config.controls,
                order_count,
            );
        };
        const rho_m = choose_reflectance_coefficient: {
            if (use_integrated_source) {
                break :choose_reflectance_coefficient reflectance_helpers.integratedSourceCoefficient(
                    layers,
                    level_sources,
                    orders_view.ud,
                    layer_count,
                    fourier_index,
                    geometry,
                    plm_basis,
                    phase,
                    source_phase_max_indices,
                );
            }

            break :choose_reflectance_coefficient reflectance_helpers.topReflectanceCoefficient(
                orders_view.ud,
                layer_count,
                geometry,
            );
        };
        const contribution = reflectance_helpers.weightedFourierContribution(
            fourier_index,
            angles.relative_azimuth_rad,
            rho_m,
            config.controls.performance_thresholds,
        );
        result_reflectance += contribution.weighted;

        if (wants_surface_albedo and fourier_index == 0) {
            surface_albedo_tangent += reflectance_helpers.surfaceAlbedoWeighting(orders_view.ud, geometry);
        }
        const evaluate_aerosol_tangent =
            config.controls.performance_thresholds.shouldEvaluateAerosolTangent(fourier_index);
        if (use_integrated_source and evaluate_aerosol_tangent and
            (wants_aerosol_optical_depth or wants_aerosol_layer_pressure))
        {
            const tangent = choose_integrated_aerosol_tangent: {
                if (wants_aerosol_optical_depth and wants_aerosol_layer_pressure) {
                    break :choose_integrated_aerosol_tangent reflectance_helpers.integratedAerosolDerivativeWeighting(
                        layers,
                        level_sources,
                        orders_view.ud,
                        orders_view.ud_sum_local,
                        layer_count,
                        fourier_index,
                        config.controls.use_spherical_correction,
                        geometry,
                        plm_basis,
                        phase,
                    );
                }

                if (wants_aerosol_optical_depth) {
                    break :choose_integrated_aerosol_tangent reflectance_helpers.AerosolDerivativeWeighting{
                        .aerosol_optical_depth = reflectance_helpers.integratedAerosolOpticalDepthWeighting(
                            layers,
                            level_sources,
                            orders_view.ud,
                            orders_view.ud_sum_local,
                            layer_count,
                            fourier_index,
                            config.controls.use_spherical_correction,
                            geometry,
                            plm_basis,
                            phase,
                        ),
                    };
                }

                break :choose_integrated_aerosol_tangent reflectance_helpers.AerosolDerivativeWeighting{
                    .aerosol_layer_mid_pressure_hpa = reflectance_helpers.integratedAerosolLayerPressureShiftWeighting(
                        layers,
                        level_sources,
                        orders_view.ud,
                        orders_view.ud_sum_local,
                        layer_count,
                        fourier_index,
                        config.controls.use_spherical_correction,
                        geometry,
                        plm_basis,
                        phase,
                    ),
                };
            };

            if (wants_aerosol_optical_depth) {
                aerosol_optical_depth_tangent += Perturbation.scalar(
                    .aerosol_aod_tangent,
                    .{
                        .fourier_index = @intCast(fourier_index),
                        .state_index = @intCast(jacobian_states.stateIndex(.aerosol_optical_depth)),
                    },
                    contribution.weight * tangent.aerosol_optical_depth,
                );
            }

            if (wants_aerosol_layer_pressure) {
                aerosol_layer_pressure_tangent += Perturbation.scalar(
                    .aerosol_pressure_tangent,
                    .{
                        .fourier_index = @intCast(fourier_index),
                        .state_index = @intCast(jacobian_states.stateIndex(.aerosol_layer_mid_pressure_hpa)),
                    },
                    contribution.weight * tangent.aerosol_layer_mid_pressure_hpa,
                );
            }
        } else if (!use_integrated_source and wants_aerosol_optical_depth and evaluate_aerosol_tangent) {
            const tangent_attenuation = try attenuation.fillDynamicTangent(
                work.dynamic_attenuation_tangent_data,
                layers,
                .aerosol_optical_depth,
                geometry,
            );
            const rt_layers_tangent = work.rt_layers_tangent[0..level_count];
            layer_reflect_transmit.fillLayerReflectTransmitTangentRowsWithBasis(
                rt_layers_tangent,
                layers,
                .aerosol_optical_depth,
                fourier_index,
                geometry,
                config.controls,
                phase,
                rayleigh_phase_coefficient2,
                plm_basis,
            );

            const tangent_orders = scattering_orders.solveOrdersTangent(
                &work.orders,
                0,
                layer_count,
                geometry,
                dynamic_attenuation.?,
                tangent_attenuation,
                rt_layers,
                rt_layers_tangent,
                config.controls,
                order_count,
            );

            const tangent_rho_m =
                reflectance_helpers.topReflectanceCoefficient(tangent_orders.ud, layer_count, geometry);

            aerosol_optical_depth_tangent += Perturbation.scalar(
                .aerosol_aod_tangent,
                .{
                    .fourier_index = @intCast(fourier_index),
                    .state_index = @intCast(jacobian_states.stateIndex(.aerosol_optical_depth)),
                },
                contribution.weight * tangent_rho_m,
            );
        }
        if (contribution.tail_break) break;
    }

    var jacobian = jacobian_states.zero();
    if (wants_surface_albedo) {
        jacobian_states.set(&jacobian, .surface_albedo, surface_albedo_tangent);
    }
    if (wants_aerosol_optical_depth) {
        jacobian_states.set(&jacobian, .aerosol_optical_depth, aerosol_optical_depth_tangent);
    }
    if (wants_aerosol_layer_pressure) {
        jacobian_states.set(&jacobian, .aerosol_layer_mid_pressure_hpa, aerosol_layer_pressure_tangent);
    }
    return .{
        .reflectance = reflectance_helpers.clampPublicReflectance(result_reflectance),
        .jacobian = jacobian,
    };
}

fn cachedPlmBasis(
    fourier_index: usize,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    cache: []phase_basis.FourierPlmBasis,
    cache_valid: []bool,
) Error!*const phase_basis.FourierPlmBasis {
    // cachedPlmBasis --------------------------------------------------------------------------------------   |
    // Reuse the Fourier PLM basis row for one geometry when caller-owned cache storage is available.          |
    // --------------------------------------------------------------------------------------------------------|
    if (fourier_index >= phase_table.coefficient_count or
        max_phase_index >= phase_table.coefficient_count or
        fourier_index >= cache.len or
        fourier_index >= cache_valid.len)
    {
        return error.InvalidShape;
    }

    const needs_rebuild = !cache_valid[fourier_index] or
        cache[fourier_index].max_phase_index < max_phase_index;
    if (needs_rebuild) {
        cache[fourier_index] = phase_basis.FourierPlmBasis.init(
            fourier_index,
            max_phase_index,
            geometry,
        );
        cache_valid[fourier_index] = true;
    }
    return &cache[fourier_index];
}

fn maxLayerPhaseIndex(indices: []const usize) usize {
    // maxLayerPhaseIndex -----------------------------------------------------------------------------------  |
    // Return the highest layer phase index that can contribute to the Fourier route.                          |
    // --------------------------------------------------------------------------------------------------------|
    var max_index: usize = 0;
    for (indices) |index| max_index = @max(max_index, index);
    return max_index;
}

fn fillSourcePhaseMaxIndicesFromLayers(
    source_phase_max_indices: []usize,
    layer_phase_max_indices: []const usize,
) void {
    // fillSourcePhaseMaxIndicesFromLayers --------------------------------------------------------------------|
    // Port main:`radiative_transfer/labos/reflectance.zig` fillAdjacentLayerPhaseMaxIndices.                  |
    // Integrated-source RTM quadrature levels use the larger phase ceiling from adjacent transport layers.    |
    // --------------------------------------------------------------------------------------------------------|
    const layer_count = layer_phase_max_indices.len;
    std.debug.assert(source_phase_max_indices.len >= layer_count + 1);
    if (layer_count == 0) {
        if (source_phase_max_indices.len != 0) source_phase_max_indices[0] = 0;
        return;
    }

    source_phase_max_indices[0] = layer_phase_max_indices[0];
    for (1..layer_count) |level_index| {
        source_phase_max_indices[level_index] = @max(
            layer_phase_max_indices[level_index - 1],
            layer_phase_max_indices[level_index],
        );
    }
    source_phase_max_indices[layer_count] = layer_phase_max_indices[layer_count - 1];
}

fn totalScatteringOpticalDepth(layers: []const layer_depths.LayerOptics) f64 {
    // totalScatteringOpticalDepth --------------------------------------------------------------------------  |
    // Sum layer scattering optical depth for the old default scattering-order cap.                            |
    // --------------------------------------------------------------------------------------------------------|
    var total: f64 = 0.0;
    for (layers) |layer| total += layer.total_scattering_optical_depth;
    return total;
}

comptime {
    const expected_work_size: usize = if (@sizeOf(scattering_orders.OrdersWorkArrays) == 120) 368 else 360;
    std.debug.assert(@sizeOf(ViewAngles) == 24);
    std.debug.assert(@sizeOf(ReflectanceResult) == 32);
    std.debug.assert(@sizeOf(TransportWorkArrays) == expected_work_size);
}
