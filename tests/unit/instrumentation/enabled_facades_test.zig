const std = @import("std");
const internal = @import("internal");

test "instrumentation facades compile when enabled by build options" {
    const zone = internal.instrumentation.trace.staticZone(@src(), "instrumentation.enabled");
    zone.end();

    const context = internal.instrumentation.telemetry.currentContext();
    internal.instrumentation.telemetry.setContext(context);
    internal.instrumentation.telemetry.clearContext();

    _ = internal.instrumentation.sensitivity.enabled;
    try exerciseEnabledCostTiming();
    try std.testing.expect(true);
}

fn exerciseEnabledCostTiming() !void {
    // exerciseEnabledCostTiming -----------------------------------------------------------------------------|
    // Compile and exercise the enabled branch of transport cost timing.                                      |
    // -------------------------------------------------------------------------------------------------------|
    const cost_timing = internal.instrumentation.cost_timing;

    try std.testing.expectEqual(true, cost_timing.enabled);
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(cost_timing.WorkspaceState));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(cost_timing.WorkspaceState));
    try std.testing.expectEqual(@as(usize, 456), @sizeOf(cost_timing.WorkerStageCost));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(cost_timing.WorkerStageCost));

    var timing = cost_timing.StageCost{};
    var state = cost_timing.WorkspaceState{};
    cost_timing.setWorkspaceState(&state, &timing);

    const active = cost_timing.activeWorkspaceState(&state) orelse return error.MissingActiveCostTiming;
    cost_timing.count(active, "fixed_doubling_steps", 3);
    try std.testing.expectEqual(@as(u64, 3), timing.fixed_doubling_steps.count);

    const start = cost_timing.start(active);
    cost_timing.finish(active, start, "fixed_qseries_work");
    try std.testing.expect(timing.fixed_qseries_work.count <= 1);

    cost_timing.clearWorkspaceState(&state);
    try std.testing.expectEqual(null, cost_timing.activeWorkspaceState(&state));
}
