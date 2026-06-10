const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const calibration = @import("../spectral_math/calibration.zig");
const grid = @import("../spectral_math/grid.zig");
const SpectralEval = @import("spectral_eval.zig");
const Types = @import("types.zig");
const Plan = @import("wavelength_plan.zig");
const Storage = @import("storage.zig");
const IntegrationKernel = @import("../../implementations/instrument/types.zig").IntegrationKernel;
const instrument_integration = @import("../../implementations/instrument/integration.zig");
const Telemetry = @import("../../instrumentation/telemetry.zig");
const Trace = @import("../../instrumentation/trace.zig");
const work_partition = @import("../../work_partition.zig");

const Allocator = std.mem.Allocator;
const Error = Storage.Error;

// wavelength_sampling.zig -----------------------------------------------------------------------------------------------|
// Builds the retained sampling plan that maps nominal product wavelengths to high-resolution radiance and                |
// irradiance samples. This is the bridge between instrument-response kernels and the dense LABOS miss plan: once         |
// built, simulation can gather offsets/weights by row index without recomputing response models.                         |
//                                                                                                                        |
// called by                                                                                                              |
//   simulate.zig when a ProductStorage wavelength-plan cache is cold or invalid. warmProductWorkspace takes the          |
//   same route to move first-use wavelength planning out of the next product run.                                        |
//                                                                                                                        |
// route map                                                                                                              |
//   buildWavelengthSampling -> allocate WavelengthSampling rows, prepare optional adaptive caches, fill rows,            |
//                              and move side arrays into OwnedWavelengthSampling                                         |
//   buildWavelengthSamplingPlan -> one nominal row -> radiance kernel + irradiance kernel + channel shifts               |
//   compactIntegrationKernel -> disabled direct sample, inline five-sample kernel, or side-array kernel ref              |
//   buildForwardMissPlan    -> deduplicate radiance wavelengths into dense forward misses and row-local indexes          |
//                                                                                                                        |
// storage                                                                                                                |
//   WavelengthSampling is the retained row. Small kernels are copied inline; larger kernels append offsets and           |
//   weights into shared side arrays through KernelStorageBuilder. The side arrays are built under a mutex because        |
//   row fill can run in worker chunks.                                                                                   |
//                                                                                                                        |
// hot path                                                                                                               |
//   Planning runs once per cache miss, not once per LABOS wavelength. It still sits on the product hot path, so          |
//   workers reuse one 32 KiB IntegrationKernel scratch per chunk, adaptive interval caches are prepared once per         |
//   channel, and direct row indexes avoid hash lookups during nominal-row gather.                                        |
//                                                                                                                        |
// math names                                                                                                             |
//   lambda_i        : nominal product wavelength                                                                         |
//   lambda_channel  : lambda_i plus radiance/irradiance calibration shift                                                |
//   lambda_ij       : lambda_channel + integration offset_j                                                              |
//   y_i             : sum_j weight_ij * y(lambda_ij)                                                                     |
// -----------------------------------------------------------------------------------------------------------------------|

pub const WavelengthSampling = Plan.WavelengthSampling;
pub const WavelengthSamplingTable = Plan.WavelengthSamplingTable;
pub const OwnedWavelengthSampling = Plan.OwnedWavelengthSampling;

const min_parallel_wavelength_sample_count: usize = 64;
const wavelength_sampling_chunk_size: usize = 16;
const initial_side_samples_per_kernel_cap: usize = 512;
const initial_side_storage_sample_cap: usize = 1 << 20;

// WavelengthSamplingErrorState ------------------------------------------------------------------------------------------|
// Shared first-error slot for parallel wavelength-plan workers.                                                          |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 24 B (0.023 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] mutex   : std.Thread.Mutex                                                                                    |
// [16..17] err     : ?Error                                                                                              |
// [18..23] padding : 6 B                                                                                                 |
//                                                                                                                        |
// unused bits: 48 padding + 0 bool-storage slack = 48 bits                                                               |
// footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count                                 |
const WavelengthSamplingErrorState = struct {
    mutex: std.Thread.Mutex = .{},
    err: ?Error = null,

    fn store(self: *WavelengthSamplingErrorState, err: Error) void {
        // WavelengthSamplingErrorState.store ----------------------------------------------------------------------------|
        // Record the first worker error while allowing other sampling workers to finish or observe the same              |
        // shared state.                                                                                                  |
        // ---------------------------------------------------------------------------------------------------------------|

        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.err == null) self.err = err;
    }
};

