//! Work partitioning policies for forward-model worker loops.
//!
//! This module intentionally does not own a thread pool, a scheduler, or the
//! lifetime rules for worker state. Callers still use `std.Thread` directly so
//! each loop can keep its own error type, local scratch storage, reduction
//! strategy, and trace labels. The shared piece is only the decision about which
//! item indices a worker is allowed to process.
//!
//! There are two policies here because the forward model has two different
//! kinds of parallel work.
//!
//! `ChunkQueue` is dynamic assignment. It is the right fit when item costs can
//! vary enough that workers should keep asking for more work after they finish a
//! small chunk:
//!
//! ```
//! var queue = ChunkQueue.init(item_count, chunk_size);
//! while (queue.next()) |chunk| {
//!     for (chunk.start..chunk.end) |index| process(index);
//! }
//! ```
//!
//! That pattern is useful for spectroscopy setup and support-grid accumulation,
//! but it is not a safe latency policy for every workload. In the high-resolution
//! forward prefetch, all misses are known up front and each miss is expensive.
//! A mutex queue can accidentally collapse to nearly serial work when worker
//! start-up is staggered:
//!
//! ```
//! // Mock timeline for dynamic queue assignment:
//! worker 0 starts, locks queue, gets 0..8
//! worker 0 finishes quickly enough to lock again, gets 8..16
//! worker 0 repeats while worker 1..N are still starting
//! worker 1..N finally enter queue.next(), but most chunks are already gone
//! // The program created threads, but latency is dominated by one worker.
//! ```
//!
//! `staticRange` is deterministic ownership. It is the right fit when the full
//! item list already exists, the work should be evenly divided, and start-up
//! timing must not decide who gets the work:
//!
//! ```
//! const range = staticRange(item_count, worker_count, worker_index);
//! for (range.start..range.end) |index| process(index);
//! ```
//!
//! With static ranges, a slow-to-start worker still owns its range. No other
//! worker can drain it first, so a queue race cannot turn the forward prefetch
//! into a mostly single-worker run.
//!
//! This module also centralizes the worker-count threshold used by these loops.
//! Keep that policy here even though callers record trace labels around the same
//! loops. A trace facade that also owns worker limits or runtime policy is a
//! smell: instrumentation should observe scheduling decisions, not define them.
//! Worker limits and runtime policy belong with partitioning/scheduling, not
//! instrumentation.
//!
//! The worker-count threshold is deliberately separate from the Linux Python
//! wheel bug. On Linux, a Zig shared library loaded through Python must link
//! libc so `std.Thread` uses pthreads. Without that, Zig can use its raw Linux
//! clone/TLS path; inside a `.so` loaded by CPython, that path can observe
//! thread-local state differently from a standalone executable. macOS reaches
//! threads through libSystem/pthread already, so it did not show the same
//! failure mode. The build fix belongs in `build.zig`; this file documents why
//! the worker loops still use native `std.Thread` after that fix instead of
//! inventing an application scheduler.

const std = @import("std");

pub const max_workers: usize = 64;
pub const worker_limit_env = "ZDISAMAR_WORKER_LIMIT";

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: start=8 B, end=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const Range = struct {
    start: usize,
    end: usize,

    pub fn len(self: Range) usize {
        return self.end - self.start;
    }
};

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: mutex=4 B, next_index=8 B, item_count=8 B, chunk_size=8 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count
pub const ChunkQueue = struct {
    mutex: std.Io.Mutex = .init,
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

    // hot path:
    //   when: variable-cost workers claim chunks for wavelength sampling or support-row setup
    //   work: hands out the next contiguous item range under a short mutex
    //   data: next index, item count, chunk size, returned range
    //   math: start = next_index; end = min(start + chunk_size, item_count)
    //   follow: wavelengthSamplingWorkerMain and profile/support-row worker loops
    pub fn next(self: *ChunkQueue) ?Range {
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        if (self.next_index >= self.item_count) return null;

        const start = self.next_index;
        const end = @min(start + self.chunk_size, self.item_count);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};

// hot path:
//   when: forward prefetch assigns known expensive misses to workers
//   work: computes deterministic ownership range for one worker
//   data: item count, worker count, worker index
//   math: start = floor(worker_index * item_count / worker_count); end = floor((worker_index + 1) * item_count / worker_count)
//   follow: spectral_forward.prefetchForwardSamples worker setup
pub fn staticRange(item_count: usize, worker_count: usize, worker_index: usize) Range {
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

// hot path:
//   when: sampling and forward-prefetch schedulers choose worker count for a batch
//   work: resolves CPU count and configured worker limit into an item-count-based worker count
//   data: item count, minimum items per worker, CPU count, worker-limit environment value
//   math: workers = min(max_workers, min(available_workers, max(1, floor(item_count / min_items_per_worker))))
//   follow: preferredWorkerCountForCpuCount and caller chunk/range ownership
pub fn preferredWorkerCount(item_count: usize, min_items_per_worker: usize) usize {
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
    const raw = std.c.getenv(worker_limit_env) orelse return null;
    const text = std.mem.sliceTo(raw, 0);
    const limit = std.fmt.parseInt(usize, text, 10) catch
        @panic(worker_limit_env ++ " must be a positive integer");
    if (limit == 0) @panic(worker_limit_env ++ " must be a positive integer");
    return limit;
}
