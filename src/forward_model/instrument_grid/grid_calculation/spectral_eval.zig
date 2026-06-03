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

pub const ForwardIntegratedSample = spectral_forward.ForwardIntegratedSample;
pub const ForwardCacheMiss = Plan.ForwardCacheMiss;
pub const preferredForwardWorkerCount = spectral_forward.preferredForwardWorkerCount;

pub const SpectralEvaluationCache = cache_module.SpectralEvaluationCache;

fn irradianceAtWavelength(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
) f64 {
    _ = prepared;
    _ = safe_span;
    return solar_compat.irradianceAtWavelength(scene, wavelength_nm);
}

// hot path:
//   when: once per nominal radiance wavelength after all forward misses are prefetched
//   work: accumulates weighted dense forward results into radiance and Jacobian totals
//   data: row-local result indexes, weights, dense forward result buffer, Jacobian accumulator
//   follow: buildForwardMissPlan and spectral_forward.prefetchForwardSamples
//   math: L_i = sum_j w_ij L(lambda_i + delta_ij); dL_i/dx = sum_j w_ij dL(lambda_i + delta_ij)/dx
pub fn integratePrefetchedForwardAtNominal(
    rtm_config: common.SolveConfig,
    results: []const ForwardIntegratedSample,
    row_ref: Plan.ForwardSampleIndexRef,
    sample_indices: []const u32,
    integration: *const Plan.IntegrationKernelRef,
    kernel_storage: Plan.IntegrationKernelStorage,
) Error!ForwardIntegratedSample {
    const start: usize = @intCast(row_ref.start);
    const count = integration.activeSampleCount();
    if (count == 0 or start > sample_indices.len or count > sample_indices.len - start) {
        return error.ShapeMismatch;
    }
    const indices = sample_indices[start .. start + count];

    // Hot path:
    //   Wavelength planning already deduplicated forward misses and recorded
    //   dense result indexes. The radiance loop reads results directly instead
    //   of hashing each integration wavelength back through the forward cache.
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

// hot path:
//   when: once per nominal irradiance wavelength, with one or more integration samples
//   work: accumulates weighted cached solar irradiance samples
//   data: integration offsets, weights, irradiance cache, solar support tables
//   follow: cachedIrradianceAtWavelength and operational solar interpolation
//   math: E0_i = sum_j w_ij E0(lambda_i + delta_ij), or E0(lambda_i) when no integration kernel is active
pub fn integrateIrradianceAtNominal(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    cache: *SpectralEvaluationCache,
    integration: *const Plan.IntegrationKernelRef,
    kernel_storage: Plan.IntegrationKernelStorage,
) Error!f64 {
    // DECISION:
    //   Integrated instruments sample irradiance through the same routine used
    //   for radiance so the instrument response stays aligned.
    if (!integration.enabled()) {
        return cachedIrradianceAtWavelength(scene, prepared, nominal_wavelength_nm, safe_span, cache);
    }

    var irradiance_sum: f64 = 0.0;
    const samples = integration.samples(kernel_storage);
    for (samples.offsets_nm, samples.weights) |offset_nm, weight| {
        irradiance_sum += weight * try cachedIrradianceAtWavelength(
            scene,
            prepared,
            nominal_wavelength_nm + offset_nm,
            safe_span,
            cache,
        );
    }
    return irradiance_sum;
}

// hot path:
//   when: once per simulation plan before nominal wavelength integration
//   work: computes all forward misses into dense result slots
//   data: forward miss array, profile spectroscopy caches, temporary result array
//   follow: spectral_forward.prefetchForwardSamples and direct-index radiance integration
//   math: result_m = F(lambda_m), where each unique lambda_m is later reused by one or more weighted nominal rows
pub fn prefetchForwardSamples(
    allocator: Allocator,
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    misses: []const ForwardCacheMiss,
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache,
    results: []ForwardIntegratedSample,
    thread_pool: ?*std.Thread.Pool,
) Error!void {
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
    );
}

// hot path:
//   when: on each high-resolution irradiance cache miss
//   work: resolves solar irradiance from operational support or reference interpolation
//   data: quantized wavelength key, irradiance cache, solar spectrum support
//   follow: operational_solar_spectrum.interpolateIrradianceWithinBounds and cache insertion
fn cachedIrradianceAtWavelength(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    cache: *SpectralEvaluationCache,
) Error!f64 {
    const key = SpectralEvaluationCache.keyFor(wavelength_nm);
    if (cache.irradiance.get(key)) |cached| return cached;

    const response = scene.observation_model.resolvedChannelControls(.irradiance).response;
    const operational_band_support = scene.observation_model.primaryOperationalBandSupport();
    const value = if (response.integration_mode == .disamar_hr_grid and
        operational_band_support.operational_solar_spectrum.enabled())
        operational_band_support.operational_solar_spectrum.interpolateIrradianceWithinBounds(wavelength_nm) orelse
            irradianceAtWavelength(scene, prepared, wavelength_nm, safe_span)
    else
        irradianceAtWavelength(scene, prepared, wavelength_nm, safe_span);
    try cache.irradiance.put(key, value);
    return value;
}
