const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const calibration = @import("../spectral_math/calibration.zig");
const grid = @import("../spectral_math/grid.zig");
const SpectralEval = @import("spectral_eval.zig");
const Types = @import("types.zig");
const Plan = @import("wavelength_plan.zig");
const Storage = @import("storage.zig");
const IntegrationKernel = @import("../../implementations/instrument.zig").IntegrationKernel;
const instrument_integration = @import("../../implementations/instrument/integration.zig");
const Trace = @import("../../performance_trace.zig");
const work_partition = @import("../../work_partition.zig");

const Allocator = std.mem.Allocator;
const Error = Storage.Error;

pub const WavelengthSampling = Plan.WavelengthSampling;

const min_parallel_wavelength_sample_count: usize = 64;
const wavelength_sampling_chunk_size: usize = 16;

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: mutex=16 B, err=2 B; padding: 6 B (48 bits)
//   unused bits: 48 padding + 0 bool-storage slack = 48 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count
const WavelengthSamplingErrorState = struct {
    mutex: std.Thread.Mutex = .{},
    err: ?Error = null,

    fn store(self: *WavelengthSamplingErrorState, err: Error) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.err == null) self.err = err;
    }
};

// layout(64-bit):
//   size: 152 B, align: 8 B
//   field storage: 145 B across 12 fields; largest: radiance_calibration=32 B, irradiance_calibration=32 B, plans=16 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   out-of-line: scene, prepared, resolved_axis, radiance_adaptive_cache, irradiance_adaptive_cache, +3 more carry references/descriptors; referenced storage is not included in size
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 152 B (0.148 KiB); total also includes referenced storage above
const WavelengthSamplingWorker = struct {
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    can_cache_adaptive_plan: bool,
    radiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    irradiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    plans: []WavelengthSampling,
    queue: *work_partition.ChunkQueue,
    error_state: *WavelengthSamplingErrorState,
    worker_index: usize,
};

// hot path:
//   when: once per simulation plan, often reused across OE iterations
//   work: expands output wavelengths into radiance and irradiance integration plans
//   data: resolved spectral axis, channel calibrations, adaptive kernel caches, sampling rows
//   follow: fillWavelengthSamplingPlans and collectUniqueForwardMisses
pub fn buildWavelengthSampling(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    implementations: Types.Implementations,
) Error![]WavelengthSampling {
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try resolved_axis.validate();
    const plans = try allocator.alloc(WavelengthSampling, sample_count);
    errdefer allocator.free(plans);
    const can_cache_adaptive_plan = prepared.spectroscopy_lines != null and
        std.mem.eql(u8, implementations.instrument.id, "builtin.generic_response");
    var radiance_adaptive_cache: instrument_integration.AdaptiveKernelCache = .{};
    var irradiance_adaptive_cache: instrument_integration.AdaptiveKernelCache = .{};
    if (can_cache_adaptive_plan) {
        const zone = Trace.staticZone(@src(), "wavelength_sampling.prepare_adaptive_cache");
        defer zone.end();
        _ = instrument_integration.prepareAdaptiveKernelCache(
            scene,
            prepared,
            .radiance,
            &radiance_adaptive_cache,
        );
        _ = instrument_integration.prepareAdaptiveKernelCache(
            scene,
            prepared,
            .irradiance,
            &irradiance_adaptive_cache,
        );
    }

    {
        const zone = Trace.staticZone(@src(), "wavelength_sampling.sample_loop");
        defer zone.end();
        try fillWavelengthSamplingPlans(
            allocator,
            scene,
            prepared,
            resolved_axis,
            radiance_calibration,
            irradiance_calibration,
            can_cache_adaptive_plan,
            &radiance_adaptive_cache,
            &irradiance_adaptive_cache,
            plans,
        );
    }
    return plans;
}

