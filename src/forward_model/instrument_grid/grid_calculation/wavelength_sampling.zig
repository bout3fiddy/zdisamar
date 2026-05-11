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

const Allocator = std.mem.Allocator;
const Error = Storage.Error;

pub const WavelengthSampling = Plan.WavelengthSampling;

const min_parallel_wavelength_sample_count: usize = 64;
const wavelength_sampling_chunk_size: usize = 16;

const WavelengthSamplingErrorState = struct {
    mutex: std.Thread.Mutex = .{},
    err: ?Error = null,

    fn store(self: *WavelengthSamplingErrorState, err: Error) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.err == null) self.err = err;
    }
};

const WavelengthSamplingQueue = struct {
    mutex: std.Thread.Mutex = .{},
    next_index: usize = 0,
    len: usize,

    fn next(self: *WavelengthSamplingQueue) ?struct { start: usize, end: usize } {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.next_index >= self.len) return null;
        const start = self.next_index;
        const end = @min(start + wavelength_sampling_chunk_size, self.len);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};

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
    queue: *WavelengthSamplingQueue,
    error_state: *WavelengthSamplingErrorState,
    worker_index: usize,
};

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

    var queue: WavelengthSamplingQueue = .{ .len = plans.len };
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
    if (sample_count < min_parallel_wavelength_sample_count) return 1;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return @min(cpu_count, @max(@as(usize, 1), sample_count / min_parallel_wavelength_sample_count));
}

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
