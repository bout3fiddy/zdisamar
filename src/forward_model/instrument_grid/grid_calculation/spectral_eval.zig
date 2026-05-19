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
//   when: once per nominal radiance wavelength, with one or more integration samples
//   work: accumulates weighted cached forward samples into radiance and Jacobian totals
//   data: integration offsets, weights, spectral forward cache, jacobian vector accumulator
//   follow: cachedForwardAtWavelength and the active instrument integration payload
pub fn integrateForwardAtNominal(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    implementations: Types.Implementations,
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    cache: *SpectralEvaluationCache,
    integration: *const Plan.IntegrationKernelRef,
    kernel_storage: Plan.IntegrationKernelStorage,
) Error!ForwardIntegratedSample {
    // DECISION:
    //   When the instrument has no internal integration routine, fall back to
    //   the quantized cached forward sample at the nominal wavelength.
    if (!integration.enabled()) {
        return cachedForwardAtWavelength(
            allocator,
            scene,
            route,
            prepared,
            nominal_wavelength_nm,
            safe_span,
            implementations,
            layer_inputs,
            source_interfaces,
            rtm_quadrature_levels,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            cache,
        );
    }

    var radiance_sum: f64 = 0.0;
    var jacobian_sum = jacobian.zero();
    const samples = integration.samples(kernel_storage);
    for (samples.offsets_nm, samples.weights) |offset_nm, weight| {
        const wavelength_nm = nominal_wavelength_nm + offset_nm;
        const sample = try cachedForwardAtWavelength(
            allocator,
            scene,
            route,
            prepared,
            wavelength_nm,
            safe_span,
            implementations,
            layer_inputs,
            source_interfaces,
            rtm_quadrature_levels,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            cache,
        );
        radiance_sum += weight * sample.radiance;
        jacobian.addScaled(&jacobian_sum, sample.jacobian, weight);
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
//   work: reserves cache capacity, computes all forward misses, and inserts dense results by key
//   data: forward miss array, profile spectroscopy caches, temporary result array, spectral cache map
//   follow: spectral_forward.prefetchForwardSamples and cache.forward.put
pub fn prefetchForwardSamples(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    safe_span: f64,
    misses: []const ForwardCacheMiss,
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache,
    cache: *SpectralEvaluationCache,
    thread_pool: ?*std.Thread.Pool,
) Error!void {
    if (misses.len == 0) return;

    try cache.reserveForward(misses.len);

    const results = try allocator.alloc(ForwardIntegratedSample, misses.len);
    defer allocator.free(results);

    try spectral_forward.prefetchForwardSamples(
        allocator,
        scene,
        route,
        prepared,
        implementations,
        safe_span,
        misses,
        profile_spectroscopy_caches,
        results,
        thread_pool,
    );
    for (misses, results) |miss, result| {
        try cache.forward.put(miss.key, result);
    }
}

// hot path:
//   when: on each high-resolution forward cache miss
//   work: computes a wavelength-specific forward sample when the quantized key is absent
//   data: layer/source/quadrature scratch arrays, pseudo-spherical arrays, spectral cache
//   follow: spectral_forward.computeForwardSampleAtWavelength and cache key reuse
pub fn cachedForwardAtWavelength(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    implementations: Types.Implementations,
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    cache: *SpectralEvaluationCache,
) Error!ForwardIntegratedSample {
    const key = SpectralEvaluationCache.keyFor(wavelength_nm);
    if (cache.forward.get(key)) |cached| return cached;

    const sample = try spectral_forward.computeForwardSampleAtWavelength(
        allocator,
        scene,
        route,
        prepared,
        wavelength_nm,
        safe_span,
        implementations,
        layer_inputs,
        source_interfaces,
        rtm_quadrature_levels,
        pseudo_spherical_samples,
        pseudo_spherical_level_starts,
        pseudo_spherical_level_altitudes,
    );
    try cache.forward.put(key, sample);
    return sample;
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
