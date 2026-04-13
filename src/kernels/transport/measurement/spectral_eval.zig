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
//!   Caches at a fixed wavelength quantization so the measurement reduction
//!   can reuse forward and irradiance results without changing solver physics.
//!
//! Invariants:
//!   Cache keys must be stable for a given wavelength quantization and the
//!   bundled O2A irradiance reference remains band-limited.
//!
//! Validation:
//!   Measurement-space summary and product tests.

const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const OpticsPreparation = @import("../../optics/preparation.zig");
const common = @import("../common.zig");
const ForwardInput = @import("forward_input.zig");
const Types = @import("types.zig");
const Workspace = @import("workspace.zig");

const Allocator = std.mem.Allocator;
const OperationalInstrumentIntegration = @import("../../../o2a/providers/instrument.zig").IntegrationKernel;
const Error = Workspace.Error;

// DECISION:
//   Quantize spectral cache keys at the sub-picometer scale so repeated
//   transport samples reuse the same cache entry without altering physics.
const spectral_cache_quantization_nm = 1.0e-6;
// DECISION:
//   Keep the bundled O2A solar reference as a short reference band for the
//   default solar spectrum fallback.
const bundled_o2a_solar_wavelengths_nm = [_]f64{ 755.0, 758.0, 760.01, 761.99, 764.99, 770.0, 776.0 };
const bundled_o2a_solar_irradiance = [_]f64{
    4.805854615e14,
    4.879049767e14,
    4.858697784e14,
    4.615924814e14,
    4.832478218e14,
    4.60914094e14,
    4.759839792e14,
};

pub const ForwardIntegratedSample = struct {
    radiance: f64,
    jacobian: f64 = 0.0,
};

pub const ForwardCacheMiss = struct {
    key: i64,
    wavelength_nm: f64,
};

const ForwardSampleScratch = struct {
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,

    fn init(
        allocator: Allocator,
        scene: *const Scene,
        route: common.Route,
        prepared: *const OpticsPreparation.PreparedOpticalState,
    ) !ForwardSampleScratch {
        const layer_count = Workspace.resolvedTransportLayerCount(route, prepared);
        const pseudo_spherical_sample_count = Workspace.resolvedPseudoSphericalSampleCount(scene, route, prepared);
        return .{
            .layer_inputs = try allocator.alloc(common.LayerInput, layer_count),
            .pseudo_spherical_layers = try allocator.alloc(common.LayerInput, pseudo_spherical_sample_count),
            .source_interfaces = try allocator.alloc(common.SourceInterfaceInput, layer_count + 1),
            .rtm_quadrature_levels = try allocator.alloc(common.RtmQuadratureLevel, layer_count + 1),
            .pseudo_spherical_samples = try allocator.alloc(common.PseudoSphericalSample, pseudo_spherical_sample_count),
            .pseudo_spherical_level_starts = try allocator.alloc(usize, layer_count + 1),
            .pseudo_spherical_level_altitudes = try allocator.alloc(f64, layer_count + 1),
        };
    }

    fn deinit(self: *ForwardSampleScratch, allocator: Allocator) void {
        allocator.free(self.layer_inputs);
        allocator.free(self.pseudo_spherical_layers);
        allocator.free(self.source_interfaces);
        allocator.free(self.rtm_quadrature_levels);
        allocator.free(self.pseudo_spherical_samples);
        allocator.free(self.pseudo_spherical_level_starts);
        allocator.free(self.pseudo_spherical_level_altitudes);
        self.* = undefined;
    }
};

const ForwardPrefetchErrorState = struct {
    mutex: std.Thread.Mutex = .{},
    err: ?Error = null,

    fn store(self: *ForwardPrefetchErrorState, err: Error) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.err == null) self.err = err;
    }
};

const ForwardPrefetchWorker = struct {
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    safe_span: f64,
    misses: []const ForwardCacheMiss,
    results: []ForwardIntegratedSample,
    error_state: *ForwardPrefetchErrorState,
};

