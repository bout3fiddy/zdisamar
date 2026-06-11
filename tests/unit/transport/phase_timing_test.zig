const std = @import("std");

const internal = @import("internal");

const phase_timing = internal.transport.phase_timing;

test "phase timing rows keep old LABOS memory layout" {
    try std.testing.expectEqual(false, phase_timing.enabled);

    try std.testing.expectEqual(@as(usize, 16), @sizeOf(phase_timing.Counter));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_timing.Counter));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(phase_timing.Counter, "ns"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(phase_timing.Counter, "count"));

    try std.testing.expectEqual(@as(usize, 8), @sizeOf(phase_timing.Count));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_timing.Count));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(phase_timing.Count, "count"));

    try std.testing.expectEqual(@as(usize, 376), @sizeOf(phase_timing.Timing));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_timing.Timing));
    try expectTimingOffsets();

    try std.testing.expectEqual(@as(usize, 8), @sizeOf(phase_timing.Active));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_timing.Active));

    try std.testing.expectEqual(@as(usize, 0), @sizeOf(phase_timing.WorkspaceState));
    try std.testing.expectEqual(@as(usize, 1), @alignOf(phase_timing.WorkspaceState));
}

test "phase timing counters merge reset and saturate" {
    var counter = phase_timing.Counter{ .ns = std.math.maxInt(u64) - 2, .count = std.math.maxInt(u64) };
    counter.add(9);
    try std.testing.expectEqual(std.math.maxInt(u64), counter.ns);
    try std.testing.expectEqual(std.math.maxInt(u64), counter.count);

    var count = phase_timing.Count{ .count = std.math.maxInt(u64) - 3 };
    count.add(9);
    try std.testing.expectEqual(std.math.maxInt(u64), count.count);

    var timing = phase_timing.Timing{};
    var other = phase_timing.Timing{};
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

test "disabled phase timing workspace calls are no-ops" {
    var timing = phase_timing.Timing{};
    var state = phase_timing.WorkspaceState{};
    const active = phase_timing.Active{ .timing = &timing };

    phase_timing.setWorkspaceState(&state, &timing);
    try std.testing.expectEqual(null, phase_timing.activeWorkspaceState(&state));

    phase_timing.setActiveWorkspaceState(&state, active);
    try std.testing.expectEqual(null, phase_timing.start(active));

    phase_timing.count(active, "fixed_doubling_steps", 3);
    phase_timing.finish(active, 0, "fixed_qseries_work");
    phase_timing.clearWorkspaceState(&state);

    try std.testing.expectEqual(@as(u64, 0), timing.fixed_doubling_steps.count);
    try std.testing.expectEqual(@as(u64, 0), timing.fixed_qseries_work.count);
}

fn expectTimingOffsets() !void {
    // expectTimingOffsets ----------------------------------------------------------------------------------- |
    // Pin the old `labos/phase_timing.zig` Timing field order used by retained trace JSON.                    |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(phase_timing.Timing, "execute"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(phase_timing.Timing, "attenuation_fill"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(phase_timing.Timing, "fourier_loop"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(phase_timing.Timing, "plm_basis"));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(phase_timing.Timing, "rt_layer_build"));
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(phase_timing.Timing, "rt_layer_phase_matrix"));
    try std.testing.expectEqual(@as(usize, 96), @offsetOf(phase_timing.Timing, "rt_layer_doubling"));
    try std.testing.expectEqual(@as(usize, 112), @offsetOf(phase_timing.Timing, "fixed_qseries_work"));
    try std.testing.expectEqual(@as(usize, 128), @offsetOf(phase_timing.Timing, "fixed_rd_update"));
    try std.testing.expectEqual(@as(usize, 144), @offsetOf(phase_timing.Timing, "fixed_tu_update"));
    try std.testing.expectEqual(@as(usize, 160), @offsetOf(phase_timing.Timing, "fixed_td_update"));
    try std.testing.expectEqual(@as(usize, 176), @offsetOf(phase_timing.Timing, "orders_total"));
    try std.testing.expectEqual(@as(usize, 192), @offsetOf(phase_timing.Timing, "orders_initial_sources"));
    try std.testing.expectEqual(@as(usize, 208), @offsetOf(phase_timing.Timing, "orders_initial_transport"));
    try std.testing.expectEqual(@as(usize, 224), @offsetOf(phase_timing.Timing, "orders_local_down"));
    try std.testing.expectEqual(@as(usize, 240), @offsetOf(phase_timing.Timing, "orders_local_up"));
    try std.testing.expectEqual(@as(usize, 256), @offsetOf(phase_timing.Timing, "orders_transport"));
    try std.testing.expectEqual(@as(usize, 272), @offsetOf(phase_timing.Timing, "orders_accumulate"));
    try std.testing.expectEqual(@as(usize, 288), @offsetOf(phase_timing.Timing, "reflectance_integral"));
    try std.testing.expectEqual(@as(usize, 304), @offsetOf(phase_timing.Timing, "fixed_doubling_steps"));
    try std.testing.expectEqual(@as(usize, 312), @offsetOf(phase_timing.Timing, "fixed_qseries_skipped"));
    try std.testing.expectEqual(@as(usize, 320), @offsetOf(phase_timing.Timing, "fixed_qseries_retained"));
    try std.testing.expectEqual(@as(usize, 328), @offsetOf(phase_timing.Timing, "fixed_rd_skipped"));
    try std.testing.expectEqual(@as(usize, 336), @offsetOf(phase_timing.Timing, "fixed_rd_retained"));
    try std.testing.expectEqual(@as(usize, 344), @offsetOf(phase_timing.Timing, "fixed_tu_skipped"));
    try std.testing.expectEqual(@as(usize, 352), @offsetOf(phase_timing.Timing, "fixed_tu_retained"));
    try std.testing.expectEqual(@as(usize, 360), @offsetOf(phase_timing.Timing, "fixed_td_skipped"));
    try std.testing.expectEqual(@as(usize, 368), @offsetOf(phase_timing.Timing, "fixed_td_retained"));
}
