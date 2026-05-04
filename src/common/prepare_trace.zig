const std = @import("std");

const env_name = "ZDISAMAR_TRACE_O2A_PREPARE";

pub const Trace = struct {
    enabled: bool,
    previous_ns: i128,
    start_ns: i128,

    pub fn init() Trace {
        const enabled = std.process.hasEnvVarConstant(env_name);
        const now = if (enabled) std.time.nanoTimestamp() else 0;
        return .{
            .enabled = enabled,
            .previous_ns = now,
            .start_ns = now,
        };
    }

    pub fn mark(self: *Trace, label: []const u8) void {
        if (!self.enabled) return;
        const now = std.time.nanoTimestamp();
        std.debug.print(
            "o2a_prepare_trace {s} delta_ms={d:.3} total_ms={d:.3}\n",
            .{
                label,
                nsToMs(now - self.previous_ns),
                nsToMs(now - self.start_ns),
            },
        );
        self.previous_ns = now;
    }
};

fn nsToMs(ns: i128) f64 {
    return @as(f64, @floatFromInt(ns)) / 1.0e6;
}
