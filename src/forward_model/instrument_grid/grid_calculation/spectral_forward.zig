const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const CarrierEval = @import("../../optical_properties/state_build/carrier_eval.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const common = @import("../../radiative_transfer/root.zig");
const jacobian = @import("../../jacobian/root.zig");
const labos = common.labos;
const Trace = @import("../../instrumentation/trace.zig");
const ForwardInput = @import("forward_input.zig");
const Types = @import("types.zig");
const Storage = @import("storage.zig");
const Plan = @import("wavelength_plan.zig");
const solar_compat = @import("../../../input/reference_data/solar_irradiance.zig");
const work_partition = @import("../../work_partition.zig");
const Telemetry = @import("../../instrumentation/telemetry.zig");

const Allocator = std.mem.Allocator;
const Error = Storage.Error;

// PUB FOR TEST: re-exported via measurement/internal.zig.
pub const min_parallel_forward_miss_count: usize = 32;

pub const ForwardIntegratedSample = Types.ForwardIntegratedSample;

pub const ForwardCacheMiss = Plan.ForwardCacheMiss;
const forward_prefetch_chunk_size: usize = 8;

// Pooled workers handle reused OE/session runs. Smaller chunks trade a little
// more queue traffic for less tail imbalance across thousands of LABOS misses.
const forward_prefetch_pooled_chunk_size: usize = 8;

// migration note: Zig 0.15.2 prefetch runtime ---------------------------------------------------------------|
// Forward prefetch uses std.Thread.Pool while product builds remain pinned to Zig 0.15.2.                    |
// The abandoned 0.16 migration used std.Io.Threaded/Group here; keep retained timing independent of that.    |
// end migration note: Zig 0.15.2 prefetch runtime -----------------------------------------------------------|

const TracePrefetchRoute = if (Storage.trace_phase_timing_enabled) struct {
    const WorkerLabosTiming = ?*labos.PhaseTiming;
    const SingleLabosTiming = labos.PhaseTiming;
    const LabosTimingStorage = [work_partition.max_workers]labos.PhaseTiming;

    const worker_labos_timing_empty: WorkerLabosTiming = null;
    const single_labos_timing_empty: SingleLabosTiming = .{};
} else struct {
    const WorkerLabosTiming = void;
    const SingleLabosTiming = void;
    const LabosTimingStorage = void;

    const worker_labos_timing_empty: WorkerLabosTiming = {};
    const single_labos_timing_empty: SingleLabosTiming = {};
};

const TraceWorkerLabosTiming = TracePrefetchRoute.WorkerLabosTiming;
const TraceSingleLabosTiming = TracePrefetchRoute.SingleLabosTiming;
const TraceLabosTimingStorage = TracePrefetchRoute.LabosTimingStorage;

const trace_worker_labos_timing_default = TracePrefetchRoute.worker_labos_timing_empty;
const trace_single_labos_timing_default = TracePrefetchRoute.single_labos_timing_empty;
const trace_labos_timing_storage_default: TraceLabosTimingStorage = undefined;

// hot path:
//   when: allocated once per forward prefetch worker
//   work: owns reusable layer, source, quadrature, carrier, pseudo-spherical, and LABOS buffers
//   reads: per-worker scratch slices and labos.Workspace
//   follow: reuse inside prefetchForwardWorkerMain across forward misses
// layout(64-bit):
//   size: 3304 B, align: 8 B
//   field storage:
//     3304 B across 8 fields; largest: labos_workspace=3168 B, support_carrier_cache=40 B
//     layer_inputs=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line:
//     layer_inputs always owns transport rows
//     source_interfaces, rtm_quadrature_levels, and pseudo_spherical_* slices are rtm_config-gated
//   cache span: 52 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 3304 B (3.227 KiB); total also includes referenced storage above
const ForwardSampleScratch = struct {
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    support_carrier_cache: CarrierEval.SupportRowScalarCache,
    labos_workspace: labos.Workspace,

    fn initInto(
        self: *ForwardSampleScratch,
        allocator: Allocator,
        scene: *const Scene,
        rtm_config: common.SolveConfig,
        prepared: *const OpticsPreparation.PreparedOpticalState,
    ) !void {
        const layer_count = Storage.resolvedTransportLayerCount(rtm_config, prepared);
        const pseudo_spherical_sample_count = Storage.resolvedPseudoSphericalSampleCount(scene, rtm_config, prepared);
        const support_cache_count = if (prepared.sublayers) |sublayers| sublayers.len else layer_count;
        const needs_source_interfaces = Storage.configMayUseSourceInterfaces(scene, rtm_config);
        const needs_rtm_quadrature = Storage.configUsesRtmQuadrature(rtm_config);
        const needs_pseudo_spherical_grid = Storage.configUsesPseudoSphericalGrid(rtm_config);

        const layer_inputs = try allocator.alloc(common.LayerInput, layer_count);
        errdefer allocator.free(layer_inputs);
        var source_interfaces: []common.SourceInterfaceInput = @constCast(&[_]common.SourceInterfaceInput{});
        if (needs_source_interfaces) {
            source_interfaces = try allocator.alloc(common.SourceInterfaceInput, layer_count + 1);
        }

        errdefer if (source_interfaces.len != 0) allocator.free(source_interfaces);
        var rtm_quadrature_levels: []common.RtmQuadratureLevel = @constCast(&[_]common.RtmQuadratureLevel{});
        if (needs_rtm_quadrature) {
            rtm_quadrature_levels = try allocator.alloc(common.RtmQuadratureLevel, layer_count + 1);
        }
        errdefer if (rtm_quadrature_levels.len != 0) allocator.free(rtm_quadrature_levels);

        var pseudo_spherical_samples: []common.PseudoSphericalSample =
            @constCast(&[_]common.PseudoSphericalSample{});
        if (needs_pseudo_spherical_grid) {
            pseudo_spherical_samples = try allocator.alloc(
                common.PseudoSphericalSample,
                pseudo_spherical_sample_count,
            );
        }
        errdefer if (pseudo_spherical_samples.len != 0) allocator.free(pseudo_spherical_samples);
        var pseudo_spherical_level_starts: []usize = @constCast(&[_]usize{});
        if (needs_pseudo_spherical_grid) {
            pseudo_spherical_level_starts = try allocator.alloc(usize, layer_count + 1);
        }

        errdefer if (pseudo_spherical_level_starts.len != 0) allocator.free(pseudo_spherical_level_starts);
        var pseudo_spherical_level_altitudes: []f64 = @constCast(&[_]f64{});
        if (needs_pseudo_spherical_grid) {
            pseudo_spherical_level_altitudes = try allocator.alloc(f64, layer_count + 1);
        }
        errdefer if (pseudo_spherical_level_altitudes.len != 0) allocator.free(pseudo_spherical_level_altitudes);

        var support_carrier_cache = try CarrierEval.SupportRowScalarCache.init(allocator, support_cache_count);
        errdefer support_carrier_cache.deinit(allocator);

        self.* = .{
            .layer_inputs = layer_inputs,
            .source_interfaces = source_interfaces,
            .rtm_quadrature_levels = rtm_quadrature_levels,
            .pseudo_spherical_samples = pseudo_spherical_samples,
            .pseudo_spherical_level_starts = pseudo_spherical_level_starts,
            .pseudo_spherical_level_altitudes = pseudo_spherical_level_altitudes,
            .support_carrier_cache = support_carrier_cache,
            .labos_workspace = labos.Workspace.init(allocator),
        };
    }

    fn deinit(self: *ForwardSampleScratch, allocator: Allocator) void {
        self.labos_workspace.deinit();
        allocator.free(self.layer_inputs);
        if (self.source_interfaces.len != 0) allocator.free(self.source_interfaces);
        if (self.rtm_quadrature_levels.len != 0) allocator.free(self.rtm_quadrature_levels);
        if (self.pseudo_spherical_samples.len != 0) allocator.free(self.pseudo_spherical_samples);

        if (self.pseudo_spherical_level_starts.len != 0) allocator.free(self.pseudo_spherical_level_starts);
        if (self.pseudo_spherical_level_altitudes.len != 0) allocator.free(self.pseudo_spherical_level_altitudes);
        self.support_carrier_cache.deinit(allocator);
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

// layout(product 64-bit):
//   size: 184 B, align: 8 B
//   field storage:
//     184 B across 11 product fields; largest: rtm_config=80 B, misses=16 B
//     profile_spectroscopy_caches=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line:
//     scene, prepared, misses, profile_spectroscopy_caches, results, +2 more carry references/descriptors
//     referenced storage is not included in size
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 184 B (0.180 KiB); total also includes referenced storage above
//   telemetry:
//     telemetry_context is zero-size in product builds
//     validation telemetry builds use it for row attribution
const ForwardPrefetchWorker = struct {
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    misses: []const ForwardCacheMiss,
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache,
    results: []ForwardIntegratedSample,
    error_state: *ForwardPrefetchErrorState,
    start_index: usize,
    end_index: usize,
    queue: ?*work_partition.ChunkQueue = null,
    worker_index: usize = 0,
    telemetry_context: Telemetry.Context,
    labos_phase_timing: TraceWorkerLabosTiming = trace_worker_labos_timing_default,
};

inline fn initializeTraceLabosTimingStorage(
    trace_phase_timing: ?*Storage.TracePhaseTiming,
    worker_count: usize,
    storage: *TraceLabosTimingStorage,
) void {
    if (comptime Storage.trace_phase_timing_enabled) {
        if (trace_phase_timing != null) {
            for (storage[0..worker_count]) |*timing| timing.* = .{};
        }
    }
}

inline fn attachSingleTraceLabosTiming(
    trace_phase_timing: ?*Storage.TracePhaseTiming,
    scratch: *ForwardSampleScratch,
    timing: *TraceSingleLabosTiming,
) void {
    if (comptime Storage.trace_phase_timing_enabled) {
        _ = trace_phase_timing orelse return;
        scratch.labos_workspace.setTracePhaseTiming(timing);
    }
}

inline fn clearTraceLabosTiming(scratch: *ForwardSampleScratch) void {
    if (comptime Storage.trace_phase_timing_enabled) {
        scratch.labos_workspace.clearTracePhaseTiming();
    }
}

inline fn traceWorkerLabosTiming(
    trace_phase_timing: ?*Storage.TracePhaseTiming,
    storage: *TraceLabosTimingStorage,
    worker_index: usize,
) TraceWorkerLabosTiming {
    if (comptime Storage.trace_phase_timing_enabled) {
        if (trace_phase_timing != null) return &storage[worker_index];

        return null;
    } else {
        return {};
    }
}

fn radianceScaleFromForward(
    scene: *const Scene,
    wavelength_nm: f64,
) f64 {
    const solar_irradiance = solar_compat.irradianceAtWavelength(scene, wavelength_nm);
    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);

    // math: built-in O2 A surface scaling is Lambertian, so BRDF_factor(lambda) = 1.
    return solar_cosine * solar_irradiance / std.math.pi;
}

fn integratedSampleFromForward(
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    wavelength_nm: f64,
    forward: common.ForwardResult,
) ForwardIntegratedSample {
    const scale = radianceScaleFromForward(scene, wavelength_nm);
    var radiance_jacobian = jacobian.zero();
    if (forward.jacobian) |reflectance_jacobian| {
        radiance_jacobian = jacobian.scaleMasked(
            reflectance_jacobian,
            scale,
            rtm_config.derivative_state_mask,
        );
    }

    return .{

        // math: L(lambda) = reflectance_factor(lambda) * scale(lambda).
        .radiance = forward.toa_reflectance_factor * scale,

        // math: dL/dx = scale(lambda) * d(reflectance_factor)/dx for each active retrieval state x.
        .jacobian = radiance_jacobian,
    };
}

fn computeForwardSampleAtWavelengthWithScratch(
    allocator: Allocator,
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    support_carrier_cache: *CarrierEval.SupportRowScalarCache,
    profile_spectroscopy_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    labos_workspace: *labos.Workspace,
) Error!ForwardIntegratedSample {

    // hot path:
    //   when: once per high-resolution wavelength cache miss in forward/retrieval runs
    //   work: builds wavelength-specific forward input and executes LABOS transport
    //   Uses layer inputs, carrier cache arrays, pseudo-spherical buffers, and labos workspace.
    //   follow: ForwardInput.configuredForwardInput and executePreparedWithLabosWorkspace
    //   math:
    //     lambda -> optical layers(lambda) -> LABOS reflectance_factor(lambda)
    //     then L(lambda) via solar/BRDF scaling

    // instrumentation: trace zone
    // captures: one high-resolution forward-sample solve
    // why: separate per-miss optical input setup and LABOS execution from nominal-grid assembly.
    const sample_zone = Trace.deepStaticZone(@src(), "forward_sample");
    defer sample_zone.end();

    // instrumentation: trace counter
    // captures: number of high-resolution forward samples evaluated
    // why: normalize prefetch wall time by actual LABOS solve count.
    Trace.plotU("forward_samples", 1);
    const input = input: {

        // instrumentation: trace zone
        // captures: wavelength-specific forward-input construction
        // why: show carrier/layer preparation cost before transport.
        const zone = Trace.deepStaticZone(@src(), "forward_sample.configured_forward_input");
        defer zone.end();
        break :input try ForwardInput.configuredForwardInput(
            scene,
            rtm_config,
            prepared,
            wavelength_nm,
            layer_inputs,
            source_interfaces,
            rtm_quadrature_levels,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            support_carrier_cache,
            profile_spectroscopy_cache,
        );
    };
    var effective_config = rtm_config;
    effective_config.rtm_controls = input.rtm_controls;
    const forward = forward: {

        // instrumentation: trace zone
        // captures: LABOS transport execution for one forward sample
        // why: keep the radiative-transfer solve separate from surrounding input and scaling work.
        const zone = Trace.deepStaticZone(@src(), "forward_sample.labos_execute");
        defer zone.end();
        break :forward try common.executePreparedWithLabosWorkspace(
            allocator,
            effective_config,
            input,
            labos_workspace,
        );
    };
    return integratedSampleFromForward(scene, rtm_config, wavelength_nm, forward);
}

fn prefetchForwardWorkerMain(worker: *ForwardPrefetchWorker) void {

    // hot path:
    //   when: on each forward prefetch worker across assigned miss chunks
    //   work: computes one dense result per miss using the worker scratch
    //   reads: miss array, result array, profile spectroscopy cache slice, worker scratch
    //   follow: nextForwardPrefetchChunk and computeForwardSampleAtWavelengthWithScratch
    //   math: results[k] = F(misses[k].wavelength_nm) for the chunk's high-resolution wavelength misses

    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-forward-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-forward-worker";

    // instrumentation: trace thread label
    // captures: forward-prefetch worker identity
    // why: make parallel miss batches separable in timeline traces.
    Trace.setThreadName(thread_name);

    // instrumentation: trace zone
    // captures: forward-prefetch worker wall time
    // why: expose load balance across high-resolution miss chunks.
    const worker_zone = Trace.staticZone(@src(), "forward_prefetch.worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var scratch: ForwardSampleScratch = undefined;
    scratch.initInto(
        allocator,
        worker.scene,
        worker.rtm_config,
        worker.prepared,
    ) catch |err| {
        worker.error_state.store(err);
        return;
    };
    if (comptime Storage.trace_phase_timing_enabled) {
        if (worker.labos_phase_timing) |timing| {
            scratch.labos_workspace.setTracePhaseTiming(timing);
        }
    }
    defer clearTraceLabosTiming(&scratch);
    defer scratch.deinit(allocator);

    while (nextForwardPrefetchChunk(worker)) |chunk| {
        {

            // instrumentation: trace zone
            // captures: one prefetch chunk size and wall time
            // why: reveal tail imbalance and chunking overhead in parallel forward solves.
            const chunk_zone = Trace.deepStaticZone(@src(), "forward_prefetch.chunk");
            chunk_zone.value(@intCast(chunk.end - chunk.start));
            defer chunk_zone.end();

            for (chunk.start..chunk.end) |index| {
                const miss = worker.misses[index];
                const profile_spectroscopy_cache = if (worker.profile_spectroscopy_caches.len == worker.misses.len)
                    &worker.profile_spectroscopy_caches[index]
                else
                    null;

                worker.results[index] = compute_sample: {
                    const previous_context = Telemetry.currentContext();
                    Telemetry.setContext(telemetrySampleContext(
                        worker.telemetry_context,
                        index + 1,
                        miss.wavelength_nm,
                    ));
                    defer Telemetry.setContext(previous_context);
                    break :compute_sample computeForwardSampleAtWavelengthWithScratch(
                        allocator,
                        worker.scene,
                        worker.rtm_config,
                        worker.prepared,
                        miss.wavelength_nm,
                        scratch.layer_inputs,
                        scratch.source_interfaces,
                        scratch.rtm_quadrature_levels,
                        scratch.pseudo_spherical_samples,
                        scratch.pseudo_spherical_level_starts,
                        scratch.pseudo_spherical_level_altitudes,
                        &scratch.support_carrier_cache,
                        profile_spectroscopy_cache,
                        &scratch.labos_workspace,
                    ) catch |err| {
                        worker.error_state.store(err);
                        return;
                    };
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

    // hot path:
    //   when: once per forward miss batch before nominal wavelength integration
    //   work: schedules miss chunks across one worker, spawned threads, or a reusable thread pool
    //   reads: miss array, profile cache array, result array, worker descriptors
    //   follow: preferredForwardWorkerCount and ForwardSampleScratch allocation boundaries

    if (misses.len == 0) return;
    const preferred_worker_count = preferredForwardWorkerCount(misses.len);
    const worker_count = preferred_worker_count;

    // instrumentation: trace counter
    // captures: selected forward worker count
    // why: tie prefetch timing to the concurrency shape chosen for this miss batch.
    Trace.plotU("forward_worker_count", @intCast(worker_count));

    // instrumentation: trace counter
    // captures: unique high-resolution cache misses
    // why: distinguish fewer computations from cheaper computation per miss.
    Trace.plotU("high_resolution_misses", @intCast(misses.len));

    const telemetry_context = Telemetry.currentContext();

    if (worker_count == 1) {
        var labos_phase_timing: TraceSingleLabosTiming = trace_single_labos_timing_default;
        var scratch: ForwardSampleScratch = undefined;
        try scratch.initInto(allocator, scene, rtm_config, prepared);

        attachSingleTraceLabosTiming(trace_phase_timing, &scratch, &labos_phase_timing);
        defer clearTraceLabosTiming(&scratch);
        defer scratch.deinit(allocator);

        for (misses, results, 0..) |miss, *result, miss_index| {
            const profile_spectroscopy_cache = if (profile_spectroscopy_caches.len == misses.len)
                &profile_spectroscopy_caches[miss_index]
            else
                null;

            result.* = result_value: {
                const previous_context = Telemetry.currentContext();
                Telemetry.setContext(telemetrySampleContext(
                    telemetry_context,
                    miss_index + 1,
                    miss.wavelength_nm,
                ));
                defer Telemetry.setContext(previous_context);
                break :result_value try computeForwardSampleAtWavelengthWithScratch(
                    allocator,
                    scene,
                    rtm_config,
                    prepared,
                    miss.wavelength_nm,
                    scratch.layer_inputs,
                    scratch.source_interfaces,
                    scratch.rtm_quadrature_levels,
                    scratch.pseudo_spherical_samples,
                    scratch.pseudo_spherical_level_starts,
                    scratch.pseudo_spherical_level_altitudes,
                    &scratch.support_carrier_cache,
                    profile_spectroscopy_cache,
                    &scratch.labos_workspace,
                );
            };
        }
        if (comptime Storage.trace_phase_timing_enabled) {
            mergeLabosPhaseTiming(trace_phase_timing, &.{labos_phase_timing});
        }
        return;
    }

    std.debug.assert(worker_count <= work_partition.max_workers);
    var error_state = ForwardPrefetchErrorState{};
    var labos_phase_timing_storage: TraceLabosTimingStorage = trace_labos_timing_storage_default;
    initializeTraceLabosTimingStorage(trace_phase_timing, worker_count, &labos_phase_timing_storage);

    var worker_storage: [work_partition.max_workers]ForwardPrefetchWorker = undefined;
    const workers = worker_storage[0..worker_count];

    for (0..worker_count) |worker_index| {
        const range = work_partition.staticRange(misses.len, worker_count, worker_index);
        workers[worker_index] = .{
            .scene = scene,
            .rtm_config = rtm_config,
            .prepared = prepared,
            .misses = misses,
            .profile_spectroscopy_caches = profile_spectroscopy_caches,
            .results = results,
            .error_state = &error_state,
            .start_index = range.start,
            .end_index = range.end,
            .worker_index = worker_index,
            .telemetry_context = telemetry_context,
            .labos_phase_timing = traceWorkerLabosTiming(
                trace_phase_timing,
                &labos_phase_timing_storage,
                worker_index,
            ),
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
        if (comptime Storage.trace_phase_timing_enabled) {
            mergeLabosPhaseTiming(trace_phase_timing, labos_phase_timing_storage[0..worker_count]);
        }
        if (error_state.err) |err| return err;
        return;
    }

    var thread_storage: [work_partition.max_workers - 1]std.Thread = undefined;
    const threads = thread_storage[0 .. worker_count - 1];
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
    if (comptime Storage.trace_phase_timing_enabled) {
        mergeLabosPhaseTiming(trace_phase_timing, labos_phase_timing_storage[0..worker_count]);
    }
    if (error_state.err) |err| return err;
}

fn mergeLabosPhaseTiming(
    trace_phase_timing: ?*Storage.TracePhaseTiming,
    worker_timings: []const labos.PhaseTiming,
) void {
    if (comptime Storage.trace_phase_timing_enabled) {
        const timing = trace_phase_timing orelse return;
        for (worker_timings) |worker_timing| timing.labos.merge(worker_timing);
    } else {
        return;
    }
}

pub fn preferredForwardWorkerCount(miss_count: usize) usize {

    // PUB FOR TEST: re-exported via measurement/internal.zig.

    return work_partition.preferredWorkerCount(miss_count, min_parallel_forward_miss_count);
}

fn telemetrySampleContext(base: Telemetry.Context, sample_index: usize, wavelength_nm: f64) Telemetry.Context {
    if (comptime !Telemetry.enabled) return base;
    var context = base;
    context.sample_index = std.math.cast(i64, sample_index) orelse std.math.maxInt(i64);
    context.wavelength_nm = wavelength_nm;
    return context;
}
