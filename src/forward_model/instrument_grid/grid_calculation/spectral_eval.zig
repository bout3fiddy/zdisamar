const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const common = @import("../../radiative_transfer/root.zig");
const jacobian = @import("../../jacobian/root.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const cache_module = @import("cache.zig");
const spectral_forward = @import("spectral_forward.zig");
const Types = @import("types.zig");
const Storage = @import("storage.zig");
const Plan = @import("wavelength_plan.zig");
const solar_compat = @import("../../../input/reference_data/solar_irradiance.zig");

const Allocator = std.mem.Allocator;
const Error = Storage.Error;

// spectral_eval.zig ---------------------------------------------------------------------------------------------------- |
// Consumes the retained wavelength plan for one product run. wavelength_sampling.zig has already turned                  |
// scene/instrument controls into compact row references; this file uses those references to prefetch the                 |
// high-resolution radiance misses once and gather nominal radiance, Jacobian, and irradiance rows without                |
// re-entering instrument-kernel planning.                                                                                |
//                                                                                                                        |
// called by                                                                                                              |
//   simulate.zig uses this in three phases:                                                                              |
//     1. resolveSimulationPlan asks prefetchForwardSamples to fill one dense result row per unique radiance              |
//        miss before nominal output rows are assembled                                                                   |
//     2. fillRadianceSamples calls integratePrefetchedForwardAtNominal for each nominal wavelength                       |
//     3. fillIrradianceSamples calls integrateIrradianceAtNominal for each nominal wavelength                            |
//                                                                                                                        |
// retained plan shape                                                                                                    |
//   WavelengthSampling.rows[i] carries the nominal wavelength, the shifted radiance and irradiance wavelengths,          |
//   and two IntegrationKernelRef values. ForwardMissPlan.rows[i].start points into sample_indices; the row's             |
//   radiance_integration.activeSampleCount() gives the length. sample_indices stores dense indexes into                  |
//   forward_results, so the gather loop never consults the deduplication hash map.                                       |
//                                                                                                                        |
// main paths                                                                                                             |
//   prefetchForwardSamples              -> spectral_forward.zig -> LABOS for each unique radiance miss                   |
//   integratePrefetchedForwardAtNominal -> sample_indices -> forward_results -> weighted radiance/Jacobian row           |
//   integrateIrradianceAtNominal        -> integration offsets -> exact-wavelength solar cache -> weighted E0 row        |
//   cachedIrradianceAtWavelength        -> operational solar table when DISAMAR HR support covers the wavelength,        |
//                                          otherwise the shared solar compatibility source order                         |
//                                                                                                                        |
// hot path                                                                                                               |
//   Nominal-row gather walks only slices already owned by the simulation plan: row refs, sample_indices, compact         |
//   integration weights, and dense ForwardIntegratedSample rows. Disabled kernels return the single prefetched           |
//   result directly. Integrated rows stream weights once; active Jacobian columns are accumulated only when the          |
//   solve config asks for derivatives. Irradiance mirrors the same offset/weight contract and reads solar support        |
//   data for each high-resolution sample.                                                                                |
//                                                                                                                        |
// weight contract                                                                                                        |
//   Integration weights are produced and normalized by implementations/instrument/integration.zig. These loops           |
//   apply the weights exactly once and do not renormalize. Shape checks guard row_ref/count/index mismatches             |
//   before borrowed arrays are indexed.                                                                                  |
//                                                                                                                        |
// memory                                                                                                                 |
//   Forward results, row refs, sample indexes, and kernel side arrays are borrowed from ResolvedSimulationPlan.          |
//   SpectralEvaluationCache owns only the per-run exact-wavelength irradiance hash map keyed by f64 bits; it is          |
//   used to avoid repeated solar interpolation when radiance and irradiance kernels revisit the same support.            |
// ---------------------------------------------------------------------------------------------------------------------- |

pub const ForwardIntegratedSample = spectral_forward.ForwardIntegratedSample;
pub const ForwardCacheMiss = Plan.ForwardCacheMiss;
pub const preferredForwardWorkerCount = spectral_forward.preferredForwardWorkerCount;

pub const SpectralEvaluationCache = cache_module.SpectralEvaluationCache;

pub fn integratePrefetchedForwardAtNominal(
    rtm_config: common.SolveConfig,
    results: []const ForwardIntegratedSample,
    row_ref: Plan.ForwardSampleIndexRef,
    sample_indices: []const u32,
    integration: *const Plan.IntegrationKernelRef,
    kernel_storage: Plan.IntegrationKernelStorage,
) Error!ForwardIntegratedSample {
    // integratePrefetchedForwardAtNominal ------------------------------------------------------------------------------ |
    // Accumulate one nominal radiance row from already-prefetched high-resolution forward results.                       |
    //                                                                                                                    |
    // data flow                                                                                                          |
    //   row_ref.start -> sample_indices[start..start + count] -> results[result_index]                                   |
    //                                                                                                                    |
    // math                                                                                                               |
    //   L_i      = sum_j weight_ij * L(lambda_i + offset_ij)                                                             |
    //   dL_i/dx  = sum_j weight_ij * dL(lambda_i + offset_ij)/dx for active derivative states                            |
    //                                                                                                                    |
    // disabled-kernel row                                                                                                |
    //   count = 1, weight = 1, offset = 0. The function returns the single prefetched result directly.                   |
    //                                                                                                                    |
    // integrated row                                                                                                     |
    //   The instrument integration builder already produced the weights used here. This loop applies them                |
    //   exactly once and does not renormalize.                                                                           |
    //                                                                                                                    |
    // why                                                                                                                |
    //   Wavelength planning has already deduplicated misses, so this hot loop avoids hash lookups.                       |
    // ------------------------------------------------------------------------------------------------------------------ |

    const start: usize = @intCast(row_ref.start);
    const count = integration.activeSampleCount();
    if (count == 0 or start > sample_indices.len or count > sample_indices.len - start) {
        return error.ShapeMismatch;
    }
    const indices = sample_indices[start .. start + count];

    if (!integration.enabled()) {
        const result_index: usize = @intCast(indices[0]);
        if (result_index >= results.len) return error.ShapeMismatch;
        return results[result_index];
    }

    const samples = integration.samples(kernel_storage);
    if (samples.weights.len != indices.len) return error.ShapeMismatch;

    var radiance_sum: f64 = 0.0;
    var jacobian_sum = jacobian.zero();
    const active_state_count = jacobian.activeStateCount(rtm_config.derivative_state_mask);
    const wants_jacobian = rtm_config.derivative_mode != .none and active_state_count != 0;
    for (indices, samples.weights) |result_index_u32, weight| {
        const result_index: usize = @intCast(result_index_u32);
        if (result_index >= results.len) return error.ShapeMismatch;
        const sample = results[result_index];
        radiance_sum += weight * sample.radiance;
        if (wants_jacobian) {
            jacobian.addScaledMasked(&jacobian_sum, sample.jacobian, weight, rtm_config.derivative_state_mask);
        }
    }

    return .{
        .radiance = radiance_sum,
        .jacobian = jacobian_sum,
    };
}

pub fn integrateIrradianceAtNominal(
    scene: *const Scene,
    nominal_wavelength_nm: f64,
    cache: *SpectralEvaluationCache,
    integration: *const Plan.IntegrationKernelRef,
    kernel_storage: Plan.IntegrationKernelStorage,
) Error!f64 {
    // integrateIrradianceAtNominal ------------------------------------------------------------------------------------- |
    // Accumulate one nominal irradiance row from solar irradiance samples. This mirrors the radiance                     |
    // integration route so the two channels use the same instrument-response offsets and weights.                        |
    //                                                                                                                    |
    // math                                                                                                               |
    //   E0_i = E0(lambda_i) when no integration kernel is active                                                         |
    //   E0_i = sum_j weight_ij * E0(lambda_i + offset_ij) otherwise                                                      |
    //                                                                                                                    |
    // shared contract                                                                                                    |
    //   Irradiance uses the same integration offsets and weights as the radiance channel selected for                    |
    //   irradiance. Radiance samples come from LABOS transport; irradiance samples come from solar support data.         |
    // ------------------------------------------------------------------------------------------------------------------ |

    if (!integration.enabled()) {
        return cachedIrradianceAtWavelength(scene, nominal_wavelength_nm, cache);
    }

    var irradiance_sum: f64 = 0.0;
    const samples = integration.samples(kernel_storage);
    for (samples.offsets_nm, samples.weights) |offset_nm, weight| {
        irradiance_sum += weight * try cachedIrradianceAtWavelength(
            scene,
            nominal_wavelength_nm + offset_nm,
            cache,
        );
    }
    return irradiance_sum;
}

pub fn prefetchForwardSamples(
    allocator: Allocator,
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    misses: []const ForwardCacheMiss,
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache,
    results: []ForwardIntegratedSample,
    thread_pool: ?*std.Thread.Pool,
    trace_phase_timing: ?*Storage.TracePhaseTiming,
) Error!void {
    // prefetchForwardSamples ------------------------------------------------------------------------------------------- |
    // Compute every unique high-resolution forward miss into a dense result array before nominal-row                     |
    // integration starts.                                                                                                |
    //                                                                                                                    |
    // output contract                                                                                                    |
    //   results[index] corresponds to misses[index]. buildForwardMissPlan stores only these dense indexes in             |
    //   each nominal row, so later integration reads the dense result array directly.                                    |
    // ------------------------------------------------------------------------------------------------------------------ |

    if (misses.len == 0) return;
    if (results.len != misses.len) return error.ShapeMismatch;

    try spectral_forward.prefetchForwardSamples(
        allocator,
        scene,
        rtm_config,
        prepared,
        misses,
        profile_spectroscopy_caches,
        results,
        thread_pool,
        trace_phase_timing,
    );
}

fn cachedIrradianceAtWavelength(
    scene: *const Scene,
    wavelength_nm: f64,
    cache: *SpectralEvaluationCache,
) Error!f64 {
    // cachedIrradianceAtWavelength ------------------------------------------------------------------------------------- |
    // Return solar irradiance at one exact wavelength, caching by the f64 bit pattern.                                   |
    //                                                                                                                    |
    // route                                                                                                              |
    //   DISAMAR high-resolution grid with covering operational solar table -> in-bounds operational interpolation        |
    //   otherwise                                           -> solar_irradiance.zig compatibility source order           |
    // ------------------------------------------------------------------------------------------------------------------ |

    const key = SpectralEvaluationCache.keyFor(wavelength_nm);
    if (cache.irradiance.get(key)) |cached| return cached;

    const response = scene.observation_model.resolvedChannelControls(.irradiance).response;
    const operational_band_support = scene.observation_model.primaryOperationalBandSupport();
    const value = choose_value: {
        break :choose_value if (response.integration_mode == .disamar_hr_grid and
            operational_band_support.operational_solar_spectrum.enabled())
            operational_band_support.operational_solar_spectrum.interpolateIrradianceWithinBounds(wavelength_nm) orelse
                solar_compat.irradianceAtWavelength(scene, wavelength_nm)
        else
            solar_compat.irradianceAtWavelength(scene, wavelength_nm);
    };
    try cache.irradiance.put(key, value);
    return value;
}
