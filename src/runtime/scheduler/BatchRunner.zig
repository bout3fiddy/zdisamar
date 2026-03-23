//! Purpose:
//!   Execute queued scene jobs against prepared-plan layout metadata using one reusable thread
//!   context.
//!
//! Physics:
//!   This is runtime orchestration only: it reuses prepared-layout hints and thread scratch while
//!   dispatching scene jobs to a caller-provided execution callback.
//!
//! Vendor:
//!   `batch scheduling and prepared-plan reuse`
//!
//! Design:
//!   Keep the scheduler generic by queueing only `(plan_id, scene_id)` jobs and delegating the
//!   actual execution to a typed callback.
//!
//! Invariants:
//!   Jobs execute against prepared plans already present in the plan cache. A thread context may
//!   be rebound only by resetting between differing plan ids.
//!
//! Validation:
//!   Batch runner tests in this file and the engine-side batch execution paths that reuse thread
//!   workspaces across plan ids.

const std = @import("std");
const PlanCache = @import("../cache/PlanCache.zig").PlanCache;
const PreparedLayout = @import("../cache/PreparedLayout.zig").PreparedLayout;
const ThreadContext = @import("ThreadContext.zig").ThreadContext;

const Allocator = std.mem.Allocator;

pub const BatchJob = struct {
    plan_id: u64,
    scene_id: []const u8,
};

pub const ExecuteFn = *const fn (
    ctx: ?*anyopaque,
    thread: *ThreadContext,
    job: BatchJob,
    prepared_layout: *const PreparedLayout,
) anyerror!void;

/// Purpose:
///   Hold a queue of plan/scene jobs and execute them against cached prepared-layout metadata.
pub const BatchRunner = struct {
    allocator: Allocator,
    queue: std.ArrayListUnmanaged(BatchJob) = .{},
    completed_jobs: u64 = 0,
    failed_jobs: u64 = 0,

    pub fn init(allocator: Allocator) BatchRunner {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *BatchRunner) void {
        self.queue.deinit(self.allocator);
    }

    /// Purpose:
    ///   Enqueue one plan/scene job for later execution.
    pub fn enqueue(self: *BatchRunner, job: BatchJob) !void {
        if (job.scene_id.len == 0) return error.InvalidBatchJob;
        try self.queue.append(self.allocator, job);
    }

    /// Purpose:
    ///   Clear the queue and reset the completed/failed counters.
    pub fn clear(self: *BatchRunner) void {
        self.queue.clearRetainingCapacity();
        self.completed_jobs = 0;
        self.failed_jobs = 0;
    }

    /// Purpose:
    ///   Execute all queued jobs against the plan cache using one reusable thread context.
    pub fn run(
        self: *BatchRunner,
        thread: *ThreadContext,
        plan_cache: *PlanCache,
        exec_ctx: ?*anyopaque,
        execute: ExecuteFn,
    ) !void {
        for (self.queue.items) |job| {
            const entry = plan_cache.get(job.plan_id) orelse return error.MissingPreparedPlan;

            if (thread.bound_plan_id) |bound| {
                if (bound != job.plan_id) {
                    // DECISION:
                    //   A batch may mix plan ids, so the thread context resets before rebinding to
                    //   another prepared plan instead of trying to share scratch state implicitly.
                    thread.reset();
                }
            }
            try thread.beginExecution(job.plan_id);
            thread.prepareScratch(&entry.prepared_layout);
            execute(exec_ctx, thread, job, &entry.prepared_layout) catch |err| {
                self.failed_jobs += 1;
                return err;
            };

            _ = plan_cache.markRun(job.plan_id);
            self.completed_jobs += 1;
        }
    }
};

test "batch runner executes queued jobs against prepared plans" {
    const Ctx = struct {
        executed: u64 = 0,
    };

    const callbacks = struct {
        fn execute(
            ctx_ptr: ?*anyopaque,
            thread: *ThreadContext,
            job: BatchJob,
            prepared_layout: *const PreparedLayout,
        ) !void {
            _ = thread;
            _ = job;
            _ = prepared_layout;
            const ctx: *Ctx = @ptrCast(@alignCast(ctx_ptr.?));
            ctx.executed += 1;
        }
    };

    var plan_cache = PlanCache.init(std.testing.allocator, .{ .max_entries = 4 });
    defer plan_cache.deinit();
    try plan_cache.put(1, .{ .measurement_capacity = 16 });
    try plan_cache.put(2, .{ .measurement_capacity = 32 });

    var thread = ThreadContext.init("batch-thread");

    var runner = BatchRunner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.enqueue(.{ .plan_id = 1, .scene_id = "scene-a" });
    try runner.enqueue(.{ .plan_id = 1, .scene_id = "scene-b" });
    try runner.enqueue(.{ .plan_id = 2, .scene_id = "scene-c" });

    var ctx: Ctx = .{};
    try runner.run(&thread, &plan_cache, &ctx, callbacks.execute);

    try std.testing.expectEqual(@as(u64, 3), ctx.executed);
    try std.testing.expectEqual(@as(u64, 3), runner.completed_jobs);
    try std.testing.expectEqual(@as(u64, 0), runner.failed_jobs);
    try std.testing.expectEqual(@as(u64, 2), plan_cache.get(1).?.run_count);
    try std.testing.expectEqual(@as(u64, 1), plan_cache.get(2).?.run_count);
}