// WavelengthSamplingWorker ----------------------------------------------------------------------------------------------|
// Worker context for filling a static range or queue of wavelength sampling rows.                                        |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 176 B (0.172 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0.. 15] allocator                  : Allocator                                                                      |
// [ 16.. 23] scene                      : *const Scene                                                                   |
// [ 24.. 31] prepared                   : *const OpticsPreparation.PreparedOpticalState                                  |
// [ 32.. 39] resolved_axis              : *const grid.ResolvedAxis                                                       |
// [ 40.. 71] radiance_calibration       : calibration.Calibration                                                        |
// [ 72..103] irradiance_calibration     : calibration.Calibration                                                        |
// [104..111] radiance_adaptive_cache    : *const instrument_integration.AdaptiveKernelCache                              |
// [112..119] irradiance_adaptive_cache  : *const instrument_integration.AdaptiveKernelCache                              |
// [120..127] kernel_storage_builder     : *KernelStorageBuilder                                                          |
// [128..143] plans                      : []WavelengthSampling                                                           |
// [144..151] queue                      : *work_partition.ChunkQueue                                                     |
// [152..159] error_state                : *WavelengthSamplingErrorState                                                  |
// [160..167] worker_index               : usize                                                                          |
// [168..168] can_cache_adaptive_plan    : bool                                                                           |
// [169..175] padding                    : 7 B                                                                            |
//                                                                                                                        |
// pointer and slice fields carry referenced storage not included in the 176 B struct size.                               |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                               |
// cache span: 3 cache lines at 64 B per line                                                                             |
// footprint: per instance = 176 B (0.172 KiB); total also includes referenced storage above                              |
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

// KernelStorageBuilder --------------------------------------------------------------------------------------------------|
// Temporary side-array builder for large integration kernels.                                                            |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 80 B (0.078 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] mutex                           : std.Thread.Mutex                                                            |
// [16..39] offsets_nm                      : std.ArrayList(f64)                                                          |
// [40..63] weights                         : std.ArrayList(f64)                                                          |
// [64..71] expected_kernel_ref_count       : usize                                                                       |
// [72..72] reserved_from_first_side_kernel : bool                                                                        |
// [73..79] padding                         : 7 B                                                                         |
//                                                                                                                        |
// offsets_nm and weights carry ArrayList backing storage not included in the 80 B struct size.                           |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                               |
// cache span: 2 cache lines at 64 B per line                                                                             |
// footprint: per instance = 80 B (0.078 KiB); total also includes referenced storage above                               |
const KernelStorageBuilder = struct {
    mutex: std.Thread.Mutex = .{},
    offsets_nm: std.ArrayList(f64) = .empty,
    weights: std.ArrayList(f64) = .empty,
    expected_kernel_ref_count: usize = 0,
    reserved_from_first_side_kernel: bool = false,

    fn init(expected_kernel_ref_count: usize) KernelStorageBuilder {
        // KernelStorageBuilder.init -------------------------------------------------------------------------------------|
        // Start side-storage collection with a hint for how many large kernel references may appear.                     |
        // ---------------------------------------------------------------------------------------------------------------|

        return .{ .expected_kernel_ref_count = expected_kernel_ref_count };
    }

    fn append(self: *KernelStorageBuilder, allocator: Allocator, kernel: *const IntegrationKernel) Error!u32 {
        // KernelStorageBuilder.append -----------------------------------------------------------------------------------|
        // Append one large integration kernel into shared side arrays and return its starting index. The                 |
        // mutex protects ArrayList growth because sampling rows may be built by several workers.                         |
        // ---------------------------------------------------------------------------------------------------------------|

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
        // KernelStorageBuilder.ensureCapacityForSideKernel --------------------------------------------------------------|
        // Reserve side-array capacity. The first large kernel uses a bounded bulk hint to avoid many reallocs            |
        // without reserving unbounded memory for very large adaptive plans.                                              |
        // ---------------------------------------------------------------------------------------------------------------|

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
        // KernelStorageBuilder.deinit -----------------------------------------------------------------------------------|
        // Release temporary side-storage builders after their arrays have been moved into OwnedWavelengthSampling.       |
        // ---------------------------------------------------------------------------------------------------------------|

        self.offsets_nm.deinit(allocator);
        self.weights.deinit(allocator);
        self.* = .{};
    }
};

