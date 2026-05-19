const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const CarrierEval = @import("../../optical_properties/state_build/carrier_eval.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const common = @import("../../radiative_transfer/root.zig");
const jacobian = @import("../../jacobian/root.zig");
const labos = @import("../../radiative_transfer/labos/root.zig");
const Trace = @import("../../performance_trace.zig");
const ForwardInput = @import("forward_input.zig");
const Types = @import("types.zig");
const Storage = @import("storage.zig");
const Plan = @import("wavelength_plan.zig");
const solar_compat = @import("../../../input/reference_data/solar_irradiance.zig");
const work_partition = @import("../../work_partition.zig");

const Allocator = std.mem.Allocator;
const Error = Storage.Error;
// PUB FOR TEST: re-exported via measurement/internal.zig.
pub const min_parallel_forward_miss_count: usize = 32;

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: radiance=8 B, jacobian=24 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   inline arrays: jacobian:[3]f64=24 B
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count
pub const ForwardIntegratedSample = struct {
    radiance: f64,
    jacobian: jacobian.Vector = jacobian.zero(),
};

pub const ForwardCacheMiss = Plan.ForwardCacheMiss;
const forward_prefetch_chunk_size: usize = 8;
const forward_prefetch_pooled_chunk_size: usize = 16;

// hot path:
//   when: allocated once per forward prefetch worker
//   work: owns reusable layer, source, quadrature, carrier, pseudo-spherical, and LABOS buffers
//   data: per-worker scratch slices and labos.Workspace
//   follow: reuse inside prefetchForwardWorkerMain across forward misses
// layout(64-bit):
//   size: 3296 B, align: 8 B
//   field storage: 3296 B across 9 fields; largest: labos_workspace=3168 B, layer_inputs=16 B, source_interfaces=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: layer_inputs, source_interfaces, rtm_quadrature_levels, pseudo_spherical_samples, pseudo_spherical_level_starts, +3 more carry references/descriptors; referenced storage is not included in size
//   cache span: 52 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 3296 B (3.219 KiB); total also includes referenced storage above
const ForwardSampleScratch = struct {
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    support_carrier_valid: []bool,
    support_carriers: []CarrierEval.SharedOpticalCarrier,
    labos_workspace: labos.Workspace,

    fn init(
        allocator: Allocator,
        scene: *const Scene,
        route: common.Route,
        prepared: *const OpticsPreparation.PreparedOpticalState,
    ) !ForwardSampleScratch {
        const layer_count = Storage.resolvedTransportLayerCount(route, prepared);
        const pseudo_spherical_sample_count = Storage.resolvedPseudoSphericalSampleCount(scene, route, prepared);
        const support_cache_count = if (prepared.sublayers) |sublayers| sublayers.len else layer_count;

        const layer_inputs = try allocator.alloc(common.LayerInput, layer_count);
        errdefer allocator.free(layer_inputs);
        const source_interfaces = try allocator.alloc(common.SourceInterfaceInput, layer_count + 1);
        errdefer allocator.free(source_interfaces);
        const rtm_quadrature_levels = try allocator.alloc(common.RtmQuadratureLevel, layer_count + 1);
        errdefer allocator.free(rtm_quadrature_levels);
        const pseudo_spherical_samples = try allocator.alloc(common.PseudoSphericalSample, pseudo_spherical_sample_count);
        errdefer allocator.free(pseudo_spherical_samples);
        const pseudo_spherical_level_starts = try allocator.alloc(usize, layer_count + 1);
        errdefer allocator.free(pseudo_spherical_level_starts);
        const pseudo_spherical_level_altitudes = try allocator.alloc(f64, layer_count + 1);
        errdefer allocator.free(pseudo_spherical_level_altitudes);
        const support_carrier_valid = try allocator.alloc(bool, support_cache_count);
        errdefer allocator.free(support_carrier_valid);
        const support_carriers = try allocator.alloc(CarrierEval.SharedOpticalCarrier, support_cache_count);
        errdefer allocator.free(support_carriers);

        return .{
            .layer_inputs = layer_inputs,
            .source_interfaces = source_interfaces,
            .rtm_quadrature_levels = rtm_quadrature_levels,
            .pseudo_spherical_samples = pseudo_spherical_samples,
            .pseudo_spherical_level_starts = pseudo_spherical_level_starts,
            .pseudo_spherical_level_altitudes = pseudo_spherical_level_altitudes,
            .support_carrier_valid = support_carrier_valid,
            .support_carriers = support_carriers,
            .labos_workspace = labos.Workspace.init(allocator),
        };
    }

    fn deinit(self: *ForwardSampleScratch, allocator: Allocator) void {
        self.labos_workspace.deinit();
        allocator.free(self.layer_inputs);
        allocator.free(self.source_interfaces);
        allocator.free(self.rtm_quadrature_levels);
        allocator.free(self.pseudo_spherical_samples);
        allocator.free(self.pseudo_spherical_level_starts);
        allocator.free(self.pseudo_spherical_level_altitudes);
        allocator.free(self.support_carrier_valid);
        allocator.free(self.support_carriers);
        self.* = undefined;
    }
};

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: mutex=16 B, err=2 B; padding: 6 B (48 bits)
//   unused bits: 48 padding + 0 bool-storage slack = 48 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count
const ForwardPrefetchErrorState = struct {
    mutex: std.Thread.Mutex = .{},
    err: ?Error = null,

    fn store(self: *ForwardPrefetchErrorState, err: Error) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.err == null) self.err = err;
    }
};

