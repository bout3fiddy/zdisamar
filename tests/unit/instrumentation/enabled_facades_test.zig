const std = @import("std");
const internal = @import("internal");

test "instrumentation facades compile when enabled by build options" {
    const zone = internal.instrumentation.trace.staticZone(@src(), "wp2.enabled");
    zone.end();

    const context = internal.instrumentation.telemetry.currentContext();
    internal.instrumentation.telemetry.setContext(context);
    internal.instrumentation.telemetry.clearContext();

    _ = internal.instrumentation.sensitivity.enabled;
    try std.testing.expect(true);
}
