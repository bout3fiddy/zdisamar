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
pub const WavelengthSamplingTable = Plan.WavelengthSamplingTable;
pub const OwnedWavelengthSampling = Plan.OwnedWavelengthSampling;

const min_parallel_wavelength_sample_count: usize = 64;
const wavelength_sampling_chunk_size: usize = 16;
const initial_side_samples_per_kernel_cap: usize = 512;
const initial_side_storage_sample_cap: usize = 1 << 20;

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
//   size: 176 B, align: 8 B
//   field storage: 169 B across 14 fields; largest: radiance_calibration=32 B, irradiance_calibration=32 B, allocator=16 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   out-of-line: scene, prepared, resolved_axis, radiance_adaptive_cache, irradiance_adaptive_cache, +5 more carry references/descriptors; referenced storage is not included in size
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 176 B (0.172 KiB); total also includes referenced storage above
const WavelengthSamplingWorker = struct {
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    can_cache_adaptive_plan: bool,
    radiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    irradiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    kernel_storage_builder: *KernelStorageBuilder,
    plans: []WavelengthSampling,
    queue: *work_partition.ChunkQueue,
    error_state: *WavelengthSamplingErrorState,
    worker_index: usize,
};

// layout(64-bit):
//   size: 64 B, align: 8 B
//   field storage: mutex=4 B, offsets_nm=16 B, weights=16 B, expected_kernel_ref_count=8 B, reserved_from_first_side_kernel=1 B; padding: 19 B
//   unused bits: 152 padding + 7 bool-storage slack = 159 bits
//   out-of-line: offsets_nm, weights carry ArrayList backing storage; referenced storage is not included in size
//   cache span: 1 cache line(s) at 64 B per line
//   count: one per wavelength sampling build
//   footprint: per instance = 64 B (0.062 KiB); total also includes referenced storage above
const KernelStorageBuilder = struct {
    mutex: std.Thread.Mutex = .{},
    offsets_nm: std.ArrayList(f64) = .empty,
    weights: std.ArrayList(f64) = .empty,
    expected_kernel_ref_count: usize = 0,
    reserved_from_first_side_kernel: bool = false,

    fn init(expected_kernel_ref_count: usize) KernelStorageBuilder {
        return .{ .expected_kernel_ref_count = expected_kernel_ref_count };
    }

    fn append(self: *KernelStorageBuilder, allocator: Allocator, kernel: *const IntegrationKernel) Error!u32 {
        const count = kernel.sample_count;
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.offsets_nm.items.len > std.math.maxInt(u32) or
            count > std.math.maxInt(u32) - self.offsets_nm.items.len)
        {
            return error.OutOfMemory;
        }
        const start: u32 = @intCast(self.offsets_nm.items.len);
        try self.ensureCapacityForSideKernel(allocator, count);
        self.offsets_nm.appendSliceAssumeCapacity(kernel.offsets_nm[0..count]);
        self.weights.appendSliceAssumeCapacity(kernel.weights[0..count]);
        return start;
    }

    fn ensureCapacityForSideKernel(self: *KernelStorageBuilder, allocator: Allocator, count: usize) Error!void {
        const required_capacity = self.offsets_nm.items.len + count;
        if (!self.reserved_from_first_side_kernel and self.expected_kernel_ref_count != 0) {
            self.reserved_from_first_side_kernel = true;
            const samples_per_kernel_hint = @min(count, initial_side_samples_per_kernel_cap);
            const raw_capacity_hint = std.math.mul(
                usize,
                self.expected_kernel_ref_count,
                samples_per_kernel_hint,
            ) catch initial_side_storage_sample_cap;
            const capacity_hint = @min(raw_capacity_hint, initial_side_storage_sample_cap);
            const reserved_capacity = @max(required_capacity, capacity_hint);
            try self.offsets_nm.ensureTotalCapacityPrecise(allocator, reserved_capacity);
            try self.weights.ensureTotalCapacityPrecise(allocator, reserved_capacity);
            return;
        }
        try self.offsets_nm.ensureUnusedCapacity(allocator, count);
        try self.weights.ensureUnusedCapacity(allocator, count);
    }

    fn deinit(self: *KernelStorageBuilder, allocator: Allocator) void {
        self.offsets_nm.deinit(allocator);
        self.weights.deinit(allocator);
        self.* = .{};
    }
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
) Error!OwnedWavelengthSampling {
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try resolved_axis.validate();
    const plans = try allocator.alloc(WavelengthSampling, sample_count);
    errdefer allocator.free(plans);
    var kernel_storage_builder = KernelStorageBuilder.init(sample_count * 2);
    defer kernel_storage_builder.deinit(allocator);
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
            &kernel_storage_builder,
            plans,
        );
    }
    const kernel_offsets_nm = try kernel_storage_builder.offsets_nm.toOwnedSlice(allocator);
    errdefer allocator.free(kernel_offsets_nm);
    const kernel_weights = try kernel_storage_builder.weights.toOwnedSlice(allocator);
    return .{
        .rows = plans,
        .kernel_offsets_nm = kernel_offsets_nm,
        .kernel_weights = kernel_weights,
    };
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
    kernel_storage_builder: *KernelStorageBuilder,
    plans: []WavelengthSampling,
) Error!void {
    const worker_count = preferredWavelengthSamplingWorkerCount(plans.len);
    if (worker_count == 1) {
        return fillWavelengthSamplingPlanRange(
            allocator,
            scene,
            prepared,
            resolved_axis,
            radiance_calibration,
            irradiance_calibration,
            can_cache_adaptive_plan,
            radiance_adaptive_cache,
            irradiance_adaptive_cache,
            kernel_storage_builder,
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
            .allocator = allocator,
            .scene = scene,
            .prepared = prepared,
            .resolved_axis = resolved_axis,
            .radiance_calibration = radiance_calibration,
            .irradiance_calibration = irradiance_calibration,
            .can_cache_adaptive_plan = can_cache_adaptive_plan,
            .radiance_adaptive_cache = radiance_adaptive_cache,
            .irradiance_adaptive_cache = irradiance_adaptive_cache,
            .kernel_storage_builder = kernel_storage_builder,
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
                worker.allocator,
                worker.scene,
                worker.prepared,
                worker.resolved_axis,
                worker.radiance_calibration,
                worker.irradiance_calibration,
                worker.can_cache_adaptive_plan,
                worker.radiance_adaptive_cache,
                worker.irradiance_adaptive_cache,
                worker.kernel_storage_builder,
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
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    can_cache_adaptive_plan: bool,
    radiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    irradiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    kernel_storage_builder: *KernelStorageBuilder,
    plans: []WavelengthSampling,
    start: usize,
    end: usize,
) Error!void {
    var integration_scratch: IntegrationKernel = undefined;
    for (start..end) |index| {
        plans[index] = try buildWavelengthSamplingPlan(
            allocator,
            scene,
            prepared,
            resolved_axis,
            radiance_calibration,
            irradiance_calibration,
            can_cache_adaptive_plan,
            radiance_adaptive_cache,
            irradiance_adaptive_cache,
            kernel_storage_builder,
            &integration_scratch,
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
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    can_cache_adaptive_plan: bool,
    radiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    irradiance_adaptive_cache: *const instrument_integration.AdaptiveKernelCache,
    kernel_storage_builder: *KernelStorageBuilder,
    integration_scratch: *IntegrationKernel,
    index: usize,
) Error!WavelengthSampling {
    const nominal_wavelength_nm = resolvedSampleAtAssumeValid(resolved_axis, index);
    if (can_cache_adaptive_plan) {
        try instrument_integration.integrationForWavelengthWithAdaptiveCacheChecked(
            scene,
            prepared,
            .radiance,
            nominal_wavelength_nm,
            radiance_adaptive_cache,
            integration_scratch,
        );
    } else {
        try instrument_integration.integrationForWavelengthChecked(
            scene,
            prepared,
            .radiance,
            nominal_wavelength_nm,
            integration_scratch,
        );
    }
    const radiance_integration = try compactIntegrationKernel(allocator, kernel_storage_builder, integration_scratch);
    if (can_cache_adaptive_plan) {
        try instrument_integration.integrationForWavelengthWithAdaptiveCacheChecked(
            scene,
            prepared,
            .irradiance,
            nominal_wavelength_nm,
            irradiance_adaptive_cache,
            integration_scratch,
        );
    } else {
        try instrument_integration.integrationForWavelengthChecked(
            scene,
            prepared,
            .irradiance,
            nominal_wavelength_nm,
            integration_scratch,
        );
    }
    const irradiance_integration = try compactIntegrationKernel(allocator, kernel_storage_builder, integration_scratch);
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

fn compactIntegrationKernel(
    allocator: Allocator,
    kernel_storage_builder: *KernelStorageBuilder,
    kernel: *const IntegrationKernel,
) Error!Plan.IntegrationKernelRef {
    var compact: Plan.IntegrationKernelRef = .{};
    if (!kernel.enabled) {
        compact.sample_count = 1;
        return compact;
    }
    if (kernel.sample_count > std.math.maxInt(u16)) return error.OutOfMemory;
    compact.sample_count = @intCast(kernel.sample_count);
    if (kernel.sample_count <= Plan.inline_integration_sample_count) {
        compact.encoding = .inline_samples;
        @memcpy(compact.inline_offsets_nm[0..kernel.sample_count], kernel.offsets_nm[0..kernel.sample_count]);
        @memcpy(compact.inline_weights[0..kernel.sample_count], kernel.weights[0..kernel.sample_count]);
        return compact;
    }
    compact.encoding = .side_samples;
    compact.side_start = try kernel_storage_builder.append(allocator, kernel);
    return compact;
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
    table: WavelengthSamplingTable,
) ![]Plan.ForwardCacheMiss {
    var seen = std.AutoHashMap(u64, void).init(allocator);
    defer seen.deinit();
    var misses = std.ArrayList(Plan.ForwardCacheMiss).empty;
    errdefer misses.deinit(allocator);

    for (table.rows) |plan| {
        const integration = &plan.radiance_integration;
        if (!integration.enabled()) {
            const key = SpectralEval.SpectralEvaluationCache.keyFor(plan.radiance_wavelength_nm);
            const entry = try seen.getOrPut(key);
            if (entry.found_existing) continue;
            try misses.append(allocator, .{
                .key = key,
                .wavelength_nm = plan.radiance_wavelength_nm,
            });
            continue;
        }
        const samples = integration.samples(table.kernel_storage);
        for (samples.offsets_nm) |offset_nm| {
            const wavelength_nm = plan.radiance_wavelength_nm + offset_nm;
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