/// Quantized spectral cache for repeated forward and irradiance samples.
pub const SpectralEvaluationCache = struct {
    allocator: Allocator,
    forward: std.AutoHashMap(i64, ForwardIntegratedSample),
    irradiance: std.AutoHashMap(i64, f64),

    /// Purpose:
    ///   Initialize the cache buckets for one measurement-space sweep.
    pub fn init(allocator: Allocator) SpectralEvaluationCache {
        return .{
            .allocator = allocator,
            .forward = std.AutoHashMap(i64, ForwardIntegratedSample).init(allocator),
            .irradiance = std.AutoHashMap(i64, f64).init(allocator),
        };
    }

    /// Purpose:
    ///   Release both spectral cache maps.
    pub fn deinit(self: *SpectralEvaluationCache) void {
        self.forward.deinit();
        self.irradiance.deinit();
        self.* = undefined;
    }

    /// Purpose:
    ///   Quantize a wavelength into the cache key space.
    pub fn keyFor(wavelength_nm: f64) i64 {
        return @as(i64, @intFromFloat(std.math.round(wavelength_nm / spectral_cache_quantization_nm)));
    }
};

/// Purpose:
///   Convert a transport forward result into radiance at one wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
pub fn radianceFromForward(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: common.ForwardResult,
) f64 {
    const solar_irradiance = irradianceAtWavelength(scene, prepared, wavelength_nm, safe_span);
    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
    const surface_gain = providers.surface.brdfFactor(.{
        .scene = scene,
        .prepared = prepared,
        .wavelength_nm = wavelength_nm,
        .safe_span = safe_span,
        .phase = phase,
        .forward = forward,
    });
    return solar_irradiance * solar_cosine * forward.toa_reflectance_factor * surface_gain / std.math.pi;
}

fn irradianceAtWavelength(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
) f64 {
    const operational_band_support = scene.observation_model.primaryOperationalBandSupport();
    const source_irradiance = if (operational_band_support.operational_solar_spectrum.enabled())
        operational_band_support.operational_solar_spectrum.interpolateIrradiance(wavelength_nm)
    else if (scene.observation_model.solar_spectrum_source.kind() == .bundle_default)
        bundledSolarIrradiance(wavelength_nm) orelse defaultSolarContinuumIrradiance(wavelength_nm)
    else
        defaultSolarContinuumIrradiance(wavelength_nm);
    _ = prepared;
    _ = safe_span;
    return @max(source_irradiance, 1e-6);
}

fn bundledSolarIrradiance(wavelength_nm: f64) ?f64 {
    if (wavelength_nm < bundled_o2a_solar_wavelengths_nm[0] or wavelength_nm > bundled_o2a_solar_wavelengths_nm[bundled_o2a_solar_wavelengths_nm.len - 1]) {
        // PARITY:
        //   Preserve the bundled O2A band shape so the default spectrum matches
        //   the vendor reference range.
        return null;
    }

    if (wavelength_nm <= bundled_o2a_solar_wavelengths_nm[0]) return bundled_o2a_solar_irradiance[0];
    for (
        bundled_o2a_solar_wavelengths_nm[0 .. bundled_o2a_solar_wavelengths_nm.len - 1],
        bundled_o2a_solar_wavelengths_nm[1..],
        bundled_o2a_solar_irradiance[0 .. bundled_o2a_solar_irradiance.len - 1],
        bundled_o2a_solar_irradiance[1..],
    ) |left_nm, right_nm, left_irradiance, right_irradiance| {
        if (wavelength_nm <= right_nm) {
            const span = right_nm - left_nm;
            if (span == 0.0) return right_irradiance;
            const blend = (wavelength_nm - left_nm) / span;
            return left_irradiance + blend * (right_irradiance - left_irradiance);
        }
    }
    return bundled_o2a_solar_irradiance[bundled_o2a_solar_irradiance.len - 1];
}

fn defaultSolarContinuumIrradiance(wavelength_nm: f64) f64 {
    const reference_wavelength_nm = 760.0;
    const reference_irradiance = 4.87401e14;
    return reference_irradiance *
        planckContinuumShape(wavelength_nm, 5778.0) /
        planckContinuumShape(reference_wavelength_nm, 5778.0);
}