// hot path:
//   when: wavelength sampling expands all output grid points into integration plans
//   work: chooses single-thread or chunked worker execution for plan rows
//   data: output plan array, resolved axis, channel calibrations, adaptive caches
//   follow: wavelengthSamplingWorkerMain and fillWavelengthSamplingPlanRange
fn fillWavelengthSamplingPlans(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    can_cache_adaptive_plan: bool,
    radiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    irradiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    plans: []WavelengthSampling,
) Error!void {
    const worker_count = preferredWavelengthSamplingWorkerCount(plans.len);
    if (worker_count == 1) {
        return fillWavelengthSamplingPlanRange(
            scene,
            prepared,
            resolved_axis,
            radiance_calibration,
            irradiance_calibration,
            can_cache_adaptive_plan,
            radiance_adaptive_cache,
            irradiance_adaptive_cache,
            plans,
            0,
            plans.len,
        );
    }

    var error_state = WavelengthSamplingErrorState{};
    const workers = try allocator.alloc(WavelengthSamplingWorker, worker_count);
    defer allocator.free(workers);
    const threads = try allocator.alloc(std.Thread, worker_count - 1);
    defer allocator.free(threads);

    var queue = work_partition.ChunkQueue.init(plans.len, wavelength_sampling_chunk_size);
    var started_thread_count: usize = 0;
    for (0..worker_count) |worker_index| {
        workers[worker_index] = .{
            .scene = scene,
            .prepared = prepared,
            .resolved_axis = resolved_axis,
            .radiance_calibration = radiance_calibration,
            .irradiance_calibration = irradiance_calibration,
            .can_cache_adaptive_plan = can_cache_adaptive_plan,
            .radiance_adaptive_cache = radiance_adaptive_cache,
            .irradiance_adaptive_cache = irradiance_adaptive_cache,
            .plans = plans,
            .queue = &queue,
            .error_state = &error_state,
            .worker_index = worker_index,
        };
        if (worker_index + 1 < worker_count) {
            threads[started_thread_count] = std.Thread.spawn(
                .{},
                wavelengthSamplingWorkerMain,
                .{&workers[worker_index]},
            ) catch {
                wavelengthSamplingWorkerMain(&workers[worker_index]);
                continue;
            };
            started_thread_count += 1;
        } else {
            wavelengthSamplingWorkerMain(&workers[worker_index]);
        }
    }
    for (threads[0..started_thread_count]) |thread| thread.join();
    if (error_state.err) |err| return err;
}

