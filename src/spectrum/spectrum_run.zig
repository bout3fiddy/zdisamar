const std = @import("std");
const builtin = @import("builtin");

const instrument_average = @import("instrument_average.zig");
const jacobian_states = @import("../transport/jacobian_states.zig");
const radiance_results = @import("radiance_results.zig");
const radiance_wavelengths = @import("radiance_wavelengths.zig");
const sampling_table = @import("sampling_table.zig");
const solar_lookup = @import("solar_lookup.zig");
const solar_irradiance_memory = @import("../cache/solar_irradiance_memory.zig");
const solar_table = @import("../setup/solar_table.zig");
const transport_worker_memory = @import("../cache/transport_worker_memory.zig");
const controls = @import("../transport/controls.zig");
const Trace = @import("../instrumentation/trace.zig");

pub const Error = error{
    ShapeMismatch,
};

// spectrum_run.zig -----------------------------------------------------------------------------------------   |
// Spectrum-level worker policy for high-resolution radiance prefetch.                                          |
//                                                                                                              |
// provenance                                                                                                   |
//   Ports the scheduling and first-error contracts from main:                                                  |
//   `src/forward_model/work_partition.zig`,                                                                    |
//   `src/forward_model/first_worker_error_state.zig`, and                                                      |
//   `src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig`.                                 |
//                                                                                                              |
// boundary                                                                                                     |
//   This file owns only spectrum orchestration policy: worker ranges, chunk draining, worker-count limits,     |
//   and first worker error capture. It stores no scene, transport controls, optical properties, solar data,    |
//   or profile-line values. Later radiance prefetch code passes those physics inputs explicitly.               |
//                                                                                                              |
// route                                                                                                        |
//   SpectrumSamplingTable -> RadianceWavelengthList -> static radiance ranges or pooled chunks -> dense        |
//   RadianceResult rows -> nominal gather and instrument averaging.                                            |
//                                                                                                              |
// allocation                                                                                                   |
//   The helpers here allocate nothing. Thread owners and worker-local transport memory live at the call site.  |
// ------------------------------------------------------------------------------------------------------------ |

pub const max_workers: usize = 64;
pub const worker_limit_env = "ZDISAMAR_WORKER_LIMIT";
pub const min_parallel_radiance_count: usize = 32;
pub const radiance_prefetch_chunk_size: usize = 8;
pub const radiance_prefetch_pooled_chunk_size: usize = 8;

// Range -----------------------------------------------------------------------------------------------------  |
// Half-open item range owned by one spectrum worker or one queue claim.                                        |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 16 B (0.016 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] start : usize                                                                                       |
// [ 8..15] end   : usize                                                                                       |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// footprint: per instance = 16 B; stack return value                                                           |
pub const Range = struct {
    start: usize,
    end: usize,

    pub fn len(self: Range) usize {
        // Range.len ----------------------------------------------------------------------------------------   |
        // Return the number of items in this half-open worker range.                                           |
        // ---------------------------------------------------------------------------------------------------- |
        return self.end - self.start;
    }
};
// ------------------------------------------------------------------------------------------------------------ |

// ChunkQueue ------------------------------------------------------------------------------------------------  |
// Mutex-protected dynamic chunk dispenser for reusable pooled workers.                                         |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 40 B (0.039 KiB), align: 8 B in Debug; 32 B (0.031 KiB), align: 8 B in optimized builds                |
//                                                                                                              |
// memory, Debug                                                                                                |
// [ 0..15] mutex      : Thread.Mutex                                                                           |
// [16..23] next_index : usize                                                                                  |
// [24..31] item_count : usize                                                                                  |
// [32..39] chunk_size : usize                                                                                  |
//                                                                                                              |
// memory, optimized                                                                                            |
// [ 0.. 7] next_index : usize                                                                                  |
// [ 8..15] item_count : usize                                                                                  |
// [16..23] chunk_size : usize                                                                                  |
// [24..27] mutex      : Thread.Mutex                                                                           |
// [28..31] padding    : 4 B                                                                                    |
//                                                                                                              |
// footprint: per instance = 40 B Debug or 32 B optimized; one queue per pooled radiance-prefetch batch         |
pub const ChunkQueue = struct {
    mutex: std.Thread.Mutex = .{},
    next_index: usize = 0,
    item_count: usize,
    chunk_size: usize,

    pub fn init(item_count: usize, chunk_size: usize) ChunkQueue {
        // ChunkQueue.init ----------------------------------------------------------------------------------   |
        // Build a queue over `item_count` items. A zero chunk would stall all workers, so it is rejected by    |
        // assertion exactly like the old worker policy.                                                        |
        // ---------------------------------------------------------------------------------------------------- |
        std.debug.assert(chunk_size != 0);
        return .{
            .item_count = item_count,
            .chunk_size = chunk_size,
        };
    }

    pub fn next(self: *ChunkQueue) ?Range {
        // ChunkQueue.next ----------------------------------------------------------------------------------   |
        // Hand out the next contiguous item range under a short mutex.                                         |
        //                                                                                                      |
        // math                                                                                                 |
        //   start = next_index                                                                                 |
        //   end   = min(start + chunk_size, item_count)                                                        |
        // ---------------------------------------------------------------------------------------------------- |
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.next_index >= self.item_count) return null;

        const start = self.next_index;
        const end = @min(start + self.chunk_size, self.item_count);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};