// layout(64-bit):
//   size: 352 B, align: 8 B
//   field storage: 352 B across 13 fields; largest: implementations=168 B, route=72 B, misses=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: scene, prepared, misses, profile_spectroscopy_caches, results, +2 more carry references/descriptors; referenced storage is not included in size
//   cache span: 6 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 352 B (0.344 KiB); total also includes referenced storage above
const ForwardPrefetchWorker = struct {
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    safe_span: f64,
    misses: []const ForwardCacheMiss,
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache,
    results: []ForwardIntegratedSample,
    error_state: *ForwardPrefetchErrorState,
    start_index: usize,
    end_index: usize,
    queue: ?*work_partition.ChunkQueue = null,
    worker_index: usize = 0,
};

pub fn radianceFromForward(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: common.ForwardResult,
) f64 {
    const scale = radianceScaleFromForward(scene, prepared, implementations, wavelength_nm, safe_span, phase, forward);
    return forward.toa_reflectance_factor * scale;
}

fn radianceScaleFromForward(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: common.ForwardResult,
) f64 {
    const solar_irradiance = solar_compat.irradianceAtWavelength(scene, wavelength_nm);
    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
    const surface_gain = implementations.surface.brdfFactor(.{
        .scene = scene,
        .prepared = prepared,
        .wavelength_nm = wavelength_nm,
        .safe_span = safe_span,
        .phase = phase,
        .forward = forward,
    });
    return solar_cosine * surface_gain * solar_irradiance / std.math.pi;
}

fn radianceJacobianFromForward(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: common.ForwardResult,
) jacobian.Vector {
    const reflectance_jacobian = forward.jacobian orelse return jacobian.zero();
    const scale = radianceScaleFromForward(scene, prepared, implementations, wavelength_nm, safe_span, phase, forward);
    return jacobian.scale(reflectance_jacobian, scale);
}

fn integratedSampleFromForward(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: common.ForwardResult,
) ForwardIntegratedSample {
    const scale = radianceScaleFromForward(scene, prepared, implementations, wavelength_nm, safe_span, phase, forward);
    return .{
        .radiance = forward.toa_reflectance_factor * scale,
        .jacobian = if (forward.jacobian) |reflectance_jacobian|
            jacobian.scale(reflectance_jacobian, scale)
        else
            jacobian.zero(),
    };
}

// hot path:
//   when: fallback path for a single uncached high-resolution wavelength
//   work: allocates temporary carrier and LABOS scratch, then delegates to the scratch-based solver
//   data: support carrier valid bits, support carriers, labos workspace
//   follow: callers that bypass batch prefetch and reach this per wavelength
pub fn computeForwardSampleAtWavelength(
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
) Error!ForwardIntegratedSample {
    const support_cache_count = if (prepared.sublayers) |sublayers| sublayers.len else layer_inputs.len;
    const support_carrier_valid = try allocator.alloc(bool, support_cache_count);
    defer allocator.free(support_carrier_valid);
    const support_carriers = try allocator.alloc(CarrierEval.SharedOpticalCarrier, support_cache_count);
    defer allocator.free(support_carriers);
    var labos_workspace = labos.Workspace.init(allocator);
    defer labos_workspace.deinit();
    return computeForwardSampleAtWavelengthWithScratch(
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
        support_carrier_valid,
        support_carriers,
        null,
        &labos_workspace,
    );
}

