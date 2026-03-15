pub const Level = enum(u8) {
    debug,
    info,
    warn,
    err,
};

pub const Scope = enum {
    engine,
    plan,
    workspace,
    runtime,
    plugin,
    adapter,
    api,
};

pub const Policy = struct {
    minimum: Level = .info,

    pub fn allows(self: Policy, level: Level) bool {
        return @intFromEnum(level) >= @intFromEnum(self.minimum);
    }
};

test "logging policy filters lower-severity messages" {
    const policy: Policy = .{ .minimum = .warn };
    try std.testing.expect(!policy.allows(.info));
    try std.testing.expect(policy.allows(.warn));
    try std.testing.expect(policy.allows(.err));
}

const std = @import("std");