// ------------------------------------------------------------------------------------------------------------ |

pub fn FirstWorkerErrorState(comptime ErrorSet: type) type {
    // FirstWorkerErrorState --------------------------------------------------------------------------------   |
    // Shared first-error slot for parallel radiance workers. Workers write only on failure, so the mutex       |
    // guards the cold path while the successful hot loop does no cross-worker coordination.                    |
    //                                                                                                          |
    // layout(64-bit, ErrorSet with one or more errors)                                                         |
    // size: 24 B (0.023 KiB), align: 8 B in Debug; 8 B (0.008 KiB), align: 4 B in optimized builds             |
    //                                                                                                          |
    // memory, Debug                                                                                            |
    // [ 0..15] mutex   : std.Thread.Mutex                                                                      |
    // [16..17] err     : ?ErrorSet                                                                             |
    // [18..23] padding : 6 B                                                                                   |
    //                                                                                                          |
    // memory, optimized                                                                                        |
    // [0..3] mutex : std.Thread.Mutex                                                                          |
    // [4..5] err   : ?ErrorSet                                                                                 |
    // [6..7] padding : 2 B                                                                                     |
    // -------------------------------------------------------------------------------------------------------- |
    return struct {
        mutex: std.Thread.Mutex = .{},
        err: ?ErrorSet = null,

        pub fn store(self: *@This(), err: ErrorSet) void {
            // FirstWorkerErrorState.store ------------------------------------------------------------------   |
            // Preserve the first observed worker error. Later worker failures leave the original cause in      |
            // place so joined callers return the earliest failure deterministically.                           |
            // ------------------------------------------------------------------------------------------------ |
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.err == null) self.err = err;
        }
    };
}

pub fn staticRange(item_count: usize, worker_count: usize, worker_index: usize) Range {
    // staticRange -------------------------------------------------------------------------------------------  |
    // Compute deterministic ownership for one direct-spawn radiance worker.                                    |
    //                                                                                                          |
    // math                                                                                                     |
    //   start = floor(worker_index * item_count / worker_count)                                                |
    //   end   = floor((worker_index + 1) * item_count / worker_count)                                          |
    //                                                                                                          |
    // reason                                                                                                   |
    //   The full exact-wavelength list is known before prefetch starts, so static ranges prevent worker        |
    //   startup order from deciding who drains expensive wavelengths.                                          |
    // -------------------------------------------------------------------------------------------------------- |
    std.debug.assert(worker_count != 0);
    std.debug.assert(worker_index < worker_count);
    return .{
        .start = worker_index * item_count / worker_count,
        .end = (worker_index + 1) * item_count / worker_count,
    };
}

pub fn nextStaticChunk(start_index: *usize, end_index: usize) ?Range {
    // nextStaticChunk ---------------------------------------------------------------------------------------  |
    // Drain a worker's static range in the same chunk shape as the old high-resolution prefetch loop.          |
    // -------------------------------------------------------------------------------------------------------- |
    if (start_index.* >= end_index) return null;
    const chunk = Range{
        .start = start_index.*,
        .end = @min(start_index.* + radiance_prefetch_chunk_size, end_index),
    };
    start_index.* = chunk.end;
    return chunk;
}