// hot path:
//   when: wavelength sampling runs in parallel over output-grid chunks
//   work: pulls chunks and fills integration-plan rows for each assigned output wavelength
//   data: chunk queue, plan array, adaptive caches, worker error state
//   follow: fillWavelengthSamplingPlanRange and work_partition.ChunkQueue
fn wavelengthSamplingWorkerMain(worker: *WavelengthSamplingWorker) void {
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-sampling-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-sampling-worker";
    Trace.setThreadName(thread_name);

    const worker_zone = Trace.staticZone(@src(), "wavelength_sampling.worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();

    while (worker.queue.next()) |chunk| {
        {
            const chunk_zone = Trace.deepStaticZone(@src(), "wavelength_sampling.chunk");
            chunk_zone.value(@intCast(chunk.end - chunk.start));
            defer chunk_zone.end();

            fillWavelengthSamplingPlanRange(
                worker.scene,
                worker.prepared,
                worker.resolved_axis,
                worker.radiance_calibration,
                worker.irradiance_calibration,
                worker.can_cache_adaptive_plan,
                worker.radiance_adaptive_cache,
                worker.irradiance_adaptive_cache,
                worker.plans,
                chunk.start,
                chunk.end,
            ) catch |err| {
                worker.error_state.store(err);
                return;
            };
        }
    }
}

// hot path:
//   when: a sampling worker fills a contiguous range of output wavelengths
//   work: writes one WavelengthSampling row per output index
//   data: plan array slice, resolved spectral axis, channel integration caches
//   follow: buildWavelengthSamplingPlan and instrument integration kernel construction
fn fillWavelengthSamplingPlanRange(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    can_cache_adaptive_plan: bool,
    radiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    irradiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    plans: []WavelengthSampling,
    start: usize,
    end: usize,
) Error!void {
    for (start..end) |index| {
        plans[index] = try buildWavelengthSamplingPlan(
            scene,
            prepared,
            resolved_axis,
            radiance_calibration,
            irradiance_calibration,
            can_cache_adaptive_plan,
            radiance_adaptive_cache,
            irradiance_adaptive_cache,
            index,
        );
    }
}

// hot path:
//   when: each output wavelength is converted into radiance and irradiance sampling plans
//   work: resolves nominal wavelength, builds channel integration kernels, and applies calibration shifts
//   data: resolved axis, radiance/irradiance adaptive caches, integration kernel outputs
//   follow: integrationForWavelengthWithAdaptiveCacheChecked and calibration.shiftedWavelength
fn buildWavelengthSamplingPlan(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    can_cache_adaptive_plan: bool,
    radiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    irradiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    index: usize,
) Error!WavelengthSampling {
    const nominal_wavelength_nm = resolvedSampleAtAssumeValid(resolved_axis, index);
    var radiance_integration: IntegrationKernel = undefined;
    if (can_cache_adaptive_plan) {
        try instrument_integration.integrationForWavelengthWithAdaptiveCacheChecked(
            scene,
            prepared,
            .radiance,
            nominal_wavelength_nm,
            radiance_adaptive_cache,
            &radiance_integration,
        );
    } else {
        try instrument_integration.integrationForWavelengthChecked(
            scene,
            prepared,
            .radiance,
            nominal_wavelength_nm,
            &radiance_integration,
        );
    }
    var irradiance_integration: IntegrationKernel = undefined;
    if (can_cache_adaptive_plan) {
        try instrument_integration.integrationForWavelengthWithAdaptiveCacheChecked(
            scene,
            prepared,
            .irradiance,
            nominal_wavelength_nm,
            irradiance_adaptive_cache,
            &irradiance_integration,
        );
    } else {
        try instrument_integration.integrationForWavelengthChecked(
            scene,
            prepared,
            .irradiance,
            nominal_wavelength_nm,
            &irradiance_integration,
        );
    }
    return .{
        .nominal_wavelength_nm = nominal_wavelength_nm,
        .radiance_wavelength_nm = calibration.shiftedWavelength(
            radiance_calibration,
            nominal_wavelength_nm,
        ),
        .irradiance_wavelength_nm = calibration.shiftedWavelength(
            irradiance_calibration,
            nominal_wavelength_nm,
        ),
        .radiance_integration = radiance_integration,
        .irradiance_integration = irradiance_integration,
    };
}

fn resolvedSampleAtAssumeValid(resolved_axis: *const grid.ResolvedAxis, index: usize) f64 {
    if (resolved_axis.explicit_wavelengths_nm.len != 0) return resolved_axis.explicit_wavelengths_nm[index];
    const sample_count = resolved_axis.base.sample_count;
    const step = (resolved_axis.base.end_nm - resolved_axis.base.start_nm) /
        @as(f64, @floatFromInt(sample_count - 1));
    return resolved_axis.base.start_nm + step * @as(f64, @floatFromInt(index));
}

fn preferredWavelengthSamplingWorkerCount(sample_count: usize) usize {
    return work_partition.preferredWorkerCount(sample_count, min_parallel_wavelength_sample_count);
}

// hot path:
//   when: once per wavelength plan before forward prefetch
//   work: deduplicates high-resolution radiance integration wavelengths into cache misses
//   data: radiance integration offsets, quantized cache keys, forward miss array
//   follow: miss ordering consumed by SpectralEval.prefetchForwardSamples
pub fn collectUniqueForwardMisses(
    allocator: Allocator,
    plans: []const WavelengthSampling,
) ![]Plan.ForwardCacheMiss {
    var seen = std.AutoHashMap(u64, void).init(allocator);
    defer seen.deinit();
    var misses = std.ArrayList(Plan.ForwardCacheMiss).empty;
    errdefer misses.deinit(allocator);

    for (plans) |plan| {
        const integration_sample_count = if (plan.radiance_integration.enabled) plan.radiance_integration.sample_count else 1;
        for (0..integration_sample_count) |sample_index| {
            const wavelength_nm = if (plan.radiance_integration.enabled)
                plan.radiance_wavelength_nm + plan.radiance_integration.offsets_nm[sample_index]
            else
                plan.radiance_wavelength_nm;
            const key = SpectralEval.SpectralEvaluationCache.keyFor(wavelength_nm);
            const entry = try seen.getOrPut(key);
            if (entry.found_existing) continue;
            try misses.append(allocator, .{
                .key = key,
                .wavelength_nm = wavelength_nm,
            });
        }
    }

    return misses.toOwnedSlice(allocator);
}
