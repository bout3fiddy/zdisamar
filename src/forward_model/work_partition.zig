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
//! That is deliberately separate from the Linux Python wheel bug. On Linux, a
//! Zig shared library loaded through Python must link libc so `std.Thread` uses
//! pthreads. Without that, Zig can use its raw Linux clone/TLS path; inside a
//! `.so` loaded by CPython, that path can observe thread-local state differently
//! from a standalone executable. macOS reaches threads through libSystem/pthread
//! already, so it did not show the same failure mode. The build fix belongs in
//! `build.zig`; this file documents why the worker loops still use native
//! `std.Thread` after that fix instead of inventing an application scheduler.

const std = @import("std");
const Trace = @import("performance_trace.zig");

pub const Range = struct {
    start: usize,
    end: usize,

    pub fn len(self: Range) usize {
        return self.end - self.start;
    }
};

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
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.next_index >= self.item_count) return null;

        const start = self.next_index;
        const end = @min(start + self.chunk_size, self.item_count);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};

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

pub fn preferredWorkerCount(item_count: usize, min_items_per_worker: usize) usize {
    std.debug.assert(min_items_per_worker != 0);
    if (item_count < min_items_per_worker) return 1;

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const count_from_work = @max(@as(usize, 1), item_count / min_items_per_worker);
    return @min(Trace.max_workers, @min(cpu_count, count_from_work));
}
