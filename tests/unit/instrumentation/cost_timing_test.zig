const std = @import("std");

const internal = @import("internal");

const cost_timing = internal.instrumentation.cost_timing;

test "cost timing rows keep LABOS memory layout" {
    try std.testing.expectEqual(false, cost_timing.enabled);

    try std.testing.expectEqual(@as(usize, 16), @sizeOf(cost_timing.Counter));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(cost_timing.Counter));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(cost_timing.Counter, "ns"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(cost_timing.Counter, "count"));

    try std.testing.expectEqual(@as(usize, 8), @sizeOf(cost_timing.Count));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(cost_timing.Count));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(cost_timing.Count, "count"));

    try std.testing.expectEqual(@as(usize, 376), @sizeOf(cost_timing.StageCost));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(cost_timing.StageCost));
    try expectStageCostOffsets();

    try std.testing.expectEqual(@as(usize, 8), @sizeOf(cost_timing.Active));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(cost_timing.Active));

    try std.testing.expectEqual(@as(usize, 0), @sizeOf(cost_timing.WorkspaceState));
    try std.testing.expectEqual(@as(usize, 1), @alignOf(cost_timing.WorkspaceState));
}

test "cost timing counters merge reset and saturate" {
    var counter = cost_timing.Counter{ .ns = std.math.maxInt(u64) - 2, .count = std.math.maxInt(u64) };
    counter.add(9);
    try std.testing.expectEqual(std.math.maxInt(u64), counter.ns);
    try std.testing.expectEqual(std.math.maxInt(u64), counter.count);

    var count = cost_timing.Count{ .count = std.math.maxInt(u64) - 3 };
    count.add(9);
    try std.testing.expectEqual(std.math.maxInt(u64), count.count);

    var timing = cost_timing.StageCost{};
    var other = cost_timing.StageCost{};
    other.execute.add(7);
    other.fixed_rd_retained.add(4);
    timing.merge(other);
    try std.testing.expectEqual(@as(u64, 7), timing.execute.ns);
    try std.testing.expectEqual(@as(u64, 1), timing.execute.count);
    try std.testing.expectEqual(@as(u64, 4), timing.fixed_rd_retained.count);

    timing.reset();
    try std.testing.expectEqual(@as(u64, 0), timing.execute.ns);
    try std.testing.expectEqual(@as(u64, 0), timing.fixed_rd_retained.count);
}

test "disabled cost timing workspace calls are no-ops" {
    var timing = cost_timing.StageCost{};
    var state = cost_timing.WorkspaceState{};
    const active = cost_timing.Active{ .stage_cost = &timing };

    cost_timing.setWorkspaceState(&state, &timing);
    try std.testing.expectEqual(null, cost_timing.activeWorkspaceState(&state));

    cost_timing.setActiveWorkspaceState(&state, active);
    try std.testing.expectEqual(null, cost_timing.start(active));

    cost_timing.count(active, "fixed_doubling_steps", 3);
    cost_timing.finish(active, 0, "fixed_qseries_work");
    cost_timing.clearWorkspaceState(&state);

    try std.testing.expectEqual(@as(u64, 0), timing.fixed_doubling_steps.count);
    try std.testing.expectEqual(@as(u64, 0), timing.fixed_qseries_work.count);
}

fn expectStageCostOffsets() !void {
    // expectStageCostOffsets --------------------------------------------------------------------------------|
    // Pin the cost-timing StageCost field order used by retained trace JSON.                                  |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(cost_timing.StageCost, "execute"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(cost_timing.StageCost, "attenuation_fill"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(cost_timing.StageCost, "fourier_loop"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(cost_timing.StageCost, "plm_basis"));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(cost_timing.StageCost, "rt_layer_build"));
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(cost_timing.StageCost, "rt_layer_phase_matrix"));
    try std.testing.expectEqual(@as(usize, 96), @offsetOf(cost_timing.StageCost, "rt_layer_doubling"));
    try std.testing.expectEqual(@as(usize, 112), @offsetOf(cost_timing.StageCost, "fixed_qseries_work"));
    try std.testing.expectEqual(@as(usize, 128), @offsetOf(cost_timing.StageCost, "fixed_rd_update"));
    try std.testing.expectEqual(@as(usize, 144), @offsetOf(cost_timing.StageCost, "fixed_tu_update"));
    try std.testing.expectEqual(@as(usize, 160), @offsetOf(cost_timing.StageCost, "fixed_td_update"));
    try std.testing.expectEqual(@as(usize, 176), @offsetOf(cost_timing.StageCost, "orders_total"));
    try std.testing.expectEqual(@as(usize, 192), @offsetOf(cost_timing.StageCost, "orders_initial_sources"));
    try std.testing.expectEqual(@as(usize, 208), @offsetOf(cost_timing.StageCost, "orders_initial_transport"));
    try std.testing.expectEqual(@as(usize, 224), @offsetOf(cost_timing.StageCost, "orders_local_down"));
    try std.testing.expectEqual(@as(usize, 240), @offsetOf(cost_timing.StageCost, "orders_local_up"));
    try std.testing.expectEqual(@as(usize, 256), @offsetOf(cost_timing.StageCost, "orders_transport"));
    try std.testing.expectEqual(@as(usize, 272), @offsetOf(cost_timing.StageCost, "orders_accumulate"));
    try std.testing.expectEqual(@as(usize, 288), @offsetOf(cost_timing.StageCost, "reflectance_integral"));
    try std.testing.expectEqual(@as(usize, 304), @offsetOf(cost_timing.StageCost, "fixed_doubling_steps"));
    try std.testing.expectEqual(@as(usize, 312), @offsetOf(cost_timing.StageCost, "fixed_qseries_skipped"));
    try std.testing.expectEqual(@as(usize, 320), @offsetOf(cost_timing.StageCost, "fixed_qseries_retained"));
    try std.testing.expectEqual(@as(usize, 328), @offsetOf(cost_timing.StageCost, "fixed_rd_skipped"));
    try std.testing.expectEqual(@as(usize, 336), @offsetOf(cost_timing.StageCost, "fixed_rd_retained"));
    try std.testing.expectEqual(@as(usize, 344), @offsetOf(cost_timing.StageCost, "fixed_tu_skipped"));
    try std.testing.expectEqual(@as(usize, 352), @offsetOf(cost_timing.StageCost, "fixed_tu_retained"));
    try std.testing.expectEqual(@as(usize, 360), @offsetOf(cost_timing.StageCost, "fixed_td_skipped"));
    try std.testing.expectEqual(@as(usize, 368), @offsetOf(cost_timing.StageCost, "fixed_td_retained"));
}
