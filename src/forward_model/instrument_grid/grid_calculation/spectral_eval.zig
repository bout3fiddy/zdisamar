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
//   solve config asks for derivatives. Irradiance mirrors the same offset/weight contract but reads solar support        |
//   instead of LABOS results.                                                                                            |
//                                                                                                                        |
// weight contract                                                                                                        |
//   Integration weights are produced and normalized by implementations/instrument/integration.zig. These loops           |
//   apply the weights exactly once and do not renormalize. Shape checks guard row_ref/count/index mismatches so          |
//   a corrupted retained plan fails here instead of reading past the borrowed arrays.                                    |
//                                                                                                                        |
// memory                                                                                                                 |
//   Forward results, row refs, sample indexes, and kernel side arrays are borrowed from ResolvedSimulationPlan.          |
//   SpectralEvaluationCache owns only the per-run exact-wavelength irradiance hash map keyed by f64 bits; it is          |
//   used to avoid repeated solar interpolation when radiance and irradiance kernels revisit the same support.            |
// ---------------------------------------------------------------------------------------------------------------------- |

pub const ForwardIntegratedSample = spectral_forward.ForwardIntegratedSample;
pub const ForwardCacheMiss = Plan.ForwardCacheMiss;
pub const ForwardPrefetchRequest = spectral_forward.ForwardPrefetchRequest;
pub const preferredForwardWorkerCount = spectral_forward.preferredForwardWorkerCount;

pub const SpectralEvaluationCache = cache_module.SpectralEvaluationCache;

// IrradianceLookupRequest -----------------------------------------------------------------------------------------------|
// Borrowed inputs for exact-wavelength solar irradiance lookup and per-run caching.                                      |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 32 B (0.031 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] scene     : *const Scene                                                                                      |
// [ 8..15] prepared  : *const OpticsPreparation.PreparedOpticalState                                                     |
// [16..23] safe_span : f64                                                                                               |
// [24..31] cache     : *SpectralEvaluationCache                                                                          |
//                                                                                                                        |
// referenced storage: scene, prepared, and cache are borrowed; the cache owns its retained hash map storage.             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 32 B (0.031 KiB); no out-of-line storage                                                     |
const IrradianceLookupRequest = struct {
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    safe_span: f64,
    cache: *SpectralEvaluationCache,
};

fn irradianceAtWavelength(
    request: *const IrradianceLookupRequest,
    wavelength_nm: f64,
) f64 {
    // irradianceAtWavelength --------------------------------------------------------------------------------------------|
    // Resolve solar irradiance at one wavelength through the compatibility helper. prepared and safe_span are            |
    // kept in the signature so this call site can absorb future prepared-spectrum routes without changing                |
    // the integration loop contract.                                                                                     |
    // -------------------------------------------------------------------------------------------------------------------|

    _ = request.prepared;
    _ = request.safe_span;
    return solar_compat.irradianceAtWavelength(request.scene, wavelength_nm);
}

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
    prepared: *const OpticsPreparation.PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
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
    //   irradiance. The difference is only the source of each high-resolution sample: solar support data                 |
    //   instead of LABOS transport.                                                                                      |
    // ------------------------------------------------------------------------------------------------------------------ |

    const lookup_request = IrradianceLookupRequest{
        .scene = scene,
        .prepared = prepared,
        .safe_span = safe_span,
        .cache = cache,
    };
    if (!integration.enabled()) {
        return cachedIrradianceAtWavelength(&lookup_request, nominal_wavelength_nm);
    }

    var irradiance_sum: f64 = 0.0;
    const samples = integration.samples(kernel_storage);
    for (samples.offsets_nm, samples.weights) |offset_nm, weight| {
        irradiance_sum += weight * try cachedIrradianceAtWavelength(
            &lookup_request,
            nominal_wavelength_nm + offset_nm,
        );
    }
    return irradiance_sum;
}

pub fn prefetchForwardSamples(
    allocator: Allocator,
    request: *const ForwardPrefetchRequest,
) Error!void {
    // prefetchForwardSamples ------------------------------------------------------------------------------------------- |
    // Compute every unique high-resolution forward miss into a dense result array before nominal-row                     |
    // integration starts.                                                                                                |
    //                                                                                                                    |
    // output contract                                                                                                    |
    //   results[index] corresponds to misses[index]. buildForwardMissPlan stores only these dense indexes in             |
    //   each nominal row, so later integration does not touch the miss hash map.                                         |
    // ------------------------------------------------------------------------------------------------------------------ |

    if (request.misses.len == 0) return;
    if (request.results.len != request.misses.len) return error.ShapeMismatch;

    try spectral_forward.prefetchForwardSamples(
        allocator,
        request,
    );
}

fn cachedIrradianceAtWavelength(
    request: *const IrradianceLookupRequest,
    wavelength_nm: f64,
) Error!f64 {
    // cachedIrradianceAtWavelength ------------------------------------------------------------------------------------- |
    // Return solar irradiance at one exact wavelength, caching by the f64 bit pattern.                                   |
    //                                                                                                                    |
    // route                                                                                                              |
    //   DISAMAR high-resolution grid with covering operational solar table -> in-bounds operational interpolation        |
    //   otherwise                                           -> solar_irradiance.zig compatibility source order           |
    // ------------------------------------------------------------------------------------------------------------------ |

    const key = SpectralEvaluationCache.keyFor(wavelength_nm);
    if (request.cache.irradiance.get(key)) |cached| return cached;

    const response = request.scene.observation_model.resolvedChannelControls(.irradiance).response;
    const operational_band_support = request.scene.observation_model.primaryOperationalBandSupport();
    const value = choose_value: {
        break :choose_value if (response.integration_mode == .disamar_hr_grid and
            operational_band_support.operational_solar_spectrum.enabled())
            operational_band_support.operational_solar_spectrum.interpolateIrradianceWithinBounds(wavelength_nm) orelse
                irradianceAtWavelength(request, wavelength_nm)
        else
            irradianceAtWavelength(request, wavelength_nm);
    };
    try request.cache.irradiance.put(key, value);
    return value;
}
