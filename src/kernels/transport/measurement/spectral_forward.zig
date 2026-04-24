//! Purpose:
//!   Compute forward radiance samples at exact wavelengths and prefetch unique
//!   cache misses for measurement evaluation.
//!
//! Physics:
//!   Couples prepared transport output with solar irradiance and surface BRDF
//!   gain, then materializes exact-wavelength forward samples for cached reuse.
//!
//! Vendor:
//!   `measurement spectral evaluation`
//!
//! Design:
//!   Keep forward-sample execution and miss-prefetch orchestration separate
//!   from cache ownership and nominal-wavelength integration.
//!
//! Invariants:
//!   Prefetch solves each unique miss exactly once and preserves deterministic
//!   cache insertion order on the main thread.
//!
//! Validation:
//!   Measurement summary/product tests and the fast O2 A transport lanes.

const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const OpticsPreparation = @import("../../optics/preparation.zig");
const common = @import("../common.zig");
const ForwardInput = @import("forward_input.zig");
const Types = @import("types.zig");
const Workspace = @import("workspace.zig");
const solar_compat = @import("../../../compat/transport/solar_irradiance.zig");

const Allocator = std.mem.Allocator;
const Error = Workspace.Error;
const min_parallel_forward_miss_count: usize = 32;

pub const ForwardIntegratedSample = struct {
    radiance: f64,
    jacobian: f64 = 0.0,
};

pub const ForwardCacheMiss = struct {
    key: u64,
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

pub fn radianceFromForward(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: common.ForwardResult,
) f64 {
    const solar_irradiance = solar_compat.irradianceAtWavelength(scene, wavelength_nm);
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

pub fn computeForwardSampleAtWavelength(
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
) Error!ForwardIntegratedSample {
    const input = try ForwardInput.configuredForwardInput(
        scene,
        route,
        prepared,
        wavelength_nm,
        layer_inputs,
        pseudo_spherical_layers,
        source_interfaces,
        rtm_quadrature_levels,
        pseudo_spherical_samples,
        pseudo_spherical_level_starts,
        pseudo_spherical_level_altitudes,
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
            scratch.layer_inputs,
            scratch.pseudo_spherical_layers,
            scratch.source_interfaces,
            scratch.rtm_quadrature_levels,
            scratch.pseudo_spherical_samples,
            scratch.pseudo_spherical_level_starts,
            scratch.pseudo_spherical_level_altitudes,
        ) catch |err| {
            worker.error_state.store(err);
            return;
        };
    }
}

pub fn prefetchForwardSamples(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    safe_span: f64,
    misses: []const ForwardCacheMiss,
    results: []ForwardIntegratedSample,
) Error!void {
    if (misses.len == 0) return;

    const worker_count = preferredForwardWorkerCount(misses.len);

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
                scratch.layer_inputs,
                scratch.pseudo_spherical_layers,
                scratch.source_interfaces,
                scratch.rtm_quadrature_levels,
                scratch.pseudo_spherical_samples,
                scratch.pseudo_spherical_level_starts,
                scratch.pseudo_spherical_level_altitudes,
            );
        }
        return;
    }

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

fn preferredForwardWorkerCount(miss_count: usize) usize {
    if (miss_count < min_parallel_forward_miss_count) return 1;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return @max(@min(cpu_count, miss_count), 1);
}

test "small forward miss batches stay single-threaded" {
    try std.testing.expectEqual(@as(usize, 1), preferredForwardWorkerCount(min_parallel_forward_miss_count - 1));
}
