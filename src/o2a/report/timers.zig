const std = @import("std");

pub const Timer = struct {
    started_at_ns: ?u64 = null,
    elapsed_ns: u64 = 0,

    pub fn start(self: *Timer) void {
        self.started_at_ns = std.time.nanoTimestamp();
    }

    pub fn stop(self: *Timer) void {
        const started_at_ns = self.started_at_ns orelse return;
        const now = std.time.nanoTimestamp();
        self.elapsed_ns += @intCast(@max(now - started_at_ns, 0));
        self.started_at_ns = null;
    }
};