// hot path:
//   when: once per high-resolution wavelength cache miss in forward/retrieval runs
//   work: builds wavelength-specific forward input and executes LABOS transport
//   data: layer inputs, carrier cache arrays, pseudo-spherical buffers, labos workspace
//   follow: ForwardInput.configuredForwardInput and executePreparedWithLabosWorkspace
fn computeForwardSampleAtWavelengthWithScratch(
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
    support_carrier_valid: []bool,
    support_carriers: []CarrierEval.SharedOpticalCarrier,
    profile_spectroscopy_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    labos_workspace: *labos.Workspace,
) Error!ForwardIntegratedSample {
    const sample_zone = Trace.deepStaticZone(@src(), "forward_sample");
    defer sample_zone.end();

    Trace.plotU("forward_samples", 1);
    const input = input: {
        const zone = Trace.deepStaticZone(@src(), "forward_sample.configured_forward_input");
        defer zone.end();
        break :input try ForwardInput.configuredForwardInput(
            scene,
            route,
            prepared,
            wavelength_nm,
            layer_inputs,
            source_interfaces,
            rtm_quadrature_levels,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            support_carrier_valid,
            support_carriers,
            profile_spectroscopy_cache,
        );
    };
    var effective_route = route;
    effective_route.rtm_controls = input.rtm_controls;
    const forward = forward: {
        const zone = Trace.deepStaticZone(@src(), "forward_sample.labos_execute");
        defer zone.end();
        break :forward if (implementations.transport.executePreparedWithLabosWorkspace) |execute_with_workspace|
            try execute_with_workspace(allocator, effective_route, input, labos_workspace)
        else
            try implementations.transport.executePrepared(allocator, effective_route, input);
    };
    return integratedSampleFromForward(scene, prepared, implementations, wavelength_nm, safe_span, 0.0, forward);
}

// hot path:
//   when: on each forward prefetch worker across assigned miss chunks
//   work: computes one dense result per miss using the worker scratch
//   data: miss array, result array, profile spectroscopy cache slice, worker scratch
//   follow: nextForwardPrefetchChunk and computeForwardSampleAtWavelengthWithScratch
fn prefetchForwardWorkerMain(worker: *ForwardPrefetchWorker) void {
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-forward-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-forward-worker";
    Trace.setThreadName(thread_name);

    const worker_zone = Trace.staticZone(@src(), "forward_prefetch.worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var scratch = ForwardSampleScratch.init(
        allocator,
        worker.scene,
        worker.route,
        worker.prepared,
    ) catch |err| {
        worker.error_state.store(err);
        return;
    };
    defer scratch.deinit(allocator);

    while (nextForwardPrefetchChunk(worker)) |chunk| {
        {
            const chunk_zone = Trace.deepStaticZone(@src(), "forward_prefetch.chunk");
            chunk_zone.value(@intCast(chunk.end - chunk.start));
            defer chunk_zone.end();

            for (chunk.start..chunk.end) |index| {
                const miss = worker.misses[index];
                const profile_spectroscopy_cache = if (worker.profile_spectroscopy_caches.len == worker.misses.len)
                    &worker.profile_spectroscopy_caches[index]
                else
                    null;
                worker.results[index] = computeForwardSampleAtWavelengthWithScratch(
                    allocator,
                    worker.scene,
                    worker.route,
                    worker.prepared,
                    miss.wavelength_nm,
                    worker.safe_span,
                    worker.implementations,
                    scratch.layer_inputs,
                    scratch.source_interfaces,
                    scratch.rtm_quadrature_levels,
                    scratch.pseudo_spherical_samples,
                    scratch.pseudo_spherical_level_starts,
                    scratch.pseudo_spherical_level_altitudes,
                    scratch.support_carrier_valid,
                    scratch.support_carriers,
                    profile_spectroscopy_cache,
                    &scratch.labos_workspace,
                ) catch |err| {
                    worker.error_state.store(err);
                    return;
                };
            }
        }
    }
}