fn planckContinuumShape(wavelength_nm: f64, temperature_k: f64) f64 {
    const h = 6.62607015e-34;
    const c = 2.99792458e8;
    const k = 1.380649e-23;
    const wavelength_m = @max(wavelength_nm, 1.0) * 1.0e-9;
    const exponent = h * c / (wavelength_m * k * @max(temperature_k, 1.0));
    const denominator = @max(std.math.expm1(exponent), 1.0e-12);
    return (2.0 * h * c * c) /
        std.math.pow(f64, wavelength_m, 5.0) /
        denominator;
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

fn computeForwardSampleAtWavelength(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    providers: Types.ProviderBindings,
    scratch: *ForwardSampleScratch,
) Error!ForwardIntegratedSample {
    const input = try ForwardInput.configuredForwardInput(
        scene,
        route,
        prepared,
        wavelength_nm,
        scratch.layer_inputs,
        scratch.pseudo_spherical_layers,
        scratch.source_interfaces,
        scratch.rtm_quadrature_levels,
        scratch.pseudo_spherical_samples,
        scratch.pseudo_spherical_level_starts,
        scratch.pseudo_spherical_level_altitudes,
    );
    var effective_route = route;
    effective_route.rtm_controls = input.rtm_controls;
    const forward = try providers.transport.executePrepared(allocator, effective_route, input);
    return .{
        .radiance = radianceFromForward(scene, prepared, providers, wavelength_nm, safe_span, 0.0, forward),
        .jacobian = if (forward.jacobian_column) |value| value else 0.0,
    };
}

fn prefetchForwardWorkerMain(worker: *ForwardPrefetchWorker) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const worker_allocator = gpa.allocator();
    var scratch = ForwardSampleScratch.init(
        worker_allocator,
        worker.scene,
        worker.route,
        worker.prepared,
    ) catch |err| {
        worker.error_state.store(err);
        return;
    };
    defer scratch.deinit(worker_allocator);

    for (worker.misses, worker.results) |miss, *result| {
        result.* = computeForwardSampleAtWavelength(
            worker_allocator,
            worker.scene,
            worker.route,
            worker.prepared,
            miss.wavelength_nm,
            worker.safe_span,
            worker.providers,
            &scratch,
        ) catch |err| {
            worker.error_state.store(err);
            return;
        };
    }
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

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const worker_count = @max(@min(cpu_count, misses.len), 1);
    const results = try allocator.alloc(ForwardIntegratedSample, misses.len);
    defer allocator.free(results);

    if (worker_count == 1) {
        var scratch = try ForwardSampleScratch.init(allocator, scene, route, prepared);
        defer scratch.deinit(allocator);
        for (misses, results) |miss, *result| {
            result.* = try computeForwardSampleAtWavelength(
                allocator,
                scene,
                route,
                prepared,
                miss.wavelength_nm,
                safe_span,
                providers,
                &scratch,
            );
        }
    } else {
        var error_state = ForwardPrefetchErrorState{};
        const workers = try allocator.alloc(ForwardPrefetchWorker, worker_count);
        defer allocator.free(workers);
        const threads = try allocator.alloc(std.Thread, worker_count - 1);
        defer allocator.free(threads);

        const base_count = misses.len / worker_count;
        const remainder = misses.len % worker_count;
        var start_index: usize = 0;
        var started_thread_count: usize = 0;
        for (0..worker_count) |worker_index| {
            const batch_count = base_count + @as(usize, if (worker_index < remainder) 1 else 0);
            const end_index = start_index + batch_count;
            workers[worker_index] = .{
                .scene = scene,
                .route = route,
                .prepared = prepared,
                .providers = providers,
                .safe_span = safe_span,
                .misses = misses[start_index..end_index],
                .results = results[start_index..end_index],
                .error_state = &error_state,
            };
            if (worker_index + 1 < worker_count) {
                threads[started_thread_count] = std.Thread.spawn(
                    .{},
                    prefetchForwardWorkerMain,
                    .{&workers[worker_index]},
                ) catch {
                    prefetchForwardWorkerMain(&workers[worker_index]);
                    start_index = end_index;
                    continue;
                };
                started_thread_count += 1;
            } else {
                prefetchForwardWorkerMain(&workers[worker_index]);
            }
            start_index = end_index;
        }
        for (threads[0..started_thread_count]) |thread| thread.join();
        if (error_state.err) |err| return err;
    }

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

    // GOTCHA:
    //   Cache keys are quantized, so nearby samples share the same storage
    //   entry to match the measurement-space reuse contract.
    var scratch = ForwardSampleScratch{
        .layer_inputs = layer_inputs,
        .pseudo_spherical_layers = pseudo_spherical_layers,
        .source_interfaces = source_interfaces,
        .rtm_quadrature_levels = rtm_quadrature_levels,
        .pseudo_spherical_samples = pseudo_spherical_samples,
        .pseudo_spherical_level_starts = pseudo_spherical_level_starts,
        .pseudo_spherical_level_altitudes = pseudo_spherical_level_altitudes,
    };
    const sample = try computeForwardSampleAtWavelength(
        allocator,
        scene,
        route,
        prepared,
        wavelength_nm,
        safe_span,
        providers,
        &scratch,
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

    const value = irradianceAtWavelength(scene, prepared, wavelength_nm, safe_span);
    try cache.irradiance.put(key, value);
    return value;
}
