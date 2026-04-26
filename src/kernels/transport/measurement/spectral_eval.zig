//! Purpose:
//!   Evaluate transport output at instrument wavelengths and cache the
//!   spectral samples used by measurement-space materialization.
//!
//! Physics:
//!   Combines transport forward results with solar irradiance and instrument
//!   integration kernels, then reuses quantized wavelength caches for repeated
//!   samples.
//!
//! Vendor:
//!   `measurement spectral evaluation` stage
//!
//! Design:
//!   Caches by exact wavelength bits so the measurement reduction can reuse
//!   repeated forward and irradiance samples without collapsing adjacent
//!   adaptive high-resolution wavelengths.
//!
//! Invariants:
//!   Cache keys must distinguish adjacent adaptive O2A samples, and the
//!   bundled O2A irradiance reference remains band-limited.
//!
//! Validation:
//!   Measurement-space summary and product tests.

const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const OpticsPreparation = @import("../../optics/preparation.zig");
const common = @import("../common.zig");
const cache_module = @import("cache.zig");
const spectral_forward = @import("spectral_forward.zig");
const Types = @import("types.zig");
const Workspace = @import("workspace.zig");
const solar_compat = @import("../../../compat/transport/solar_irradiance.zig");

const Allocator = std.mem.Allocator;
const OperationalInstrumentIntegration = @import("../../../o2a/providers/instrument.zig").IntegrationKernel;
const Error = Workspace.Error;

pub const ForwardIntegratedSample = spectral_forward.ForwardIntegratedSample;
pub const ForwardCacheMiss = spectral_forward.ForwardCacheMiss;

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

/// Purpose:
///   Integrate the forward model at one nominal instrument wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
pub fn integrateForwardAtNominal(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    providers: Types.ProviderBindings,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    cache: *SpectralEvaluationCache,
    integration: *const OperationalInstrumentIntegration,
) Error!ForwardIntegratedSample {
    // DECISION:
    //   When the instrument has no internal integration kernel, fall back to
    //   the quantized cached forward sample at the nominal wavelength.
    if (!integration.enabled) {
        return cachedForwardAtWavelength(
            allocator,
            scene,
            route,
            prepared,
            nominal_wavelength_nm,
            safe_span,
            providers,
            layer_inputs,
            pseudo_spherical_layers,
            source_interfaces,
            rtm_quadrature_levels,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            cache,
        );
    }

    var radiance_sum: f64 = 0.0;
    var jacobian_sum: f64 = 0.0;
    for (0..integration.sample_count) |index| {
        const offset_nm = integration.offsets_nm[index];
        const weight = integration.weights[index];
        const wavelength_nm = nominal_wavelength_nm + offset_nm;
        const sample = try cachedForwardAtWavelength(
            allocator,
            scene,
            route,
            prepared,
            wavelength_nm,
            safe_span,
            providers,
            layer_inputs,
            pseudo_spherical_layers,
            source_interfaces,
            rtm_quadrature_levels,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            cache,
        );
        radiance_sum += weight * sample.radiance;
        jacobian_sum += weight * sample.jacobian;
    }

    return .{
        .radiance = radiance_sum,
        .jacobian = jacobian_sum,
    };
}

/// Purpose:
///   Integrate the solar irradiance at one nominal instrument wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
pub fn integrateIrradianceAtNominal(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    cache: *SpectralEvaluationCache,
    integration: *const OperationalInstrumentIntegration,
) Error!f64 {
    // DECISION:
    //   Integrated instruments sample irradiance through the same kernel used
    //   for radiance so the instrument response stays aligned.
    if (!integration.enabled) {
        return cachedIrradianceAtWavelength(scene, prepared, nominal_wavelength_nm, safe_span, cache);
    }

    var irradiance_sum: f64 = 0.0;
    for (0..integration.sample_count) |index| {
        const offset_nm = integration.offsets_nm[index];
        const weight = integration.weights[index];
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

/// Purpose:
///   Prefill the forward cache by solving each unique quantized wavelength miss
///   exactly once, optionally in parallel.
///
/// Physics:
///   Keeps the cache-key contract exact by solving the first encountered sample
///   wavelength for each quantized miss and then inserting the finished samples
///   back into the main-thread cache in deterministic order.
pub fn prefetchForwardSamples(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    safe_span: f64,
    misses: []const ForwardCacheMiss,
    cache: *SpectralEvaluationCache,
) Error!void {
    if (misses.len == 0) return;

    const results = try allocator.alloc(ForwardIntegratedSample, misses.len);
    defer allocator.free(results);

    try spectral_forward.prefetchForwardSamples(
        allocator,
        scene,
        route,
        prepared,
        providers,
        safe_span,
        misses,
        results,
    );
    for (misses, results) |miss, result| {
        try cache.forward.put(miss.key, result);
    }
}

/// Purpose:
///   Cache and return a forward sample at one wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
pub fn cachedForwardAtWavelength(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    providers: Types.ProviderBindings,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
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
        providers,
        layer_inputs,
        pseudo_spherical_layers,
        source_interfaces,
        rtm_quadrature_levels,
        pseudo_spherical_samples,
        pseudo_spherical_level_starts,
        pseudo_spherical_level_altitudes,
    );
    try cache.forward.put(key, sample);
    return sample;
}

/// Purpose:
///   Cache and return a solar irradiance sample at one wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
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

test "spectral cache key distinguishes adjacent adaptive samples" {
    const first = 759.637013770239;
    const second = 759.6370143839599;
    try std.testing.expect(SpectralEvaluationCache.keyFor(first) != SpectralEvaluationCache.keyFor(second));
}
