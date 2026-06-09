const std = @import("std");

// work_partition.zig -----------------------------------------------------------------------------------------|
// Work partitioning policies shared by forward-model worker loops.                                            |
//                                                                                                             |
// called by                                                                                                   |
//   optical setup: absorber line-state workers, spectroscopy cache initialization, and support-row buildup    |
//   instrument grid: wavelength sampling, forward-cache prefetch, profile-cache build, and product simulate   |
//   optimal estimation: batch retrieval workers                                                               |
//   tests/unit/forward_model/work_partition_test.zig covers chunk draining, static coverage, and worker caps  |
//                                                                                                             |
// boundary shape                                                                                              |
//   This module does not own a thread pool, scheduler, worker lifetime, trace label, scratch buffer, error    |
//   channel, or reduction strategy. Callers keep std.Thread and their local worker state. The shared policy   |
//   here is only which half-open item range one worker may process.                                           |
//                                                                                                             |
// policies                                                                                                    |
//   ChunkQueue is dynamic assignment: workers claim the next small chunk when item costs vary enough that     |
//   static ranges can leave late work stranded. It fits spectroscopy setup and support-grid accumulation.     |
//                                                                                                             |
//   staticRange is deterministic ownership: workers get fixed ranges when the full item list already exists,  |
//   work should be evenly divided, and startup timing must not decide who drains the expensive items. It is   |
//   the preferred latency shape for high-resolution forward prefetch.                                         |
//                                                                                                             |
// queue hazard                                                                                                |
//   Dynamic queues are not universally safe. If worker 0 starts early and repeatedly locks the queue before   |
//   worker 1..N enter next(), it can drain most known-expensive chunks and make the run mostly serial. Static |
//   ranges prevent that by leaving each worker's range owned even if the worker starts late.                  |
//                                                                                                             |
// worker count                                                                                                |
//   preferredWorkerCount combines CPU count, item count, max_workers, and ZDISAMAR_WORKER_LIMIT. Keep that    |
//   scheduling policy here. Trace and telemetry may observe worker loops, but instrumentation must not define |
//   worker limits or runtime policy.                                                                          |
//                                                                                                             |
// platform note                                                                                               |
//   The Linux Python wheel thread bug was fixed in build.zig by linking libc for the shared library so        |
//   std.Thread uses pthreads when loaded by CPython. This file keeps native std.Thread partitioning instead   |
//   of adding an application scheduler. macOS already reaches threads through libSystem/pthread.              |
// ------------------------------------------------------------------------------------------------------------|

pub const max_workers: usize = 64;
pub const worker_limit_env = "ZDISAMAR_WORKER_LIMIT";

// Range ----------------------------------------------------------------------------------------------------- |
// Half-open item range owned by one worker or one queue claim.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] start : usize                                                                                      |
// [ 8..15] end   : usize                                                                                      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B; stack return value                                                          |
pub const Range = struct {
    start: usize,
    end: usize,

    pub fn len(self: Range) usize {
        return self.end - self.start;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// ChunkQueue ------------------------------------------------------------------------------------------------ |
// Mutex-protected dynamic chunk dispenser for variable-cost worker loops.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] mutex      : Thread.Mutex                                                                          |
// [16..23] next_index : usize                                                                                 |
// [24..31] item_count : usize                                                                                 |
// [32..39] chunk_size : usize                                                                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 40 B; one queue per dynamic worker group                                          |
pub const ChunkQueue = struct {
    mutex: std.Thread.Mutex = .{},
    next_index: usize = 0,
    item_count: usize,
    chunk_size: usize,

    pub fn init(item_count: usize, chunk_size: usize) ChunkQueue {
        std.debug.assert(chunk_size != 0);
        return .{
            .item_count = item_count,
            .chunk_size = chunk_size,
        };
    }

    pub fn next(self: *ChunkQueue) ?Range {
        // ChunkQueue.next --------------------------------------------------------------------------------    |
        // Hands out the next contiguous item range under a short mutex.                                       |
        //                                                                                                     |
        // hot path                                                                                            |
        //   Variable-cost workers claim chunks for wavelength sampling or support-row setup.                  |
        //                                                                                                     |
        // math                                                                                                |
        //   start = next_index                                                                                |
        //   end   = min(start + chunk_size, item_count)                                                       |
        // ------------------------------------------------------------------------------------------------    |

        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.next_index >= self.item_count) return null;

        const start = self.next_index;
        const end = @min(start + self.chunk_size, self.item_count);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn staticRange(item_count: usize, worker_count: usize, worker_index: usize) Range {
    // staticRange ------------------------------------------------------------------------------------------- |
    // Computes deterministic ownership range for one worker.                                                  |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Forward prefetch assigns known expensive misses up front, so startup timing must not decide which     |
    //   worker drains the work.                                                                               |
    //                                                                                                         |
    // math                                                                                                    |
    //   start = floor(worker_index * item_count / worker_count)                                               |
    //   end   = floor((worker_index + 1) * item_count / worker_count)                                         |
    // ------------------------------------------------------------------------------------------------------- |

    std.debug.assert(worker_count != 0);
    std.debug.assert(worker_index < worker_count);
    return .{
        .start = worker_index * item_count / worker_count,
        .end = (worker_index + 1) * item_count / worker_count,
    };
}

pub fn rangesAreBalanced(item_count: usize, worker_count: usize) bool {
    if (worker_count == 0) return false;

    var expected_start: usize = 0;
    var min_count: usize = std.math.maxInt(usize);
    var max_count: usize = 0;
    for (0..worker_count) |worker_index| {
        const range = staticRange(item_count, worker_count, worker_index);
        if (range.start != expected_start) return false;
        if (range.end < range.start or range.end > item_count) return false;

        const count = range.len();
        min_count = @min(min_count, count);
        max_count = @max(max_count, count);
        expected_start = range.end;
    }

    if (expected_start != item_count) return false;
    if (item_count == 0) return max_count == 0;
    return max_count - min_count <= 1;
}

pub fn preferredWorkerCount(item_count: usize, min_items_per_worker: usize) usize {
    // preferredWorkerCount ---------------------------------------------------------------------------------- |
    // Resolves CPU count and configured worker limit into a batch worker count.                               |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Sampling and forward-prefetch schedulers call this before creating worker-owned ranges or queues.     |
    //                                                                                                         |
    // math                                                                                                    |
    //   workers = min(max_workers, available_workers, max(1, item_count / min_items_per_worker))              |
    // ------------------------------------------------------------------------------------------------------- |

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
    const limit = std.process.parseEnvVarInt(worker_limit_env, usize, 10) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => @panic(worker_limit_env ++ " must be a positive integer"),
    };
    if (limit) |value| {
        if (value == 0) @panic(worker_limit_env ++ " must be a positive integer");
    }
    return limit;
}
