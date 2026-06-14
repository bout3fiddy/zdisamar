const std = @import("std");
const internal = @import("internal");

test "instrumentation facades compile in disabled configuration" {
    const zone = internal.instrumentation.trace.staticZone(@src(), "instrumentation.disabled");
    zone.end();

    const context = internal.instrumentation.telemetry.currentContext();
    internal.instrumentation.telemetry.setContext(context);
    internal.instrumentation.telemetry.clearContext();

    try std.testing.expectEqual(false, internal.instrumentation.sensitivity.enabled);
}