pub fn buildWavelengthSampling(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
) Error!OwnedWavelengthSampling {
    // buildWavelengthSampling -------------------------------------------------------------------------------------------|
    // Build one reusable wavelength plan for all nominal output samples. Radiance and irradiance have                    |
    // separate channel calibration and instrument-response kernels, but they share the same nominal axis.                |
    //                                                                                                                    |
    // steps                                                                                                              |
    //   1. allocate one WavelengthSampling row per output wavelength                                                     |
    //   2. prepare adaptive instrument-kernel caches when line-list data can drive them                                  |
    //   3. fill rows, possibly in parallel                                                                               |
    //   4. move large-kernel side arrays into the owned plan                                                             |
    // -------------------------------------------------------------------------------------------------------------------|

    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try resolved_axis.validate();
    const plans = try allocator.alloc(WavelengthSampling, sample_count);
    errdefer allocator.free(plans);
    var kernel_storage_builder = KernelStorageBuilder.init(sample_count * 2);
    defer kernel_storage_builder.deinit(allocator);
    const can_cache_adaptive_plan = prepared.spectroscopy_lines != null;
    var radiance_adaptive_cache: instrument_integration.AdaptiveKernelCache = .{};
    var irradiance_adaptive_cache: instrument_integration.AdaptiveKernelCache = .{};
    if (can_cache_adaptive_plan) {

        // instrumentation: trace zone: adaptive kernel cache ----------------------------------------------------------- |
        // captures: adaptive kernel cache preparation                                                                    |
        // why: measures reusable instrument-response setup.                                                              |
        const zone = Trace.staticZone(@src(), "wavelength_sampling.prepare_adaptive_cache");
        defer zone.end();
        // end instrumentation: trace zone: adaptive kernel cache ------------------------------------------------------- |

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

        // instrumentation: trace zone: wavelength sampling loop -------------------------------------------------------- |
        // captures: wavelength sampling plan fill                                                                        |
        // why: measures output-grid expansion into integration samples.                                                  |
        const zone = Trace.staticZone(@src(), "wavelength_sampling.sample_loop");
        defer zone.end();
        // end instrumentation: trace zone: wavelength sampling loop ---------------------------------------------------- |

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
    recordWavelengthSamplingPlan(plans, kernel_offsets_nm.len);
    return .{
        .rows = plans,
        .kernel_offsets_nm = kernel_offsets_nm,
        .kernel_weights = kernel_weights,
    };
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
    kernel_storage_builder: *KernelStorageBuilder,
    plans: []WavelengthSampling,
) Error!void {
    // fillWavelengthSamplingPlans ---------------------------------------------------------------------------------------|
    // Fill all plan rows either on the current thread or across worker chunks when the output grid is large.             |
    // -------------------------------------------------------------------------------------------------------------------|

    // Keep small output grids single-threaded and use the shared work-partition threshold for larger grids.
    const worker_count = work_partition.preferredWorkerCount(plans.len, min_parallel_wavelength_sample_count);
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

fn wavelengthSamplingWorkerMain(worker: *WavelengthSamplingWorker) void {
    // wavelengthSamplingWorkerMain --------------------------------------------------------------------------------------|
    // Worker loop for plan-row construction. Each worker pulls output-index chunks and writes those rows                 |
    // directly into the shared plans array.                                                                              |
    // -------------------------------------------------------------------------------------------------------------------|

    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-sampling-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-sampling-worker";

    // instrumentation: trace thread label: wavelength sampling worker -------------------------------------------------- |
    // captures: wavelength-sampling worker identity                                                                      |
    // why: makes parallel plan-fill lanes separable in timeline traces.                                                  |
    Trace.setThreadName(thread_name);
    // end instrumentation: trace thread label: wavelength sampling worker ---------------------------------------------- |

    // instrumentation: trace zone: wavelength sampling worker ---------------------------------------------------------- |
    // captures: worker chunk timing and chunk sizes                                                                      |
    // why: inspects parallel wavelength-plan load balance.                                                               |
    const worker_zone = Trace.staticZone(@src(), "wavelength_sampling.worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();
    // end instrumentation: trace zone: wavelength sampling worker ------------------------------------------------------ |

    while (worker.queue.next()) |chunk| {
        {

            // instrumentation: trace zone: wavelength sampling chunk --------------------------------------------------- |
            // captures: wavelength-sampling chunk wall time and row count                                                |
            // why: reveals chunk imbalance while filling integration plans.                                              |
            const chunk_zone = Trace.deepStaticZone(@src(), "wavelength_sampling.chunk");
            chunk_zone.value(@intCast(chunk.end - chunk.start));
            defer chunk_zone.end();
            // end instrumentation: trace zone: wavelength sampling chunk ----------------------------------------------- |

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
    // fillWavelengthSamplingPlanRange -----------------------------------------------------------------------------------|
    // Fill one contiguous output-index range. The IntegrationKernel scratch is reused for radiance and                   |
    // irradiance so each row does not allocate a temporary kernel.                                                       |
    // -------------------------------------------------------------------------------------------------------------------|

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
    // buildWavelengthSamplingPlan ---------------------------------------------------------------------------------------|
    // Build the radiance and irradiance sampling description for one nominal output wavelength.                          |
    //                                                                                                                    |
    // math                                                                                                               |
    //   lambda_i          = nominal output wavelength                                                                    |
    //   lambda_radiance   = lambda_i + radiance wavelength shift                                                         |
    //   lambda_irradiance = lambda_i + irradiance wavelength shift                                                       |
    //   sample lambda_ij  = lambda_channel + offset_ij                                                                   |
    //                                                                                                                    |
    // integration rows                                                                                                   |
    //   offset_ij and weight_ij come from the channel instrument response at lambda_i. The channel shift is              |
    //   applied to the center wavelength stored in the plan, then offsets are added later when building misses.          |
    // -------------------------------------------------------------------------------------------------------------------|

    const nominal_wavelength_nm = if (resolved_axis.explicit_wavelengths_nm.len != 0)
        resolved_axis.explicit_wavelengths_nm[index]
    else sample: {
        const sample_count = resolved_axis.base.sample_count;

        // math: lambda_i = lambda_start + i * (lambda_end - lambda_start) / (N - 1).
        const step = (resolved_axis.base.end_nm - resolved_axis.base.start_nm) /
            @as(f64, @floatFromInt(sample_count - 1));
        break :sample resolved_axis.base.start_nm + step * @as(f64, @floatFromInt(index));
    };

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
    // compactIntegrationKernel ------------------------------------------------------------------------------------------|
    // Convert an instrument IntegrationKernel into the compact row representation used by WavelengthSampling.            |
    // Disabled kernels become direct samples, small kernels are stored inline, and larger kernels use side               |
    // storage.                                                                                                           |
    // -------------------------------------------------------------------------------------------------------------------|

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

fn recordWavelengthSamplingPlan(plans: []const WavelengthSampling, side_sample_count: usize) void {
    // recordWavelengthSamplingPlan --------------------------------------------------------------------------------------|
    // Emit one compact telemetry row about sampling fan-out when telemetry is compiled in. Product builds                |
    // skip this work entirely.                                                                                           |
    // -------------------------------------------------------------------------------------------------------------------|

    // instrumentation: calculation telemetry: wavelength sampling plan ------------------------------------------------- |
    // captures: integrated rows, sample counts, and side samples                                                         |
    // why: quantifies spectral sampling work before forward misses.                                                      |
    if (!Telemetry.enabled) return;
    var radiance_integrated_rows: usize = 0;
    var irradiance_integrated_rows: usize = 0;
    var radiance_sample_count: usize = 0;
    var irradiance_sample_count: usize = 0;
    var max_kernel_sample_count: usize = 0;

    for (plans) |plan| {
        const radiance_count = plan.radiance_integration.activeSampleCount();
        const irradiance_count = plan.irradiance_integration.activeSampleCount();
        if (plan.radiance_integration.enabled()) radiance_integrated_rows += 1;
        if (plan.irradiance_integration.enabled()) irradiance_integrated_rows += 1;
        radiance_sample_count += radiance_count;

        irradiance_sample_count += irradiance_count;
        max_kernel_sample_count = @max(max_kernel_sample_count, radiance_count);
        max_kernel_sample_count = @max(max_kernel_sample_count, irradiance_count);
    }

    Telemetry.wavelengthSamplingPlan(
        plans.len,
        radiance_integrated_rows,
        irradiance_integrated_rows,
        radiance_sample_count,
        irradiance_sample_count,
        side_sample_count,
        max_kernel_sample_count,
    );
    // end instrumentation: calculation telemetry: wavelength sampling plan --------------------------------------------- |

}

pub fn buildForwardMissPlan(
    allocator: Allocator,
    table: WavelengthSamplingTable,
) !Plan.OwnedForwardMissPlan {
    // buildForwardMissPlan ----------------------------------------------------------------------------------------------|
    // Deduplicate radiance integration wavelengths and build direct indexes into the dense forward-results               |
    // array. Irradiance samples do not enter this plan because they are resolved through the solar cache.                |
    //                                                                                                                    |
    // row contract                                                                                                       |
    //   rows[i].start points into sample_indices. rows[i]'s radiance_integration.activeSampleCount() gives               |
    //   the row length. sample_indices stores dense indexes into misses/results, not wavelengths.                        |
    //                                                                                                                    |
    // math                                                                                                               |
    //   direct row     : one miss at lambda_radiance_i                                                                   |
    //   integrated row : one miss for each lambda_radiance_i + offset_ij                                                 |
    // -------------------------------------------------------------------------------------------------------------------|

    var miss_indices = std.AutoHashMap(u64, u32).init(allocator);
    defer miss_indices.deinit();
    var misses = std.ArrayList(Plan.ForwardCacheMiss).empty;
    errdefer misses.deinit(allocator);
    var sample_indices = std.ArrayList(u32).empty;
    errdefer sample_indices.deinit(allocator);
    var radiance_sample_index_count: usize = 0;
    for (table.rows) |plan| {
        radiance_sample_index_count += plan.radiance_integration.activeSampleCount();
    }
    try sample_indices.ensureTotalCapacityPrecise(allocator, radiance_sample_index_count);
    const rows = try allocator.alloc(Plan.ForwardSampleIndexRef, table.rows.len);
    errdefer allocator.free(rows);

    for (table.rows, rows) |plan, *row| {
        const integration = &plan.radiance_integration;
        const start = sample_indices.items.len;
        if (!integration.enabled()) {
            try appendForwardMissIndex(allocator, &miss_indices, &misses, &sample_indices, plan.radiance_wavelength_nm);
            row.* = .{
                .start = try castForwardSampleIndexStart(start),
            };
            continue;
        }
        const samples = integration.samples(table.kernel_storage);
        for (samples.offsets_nm) |offset_nm| {
            try appendForwardMissIndex(
                allocator,
                &miss_indices,
                &misses,
                &sample_indices,
                plan.radiance_wavelength_nm + offset_nm,
            );
        }
        row.* = .{
            .start = try castForwardSampleIndexStart(start),
        };
    }

    // instrumentation: calculation telemetry: forward miss plan -------------------------------------------------------- |
    // captures: sample-index reuse vs unique misses                                                                      |
    // why: measures how much dense forward work integration actually needs.                                              |
    Telemetry.forwardMissPlan(table.rows.len, sample_indices.items.len, misses.items.len);
    // end instrumentation: calculation telemetry: forward miss plan ---------------------------------------------------- |

    return .{
        .rows = rows,
        .sample_indices = try sample_indices.toOwnedSlice(allocator),
        .misses = try misses.toOwnedSlice(allocator),
    };
}

fn castForwardSampleIndexStart(start: usize) !u32 {
    // castForwardSampleIndexStart ---------------------------------------------------------------------------------------|
    // Store sample-index starts as u32 to keep each row compact. Oversized plans fail before a truncated                 |
    // start can be stored.                                                                                               |
    // -------------------------------------------------------------------------------------------------------------------|

    if (start > std.math.maxInt(u32)) return error.OutOfMemory;
    return @intCast(start);
}

fn appendForwardMissIndex(
    allocator: Allocator,
    miss_indices: *std.AutoHashMap(u64, u32),
    misses: *std.ArrayList(Plan.ForwardCacheMiss),
    sample_indices: *std.ArrayList(u32),
    wavelength_nm: f64,
) !void {
    // appendForwardMissIndex --------------------------------------------------------------------------------------------|
    // Append the dense result index for one radiance sample. Reused wavelengths append an existing miss index;           |
    // new wavelengths append both a ForwardCacheMiss and its index.                                                      |
    // -------------------------------------------------------------------------------------------------------------------|

    const key = SpectralEval.SpectralEvaluationCache.keyFor(wavelength_nm);

    if (miss_indices.get(key)) |miss_index| {
        sample_indices.appendAssumeCapacity(miss_index);
        return;
    }
    if (misses.items.len > std.math.maxInt(u32)) return error.OutOfMemory;
    const miss_index: u32 = @intCast(misses.items.len);

    const entry = try miss_indices.getOrPut(key);
    if (entry.found_existing) {
        sample_indices.appendAssumeCapacity(entry.value_ptr.*);
        return;
    }
    misses.append(allocator, .{
        .key = key,
        .wavelength_nm = wavelength_nm,
    }) catch |err| {
        _ = miss_indices.remove(key);

        return err;
    };
    entry.value_ptr.* = miss_index;
    sample_indices.appendAssumeCapacity(miss_index);
}
