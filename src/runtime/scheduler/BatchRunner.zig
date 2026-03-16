const std = @import("std");
const PlanCache = @import("../cache/PlanCache.zig").PlanCache;
const PreparedPlanCache = @import("../cache/PreparedPlanCache.zig").PreparedPlanCache;
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
    prepared: *const PreparedPlanCache,
) anyerror!void;

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

    pub fn enqueue(self: *BatchRunner, job: BatchJob) !void {
        if (job.scene_id.len == 0) return error.InvalidBatchJob;
        try self.queue.append(self.allocator, job);
    }

    pub fn clear(self: *BatchRunner) void {
        self.queue.clearRetainingCapacity();
        self.completed_jobs = 0;
        self.failed_jobs = 0;
    }

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
                    // A batch may include multiple prepared plans; reset scratch
                    // and binding before transitioning to another plan id.
                    thread.reset();
                }
            }
            try thread.beginExecution(job.plan_id, &entry.prepared);
            execute(exec_ctx, thread, job, &entry.prepared) catch |err| {
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
            prepared: *const PreparedPlanCache,
        ) !void {
            _ = thread;
            _ = job;
            _ = prepared;
            const ctx: *Ctx = @ptrCast(@alignCast(ctx_ptr.?));
            ctx.executed += 1;
        }
    };

    var plan_cache = PlanCache.init(std.testing.allocator, .{ .max_entries = 4 });
    defer plan_cache.deinit();
    try plan_cache.put(1, .{ .measurement_capacity = 16 });
    try plan_cache.put(2, .{ .measurement_capacity = 32 });

    var thread = try ThreadContext.init(std.testing.allocator, "batch-thread");
    defer thread.deinit();

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
