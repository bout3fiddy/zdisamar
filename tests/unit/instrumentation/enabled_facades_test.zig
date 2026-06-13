const std = @import("std");
const internal = @import("internal");

test "instrumentation facades compile when enabled by build options" {
    const zone = internal.instrumentation.trace.staticZone(@src(), "wp2.enabled");
    zone.end();

    const context = internal.instrumentation.telemetry.currentContext();
    internal.instrumentation.telemetry.setContext(context);
    internal.instrumentation.telemetry.clearContext();

    _ = internal.instrumentation.sensitivity.enabled;
    try exerciseEnabledPhaseTiming();
    try std.testing.expect(true);
}

fn exerciseEnabledPhaseTiming() !void {
    // exerciseEnabledPhaseTiming ----------------------------------------------------------------------------|
    // Compile and exercise the trace-build branch of transport phase timing.                                 |
    // -------------------------------------------------------------------------------------------------------|
    const phase_timing = internal.rtm.phase_timing;

    try std.testing.expectEqual(true, phase_timing.enabled);
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(phase_timing.WorkspaceState));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_timing.WorkspaceState));

    var timing = phase_timing.Timing{};
    var state = phase_timing.WorkspaceState{};
    phase_timing.setWorkspaceState(&state, &timing);

    const active = phase_timing.activeWorkspaceState(&state) orelse return error.MissingActivePhaseTiming;
    phase_timing.count(active, "fixed_doubling_steps", 3);
    try std.testing.expectEqual(@as(u64, 3), timing.fixed_doubling_steps.count);

    const start = phase_timing.start(active);
    phase_timing.finish(active, start, "fixed_qseries_work");
    try std.testing.expect(timing.fixed_qseries_work.count <= 1);

    phase_timing.clearWorkspaceState(&state);
    try std.testing.expectEqual(null, phase_timing.activeWorkspaceState(&state));
}