pub fn prefetchRadianceRowsSingleWorker(
    comptime ComputeState: type,
    comptime ComputeError: type,
    wavelengths: radiance_wavelengths.RadianceWavelengthList,
    results: []radiance_results.RadianceResult,
    worker_memory: *transport_worker_memory.TransportWorkerMemory,
    compute_state: *ComputeState,
    comptime compute: fn (
        *ComputeState,
        f64,
        usize,
        *transport_worker_memory.TransportWorkerMemory,
    ) ComputeError!radiance_results.RadianceResult,
) (Error || ComputeError)!void {
    // prefetchRadianceRowsSingleWorker -------------------------------------------------------------------     |
    // Fill dense high-resolution radiance rows for one worker-local memory owner.                              |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports the single-worker loop shape from main:                                                          |
    //   `src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig`                              |
    //   `prefetchForwardSamples` and `computeForwardSampleAtWavelengthWithScratch`.                            |
    //                                                                                                          |
    // row contract                                                                                             |
    //   results[index] corresponds to wavelengths.wavelengths[index]. Later nominal gathers read these rows    |
    //   through RadianceSampleIndexRef/sample_indices, so this function must not reorder the dense array.      |
    //                                                                                                          |
    // memory                                                                                                   |
    //   The worker memory is caller-owned and reusable. The compute callback receives explicit wavelength      |
    //   and memory inputs; no scene, request, or generic cache is stored here.                                 |
    // ---------------------------------------------------------------------------------------------------------|
    if (results.len != wavelengths.wavelengths.len) return error.ShapeMismatch;
    if (wavelengths.wavelengths.len == 0) return;

    // instrumentation: trace counter: high-resolution radiance rows ------------------------------------------ |
    // captures: unique exact radiance wavelengths evaluated by this prefetch pass                              |
    // why: distinguishes fewer transport solves from cheaper work per solve.                                   |
    Trace.plotU("high_resolution_misses", @intCast(wavelengths.wavelengths.len));
    // end instrumentation: trace counter: high-resolution radiance rows -------------------------------------- |

    var start_index: usize = 0;
    while (nextStaticChunk(&start_index, wavelengths.wavelengths.len)) |chunk| {
        try prefetchRadianceChunk(
            ComputeState,
            ComputeError,
            wavelengths.wavelengths,
            results,
            chunk,
            worker_memory,
            compute_state,
            compute,
        );
    }
}

fn prefetchRadianceChunk(
    comptime ComputeState: type,
    comptime ComputeError: type,
    wavelengths: []const radiance_wavelengths.RadianceWavelength,
    results: []radiance_results.RadianceResult,
    chunk: Range,
    worker_memory: *transport_worker_memory.TransportWorkerMemory,
    compute_state: *ComputeState,
    comptime compute: fn (
        *ComputeState,
        f64,
        usize,
        *transport_worker_memory.TransportWorkerMemory,
    ) ComputeError!radiance_results.RadianceResult,
) ComputeError!void {
    // prefetchRadianceChunk --------------------------------------------------------------------------------   |
    // Compute one contiguous chunk from the dense exact-wavelength list.                                       |
    // ---------------------------------------------------------------------------------------------------------|
    const worker_index: usize = 0;

    // instrumentation: trace zone: radiance prefetch chunk --------------------------------------------------- |
    // captures: one single-worker prefetch chunk size and wall time                                            |
    // why: keeps dense radiance prefetch work visible separately from nominal gather loops.                    |
    const chunk_zone = Trace.deepStaticZone(@src(), "radiance_prefetch.chunk");
    chunk_zone.value(@intCast(chunk.len()));
    defer chunk_zone.end();
    // end instrumentation: trace zone: radiance prefetch chunk ----------------------------------------------- |

    for (chunk.start..chunk.end) |index| {
        results[index] = try compute(
            compute_state,
            wavelengths[index].wavelength_nm,
            worker_index,
            worker_memory,
        );
    }
}

