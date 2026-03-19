const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const DatasetCache = internal.runtime.cache.DatasetCache;
const LUTCache = internal.runtime.cache.LUTCache;
const PlanCache = internal.runtime.cache.PlanCache;
const PreparedLayout = internal.runtime.cache.PreparedLayout;
const BatchRunner = internal.runtime.scheduler.BatchRunner;
const BatchJob = internal.runtime.scheduler.BatchJob;

test "dataset and lut caches track owned entries with explicit updates" {
    var datasets = DatasetCache.init(std.testing.allocator);
    defer datasets.deinit();

    var luts = LUTCache.init(std.testing.allocator);
    defer luts.deinit();

    try datasets.upsert("climatology.base", "sha256:dataset-a");
    try datasets.upsert("climatology.base", "sha256:dataset-b");
    try luts.upsert("climatology.base", "temperature_273", .{
        .spectral_bins = 480,
        .layer_count = 32,
        .coefficient_count = 8,
    });

    try std.testing.expectEqual(@as(usize, 1), datasets.count());
    try std.testing.expectEqualStrings("sha256:dataset-b", datasets.get("climatology.base").?.dataset_hash);
    try std.testing.expectEqual(@as(usize, 1), luts.count());
}

test "plan cache and batch runner execute against thread-bound prepared plans" {
    const Counters = struct {
        executed: usize = 0,
    };

    const callbacks = struct {
        fn execute(
            ctx_ptr: ?*anyopaque,
            thread: *zdisamar.Workspace,
            job: BatchJob,
            prepared: *const PreparedLayout,
        ) !void {
            _ = thread;
            _ = job;
            _ = prepared;
            const counters: *Counters = @ptrCast(@alignCast(ctx_ptr.?));
            counters.executed += 1;
        }
    };

    var plans = PlanCache.init(std.testing.allocator, .{ .max_entries = 8 });
    defer plans.deinit();
    try plans.put(11, .{ .measurement_capacity = 48 });

    var thread = zdisamar.Workspace.init("thread-a");

    var runner = BatchRunner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.enqueue(.{ .plan_id = 11, .scene_id = "scene-1" });
    try runner.enqueue(.{ .plan_id = 11, .scene_id = "scene-2" });

    var counters: Counters = .{};
    try runner.run(&thread, &plans, &counters, callbacks.execute);

    try std.testing.expectEqual(@as(usize, 2), counters.executed);
    try std.testing.expectEqual(@as(u64, 2), runner.completed_jobs);
    try std.testing.expectEqual(@as(u64, 2), plans.get(11).?.run_count);
}

test "engine can repeatedly prepare and dispose plans without exhausting cache capacity" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{ .max_prepared_plans = 1 });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var last_plan_id: u64 = 0;
    var iteration: usize = 0;
    while (iteration < 4) : (iteration += 1) {
        var plan = try engine.preparePlan(.{});
        try std.testing.expect(plan.id > last_plan_id);
        try std.testing.expectEqual(@as(usize, 1), engine.plan_cache.count());
        last_plan_id = plan.id;
        plan.deinit();
    }

    try std.testing.expectEqual(@as(usize, 1), engine.plan_cache.count());
}