fn nextForwardPrefetchChunk(worker: *ForwardPrefetchWorker) ?work_partition.Range {
    if (worker.queue) |queue| return queue.next();
    if (worker.start_index >= worker.end_index) return null;
    const chunk = work_partition.Range{
        .start = worker.start_index,
        .end = @min(worker.start_index + forward_prefetch_chunk_size, worker.end_index),
    };
    worker.start_index = chunk.end;
    return chunk;
}

// hot path:
//   when: once per forward miss batch before nominal wavelength integration
//   work: schedules miss chunks across one worker, spawned threads, or a thread pool
//   data: miss array, profile cache array, result array, worker descriptors
//   follow: preferredForwardWorkerCount and ForwardSampleScratch allocation boundaries
pub fn prefetchForwardSamples(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    safe_span: f64,
    misses: []const ForwardCacheMiss,
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache,
    results: []ForwardIntegratedSample,
    thread_pool: ?*std.Thread.Pool,
) Error!void {
    if (misses.len == 0) return;

    const preferred_worker_count = preferredForwardWorkerCount(misses.len);
    const worker_count = preferred_worker_count;
    Trace.plotU("forward_worker_count", @intCast(worker_count));
    Trace.plotU("high_resolution_misses", @intCast(misses.len));

    if (worker_count == 1) {
        var scratch = try ForwardSampleScratch.init(allocator, scene, route, prepared);
        defer scratch.deinit(allocator);
        for (misses, results, 0..) |miss, *result, miss_index| {
            const profile_spectroscopy_cache = if (profile_spectroscopy_caches.len == misses.len)
                &profile_spectroscopy_caches[miss_index]
            else
                null;
            result.* = try computeForwardSampleAtWavelengthWithScratch(
                allocator,
                scene,
                route,
                prepared,
                miss.wavelength_nm,
                safe_span,
                implementations,
                scratch.layer_inputs,
                scratch.source_interfaces,
                scratch.rtm_quadrature_levels,
                scratch.pseudo_spherical_samples,
                scratch.pseudo_spherical_level_starts,
                scratch.pseudo_spherical_level_altitudes,
                scratch.support_carrier_valid,
                scratch.support_carriers,
                profile_spectroscopy_cache,
                &scratch.labos_workspace,
            );
        }
        return;
    }

    var error_state = ForwardPrefetchErrorState{};
    const workers = try allocator.alloc(ForwardPrefetchWorker, worker_count);
    defer allocator.free(workers);

    for (0..worker_count) |worker_index| {
        const range = work_partition.staticRange(misses.len, worker_count, worker_index);
        workers[worker_index] = .{
            .scene = scene,
            .route = route,
            .prepared = prepared,
            .implementations = implementations,
            .safe_span = safe_span,
            .misses = misses,
            .profile_spectroscopy_caches = profile_spectroscopy_caches,
            .results = results,
            .error_state = &error_state,
            .start_index = range.start,
            .end_index = range.end,
            .worker_index = worker_index,
        };
    }

    if (thread_pool) |pool| {
        var queue = work_partition.ChunkQueue.init(misses.len, forward_prefetch_pooled_chunk_size);
        for (workers) |*worker| worker.queue = &queue;
        var wait_group = std.Thread.WaitGroup{};
        for (0..worker_count - 1) |worker_index| {
            pool.spawnWg(&wait_group, prefetchForwardWorkerMain, .{&workers[worker_index]});
        }
        prefetchForwardWorkerMain(&workers[worker_count - 1]);
        wait_group.wait();
        if (error_state.err) |err| return err;
        return;
    }

    const threads = try allocator.alloc(std.Thread, worker_count - 1);
    defer allocator.free(threads);
    var started_thread_count: usize = 0;
    for (0..worker_count - 1) |worker_index| {
        threads[started_thread_count] = std.Thread.spawn(
            .{},
            prefetchForwardWorkerMain,
            .{&workers[worker_index]},
        ) catch {
            prefetchForwardWorkerMain(&workers[worker_index]);
            continue;
        };
        started_thread_count += 1;
    }
    prefetchForwardWorkerMain(&workers[worker_count - 1]);
    for (threads[0..started_thread_count]) |thread| thread.join();
    if (error_state.err) |err| return err;
}

// PUB FOR TEST: re-exported via measurement/internal.zig.
pub fn preferredForwardWorkerCount(miss_count: usize) usize {
    return work_partition.preferredWorkerCount(miss_count, min_parallel_forward_miss_count);
}
