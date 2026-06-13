const std = @import("std");
const builtin = @import("builtin");

// worker_partition.zig ---------------------------------------------------------------------------------------|
// Shared worker partitioning and spawn orchestration for the explicit O2 A route.                             |
//                                                                                                             |
//                                                                                                             |
// boundary                                                                                                    |
//   This module owns worker count, deterministic ranges, chunk claims, first-error capture, and shared        |
//   spawn/join choreography. Workers stay site-local and carry the physical rows for that phase.              |
//   No scene, controls, optics rows, spectrum rows, or cache stamps enter this shared support file.           |
//                                                                                                             |
// policies                                                                                                    |
//   staticRange assigns deterministic half-open ranges when the full item list exists before launch.          |
//   ChunkQueue assigns dynamic chunks when item cost varies enough that static ranges can leave late work.    |
//   runWorkers preserves ordering: helpers start first, the calling thread runs the last worker, and          |
//   joins happen after the calling-thread worker finishes.                                                    |
//                                                                                                             |
// platform note                                                                                               |
//   The C library links libc so std.Thread reaches pthreads when loaded by CPython. This file keeps the       |
//   std.Thread model and does not add an application scheduler.                                               |
// ------------------------------------------------------------------------------------------------------------|

pub const max_workers: usize = 64;
pub const worker_limit_env = "ZDISAMAR_WORKER_LIMIT";

pub const testing = if (builtin.is_test) struct {
    pub var force_raw_spawn_failure = std.atomic.Value(bool).init(false);
} else struct {};

// Range ------------------------------------------------------------------------------------------------------|
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
        // Range.len ------------------------------------------------------------------------------------------|
        // Return the number of items in this half-open worker range.                                          |
        // ----------------------------------------------------------------------------------------------------|
        return self.end - self.start;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// ChunkQueue -------------------------------------------------------------------------------------------------|