pub fn gatherProductRows(
    solve_config: controls.SolveConfig,
    table: sampling_table.SpectrumSamplingTable,
    wavelengths: radiance_wavelengths.RadianceWavelengthList,
    dense_radiance: []const radiance_results.RadianceResult,
    solar: solar_table.SolarTable,
    solar_memory: *solar_irradiance_memory.SolarIrradianceMemory,
    out_wavelengths_nm: []f64,
    out_raw_radiance: []radiance_results.RadianceResult,
    out_raw_irradiance: []f64,
) (Error || radiance_results.Error || solar_lookup.Error || std.mem.Allocator.Error)!void {
    // gatherProductRows -----------------------------------------------------------------------------------    |
    // Gather nominal product rows after dense radiance prefetch.                                               |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports the cache-integration sections of old main:                                                      |
    //   `src/forward_model/instrument_grid/grid_calculation/simulate.zig` `fillRadianceSamples` and            |
    //   `fillIrradianceSamples`, delegating the scalar math to `radiance_results.zig` and `solar_lookup.zig`.  |
    //                                                                                                          |
    // data flow                                                                                                |
    //   sampling row -> exact radiance sample indexes -> dense radiance rows -> raw product radiance           |
    //   sampling row -> exact solar lookup/cache                     -> raw product irradiance                 |
    //                                                                                                          |
    // memory                                                                                                   |
    //   Output slices are caller-owned. Solar memory is reset and reserved before the row loop so exact-key    |
    //   inserts do not allocate while nominal rows are being gathered.                                         |
    // ---------------------------------------------------------------------------------------------------------|
    const row_count = table.rows.len;
    const shape_matches = wavelengths.rows.len == row_count and
        out_wavelengths_nm.len == row_count and
        out_raw_radiance.len == row_count and
        out_raw_irradiance.len == row_count;
    if (!shape_matches) return error.ShapeMismatch;

    solar_memory.reset();
    try solar_lookup.reserveIrradianceMemory(solar_memory, table);

    // instrumentation: trace zone: product row gather -------------------------------------------------------- |
    // captures: nominal-row radiance and irradiance gather wall time                                           |
    // why: separates dense transport prefetch from product-grid sampling work.                                 |
    const zone = Trace.staticZone(@src(), "spectrum.product_row_gather");
    zone.value(@intCast(row_count));
    defer zone.end();
    // end instrumentation: trace zone: product row gather ---------------------------------------------------- |

    for (table.rows, 0..) |row, index| {
        out_wavelengths_nm[index] = row.nominal_wavelength_nm;
        out_raw_radiance[index] = try radiance_results.integratePrefetchedRadianceAtNominal(
            solve_config,
            dense_radiance,
            wavelengths.rows[index],
            wavelengths.sample_indices,
            &row.radiance_integration,
            table.kernel_storage,
        );
        out_raw_irradiance[index] = try solar_lookup.integrateIrradianceAtNominalAssumeCapacity(
            solar,
            solar_memory,
            row.irradiance_wavelength_nm,
            &row.irradiance_integration,
            table.kernel_storage,
        );
    }
}

pub fn postprocessAndAssembleProductRows(
    solve_config: controls.SolveConfig,
    uses_integrated_radiance_sampling: bool,
    uses_integrated_irradiance_sampling: bool,
    radiance_calibration: instrument_average.Calibration,
    irradiance_calibration: instrument_average.Calibration,
    radiance_slit_kernel: []const f64,
    irradiance_slit_kernel: []const f64,
    solar_cosine: f64,
    raw_radiance: []const radiance_results.RadianceResult,
    raw_irradiance: []const f64,
    out_radiance: []radiance_results.RadianceResult,
    out_irradiance: []f64,
    out_reflectance: []f64,
    out_jacobian: []jacobian_states.Vector,
) (Error || instrument_average.Error)!instrument_average.ReflectanceAssemblySummary {
    // postprocessAndAssembleProductRows ------------------------------------------------------------------     |
    // Apply the old product-grid postprocess order and final reflectance assembly to caller-owned rows.        |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports the orchestration order from main: `simulate.zig` `fillRadianceSamples`,                         |
    //   `fillIrradianceSamples`, `processJacobianSamples`, and `assembleReflectance`. The scalar               |
    //   convolution, calibration, and reflectance math stays in `instrument_average.zig`.                      |
    //                                                                                                          |
    // data flow                                                                                                |
    //   raw product radiance     -> radiance convolution/calibration plus active Jacobian lanes                |
    //   raw product irradiance   -> irradiance convolution/calibration                                         |
    //   calibrated product rows  -> reflectance and optional reflectance Jacobian rows                         |
    //                                                                                                          |
    // memory                                                                                                   |
    //   Every slice is caller-owned. Non-integrated convolution overlap guards are enforced by                 |
    //   `instrument_average`; this wrapper only proves that all product-row slices describe the same count.    |
    // ---------------------------------------------------------------------------------------------------------|
    const row_count = raw_radiance.len;
    const shape_matches = raw_irradiance.len == row_count and
        out_radiance.len == row_count and
        out_irradiance.len == row_count and
        out_reflectance.len == row_count;
    if (!shape_matches) return error.ShapeMismatch;

    // instrumentation: trace zone: radiance postprocess ------------------------------------------------------ |
    // captures: product-row radiance convolution/calibration wall time                                         |
    // why: preserves visibility of the old simulate.radiance_postprocess stage.                                |
    {
        const radiance_zone = Trace.staticZone(@src(), "spectrum.radiance_postprocess");
        radiance_zone.value(@intCast(row_count));
        defer radiance_zone.end();
        try instrument_average.postprocessRadianceResults(
            solve_config,
            uses_integrated_radiance_sampling,
            radiance_calibration,
            radiance_slit_kernel,
            raw_radiance,
            out_radiance,
        );
    }
    // end instrumentation: trace zone: radiance postprocess -------------------------------------------------- |

    // instrumentation: trace zone: irradiance postprocess ---------------------------------------------------- |
    // captures: product-row irradiance convolution/calibration wall time                                       |
    // why: preserves visibility of the old simulate.irradiance_postprocess stage.                              |
    {
        const irradiance_zone = Trace.staticZone(@src(), "spectrum.irradiance_postprocess");
        irradiance_zone.value(@intCast(row_count));
        defer irradiance_zone.end();
        try instrument_average.postprocessSignal(
            uses_integrated_irradiance_sampling,
            irradiance_calibration,
            irradiance_slit_kernel,
            raw_irradiance,
            out_irradiance,
        );
    }
    // end instrumentation: trace zone: irradiance postprocess ------------------------------------------------ |

    // instrumentation: trace zone: reflectance assembly ------------------------------------------------------ |
    // captures: final reflectance and reflectance-Jacobian assembly wall time                                  |
    // why: keeps the final product conversion separate from sampling and channel postprocess costs.            |
    const reflectance_zone = Trace.staticZone(@src(), "spectrum.reflectance_assembly");
    reflectance_zone.value(@intCast(row_count));
    defer reflectance_zone.end();
    // end instrumentation: trace zone: reflectance assembly -------------------------------------------------- |

    return instrument_average.assembleReflectanceResults(
        solve_config,
        solar_cosine,
        out_radiance,
        out_irradiance,
        out_reflectance,
        out_jacobian,
    );
}