// Mutex-protected dynamic chunk dispenser for variable-cost worker loops.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B in Debug; 32 B (0.031 KiB), align: 8 B in optimized builds               |
//                                                                                                             |
// memory, Debug                                                                                               |
// [ 0..15] mutex      : Thread.Mutex                                                                          |
// [16..23] next_index : usize                                                                                 |
// [24..31] item_count : usize                                                                                 |
// [32..39] chunk_size : usize                                                                                 |
//                                                                                                             |
// memory, optimized                                                                                           |
// [ 0.. 7] next_index : usize                                                                                 |
// [ 8..15] item_count : usize                                                                                 |
// [16..23] chunk_size : usize                                                                                 |
// [24..27] mutex      : Thread.Mutex                                                                          |
// [28..31] padding    : 4 B                                                                                   |
//                                                                                                             |
// footprint: per instance = 40 B Debug or 32 B optimized; one queue per dynamic worker group                  |
pub const ChunkQueue = struct {
    mutex: std.Thread.Mutex = .{},
    next_index: usize = 0,
    item_count: usize,
    chunk_size: usize,

    pub fn init(item_count: usize, chunk_size: usize) ChunkQueue {
        // ChunkQueue.init ------------------------------------------------------------------------------------|
        // Build a queue over `item_count` items. A zero chunk would stall workers, so assert the              |
        // policy precondition before any worker can enter next().                                             |
        // ----------------------------------------------------------------------------------------------------|
        std.debug.assert(chunk_size != 0);
        return .{
            .item_count = item_count,
            .chunk_size = chunk_size,
        };
    }

    pub fn next(self: *ChunkQueue) ?Range {
        // ChunkQueue.next ------------------------------------------------------------------------------------|
        // Hand out the next contiguous item range under a short mutex.                                        |
        //                                                                                                     |
        // math                                                                                                |
        //   start = next_index                                                                                |
        //   end   = min(start + chunk_size, item_count)                                                       |
        // ----------------------------------------------------------------------------------------------------|
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

pub fn FirstWorkerErrorState(comptime ErrorSet: type) type {
    // FirstWorkerErrorState ----------------------------------------------------------------------------------|
    // Shared first-error slot for parallel workers. Workers write only on failure, so the mutex guards the    |
    // cold path while the successful hot loop does no cross-worker coordination.                              |
    //                                                                                                         |
    // layout(64-bit, ErrorSet with one or more errors)                                                        |
    // size: 24 B (0.023 KiB), align: 8 B in Debug; 8 B (0.008 KiB), align: 4 B in optimized builds            |
    //                                                                                                         |
    // memory, Debug                                                                                           |
    // [ 0..15] mutex   : std.Thread.Mutex                                                                     |
    // [16..17] err     : ?ErrorSet                                                                            |
    // [18..23] padding : 6 B                                                                                  |
    //                                                                                                         |
    // memory, optimized                                                                                       |
    // [0..3] mutex   : std.Thread.Mutex                                                                       |
    // [4..5] err     : ?ErrorSet                                                                              |
    // [6..7] padding : 2 B                                                                                    |
    // --------------------------------------------------------------------------------------------------------|
    return struct {
        mutex: std.Thread.Mutex = .{},
        err: ?ErrorSet = null,

        pub fn store(self: *@This(), err: ErrorSet) void {
            // FirstWorkerErrorState.store --------------------------------------------------------------------|
            // Preserve the first observed worker error. Later failures leave the original cause in place.     |
            // Joined callers return the earliest failure deterministically.                                   |
            // ------------------------------------------------------------------------------------------------|
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.err == null) self.err = err;
        }
    };
}

pub fn staticRange(item_count: usize, worker_count: usize, worker_index: usize) Range {
    // staticRange --------------------------------------------------------------------------------------------|
    // Compute deterministic ownership range for one worker.                                                   |
    //                                                                                                         |
    // math                                                                                                    |
    //   start = floor(worker_index * item_count / worker_count)                                               |
    //   end   = floor((worker_index + 1) * item_count / worker_count)                                         |
    //                                                                                                         |
    // reason                                                                                                  |
    //   Known expensive forward misses are assigned before launch so worker startup timing cannot decide who  |
    //   drains the high-cost items.                                                                           |
    // --------------------------------------------------------------------------------------------------------|
    std.debug.assert(worker_count != 0);
    std.debug.assert(worker_index < worker_count);
    return .{
        .start = worker_index * item_count / worker_count,
        .end = (worker_index + 1) * item_count / worker_count,
    };
}

pub fn nextStaticChunk(start_index: *usize, end_index: usize, chunk_size: usize) ?Range {
    // nextStaticChunk ----------------------------------------------------------------------------------------|
    // Drain one worker-owned static range in the caller's canonical chunk shape.                              |
    // --------------------------------------------------------------------------------------------------------|
    std.debug.assert(chunk_size != 0);
    if (start_index.* >= end_index) return null;

    const chunk = Range{
        .start = start_index.*,
        .end = @min(start_index.* + chunk_size, end_index),
    };
    start_index.* = chunk.end;
    return chunk;
}

pub fn preferredWorkerCount(item_count: usize, min_items_per_worker: usize) usize {
    // preferredWorkerCount -----------------------------------------------------------------------------------|
    // Resolve CPU count and configured worker limit into a batch worker count.                                |
    //                                                                                                         |
    // math                                                                                                    |
    //   workers = min(max_workers, available_workers, max(1, item_count / min_items_per_worker))              |
    // --------------------------------------------------------------------------------------------------------|
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
    // preferredWorkerCountForCpuCount ------------------------------------------------------------------------|
    // Pure worker-count resolver used by tests and by preferredWorkerCount after CPU/env discovery.           |
    // --------------------------------------------------------------------------------------------------------|
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

pub fn runWorkers(pool: ?*std.Thread.Pool, workers: anytype, comptime workerMain: anytype) void {
    // runWorkers ---------------------------------------------------------------------------------------------|
    // Run one site-local worker row per worker through the shared pool/raw-spawn choreography.                |
    //                                                                                                         |
    // scheduling                                                                                              |
    //   worker_count == 1 : calling thread runs worker 0 inline                                               |
    //   pool != null      : pool helpers run workers 0..n-2, calling thread runs worker n-1, wait after       |
    //   pool == null      : raw helper threads run workers 0..n-2 when spawn succeeds; failed spawns run      |
    //                       that helper inline; calling thread still runs worker n-1 before joining helpers   |
    //                                                                                                         |
    // boundary                                                                                                |
    //   Worker rows own their error slots, output slices, queues, traces, and reduction buffers. This helper  |
    //   never interprets worker contents and therefore cannot hide physics inputs or cache stamps.            |
    // --------------------------------------------------------------------------------------------------------|
    if (workers.len == 0) return;
    std.debug.assert(workers.len <= max_workers);

    if (workers.len == 1) {
        workerMain(&workers[0]);
        return;
    }

    if (pool) |thread_pool| {
        var wait_group = std.Thread.WaitGroup{};
        for (workers[0 .. workers.len - 1]) |*worker| {
            thread_pool.spawnWg(&wait_group, workerMain, .{worker});
        }
        workerMain(&workers[workers.len - 1]);
        wait_group.wait();
        return;
    }

    var threads: [max_workers - 1]std.Thread = undefined;
    var started_thread_count: usize = 0;

    for (workers[0 .. workers.len - 1]) |*worker| {
        const force_spawn_failure_for_test = if (builtin.is_test)
            testing.force_raw_spawn_failure.load(.seq_cst)
        else
            false;

        if (force_spawn_failure_for_test) {
            workerMain(worker);
            continue;
        }

        threads[started_thread_count] = std.Thread.spawn(.{}, workerMain, .{worker}) catch {
            workerMain(worker);
            continue;
        };
        started_thread_count += 1;
    }

    workerMain(&workers[workers.len - 1]);
    for (threads[0..started_thread_count]) |thread| thread.join();
}

fn configuredWorkerLimit() ?usize {
    // configuredWorkerLimit ----------------------------------------------------------------------------------|
    // Preserve `ZDISAMAR_WORKER_LIMIT` behavior: absent means no extra limit; invalid or zero values          |
    // panic before worker launch.                                                                             |
    // --------------------------------------------------------------------------------------------------------|
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