pub fn preferredRadianceWorkerCount(radiance_count: usize) usize {
    // preferredRadianceWorkerCount -------------------------------------------------------------------------   |
    // Keep small exact-wavelength batches single-threaded and scale larger batches through the shared          |
    // worker-count policy. This is the old `preferredForwardWorkerCount` rule under the spectrum owner.        |
    // -------------------------------------------------------------------------------------------------------- |
    return preferredWorkerCount(radiance_count, min_parallel_radiance_count);
}

pub fn preferredWorkerCount(item_count: usize, min_items_per_worker: usize) usize {
    // preferredWorkerCount ---------------------------------------------------------------------------------   |
    // Resolve CPU count and configured worker limit into a batch worker count.                                 |
    //                                                                                                          |
    // math                                                                                                     |
    //   workers = min(max_workers, available_workers, max(1, item_count / min_items_per_worker))               |
    // -------------------------------------------------------------------------------------------------------- |
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return preferredWorkerCountForCpuCount(
        item_count,
        min_items_per_worker,
        cpu_count,
        configuredWorkerLimit(),
    );
}

pub fn preferredWorkerCountForCpuCount(
    item_count: usize,
    min_items_per_worker: usize,
    cpu_count: usize,
    worker_limit: ?usize,
) usize {
    // preferredWorkerCountForCpuCount ----------------------------------------------------------------------   |
    // Pure worker-count resolver used by tests and by preferredWorkerCount after CPU/env discovery.            |
    // -------------------------------------------------------------------------------------------------------- |
    std.debug.assert(min_items_per_worker != 0);
    if (item_count < min_items_per_worker) return 1;

    const count_from_work = @max(@as(usize, 1), item_count / min_items_per_worker);
    var available_workers = @max(@as(usize, 1), cpu_count);
    if (worker_limit) |limit| {
        if (limit == 0) @panic(worker_limit_env ++ " must be a positive integer");
        available_workers = @min(available_workers, limit);
    }
    return @min(max_workers, @min(available_workers, count_from_work));
}

fn configuredWorkerLimit() ?usize {
    // configuredWorkerLimit --------------------------------------------------------------------------------   |
    // Preserve the old `ZDISAMAR_WORKER_LIMIT` behavior: absent means no extra limit; invalid or zero values   |
    // are programmer/operator errors and panic before worker launch.                                           |
    // -------------------------------------------------------------------------------------------------------- |
    const limit = std.process.parseEnvVarInt(worker_limit_env, usize, 10) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => @panic(worker_limit_env ++ " must be a positive integer"),
    };
    if (limit) |value| {
        if (value == 0) @panic(worker_limit_env ++ " must be a positive integer");
    }
    return limit;
}

comptime {
    std.debug.assert(@sizeOf(Range) == 16);
    if (builtin.mode == .Debug) {
        std.debug.assert(@sizeOf(ChunkQueue) == 40);
        std.debug.assert(@sizeOf(FirstWorkerErrorState(error{WorkerFailed})) == 24);
    } else {
        std.debug.assert(@sizeOf(ChunkQueue) == 32);
        std.debug.assert(@sizeOf(FirstWorkerErrorState(error{WorkerFailed})) == 8);
    }
}
