//! Purpose:
//!   Define the minimal logging vocabulary shared across engine, runtime, plugin, and
//!   adapter code without introducing a global logging backend.
//!
//! Physics:
//!   This file is infrastructure only; it does not encode a scientific model.
//!
//! Vendor:
//!   `engine diagnostics severity policy`
//!
//! Design:
//!   Logging remains a typed policy check so higher layers can decide how to route or
//!   suppress messages without coupling the core to I/O.
//!
//! Invariants:
//!   Severity ordering follows the enum discriminants and policy checks are pure.
//!
//! Validation:
//!   Unit tests below verify the minimum-severity filter behavior.
const std = @import("std");

/// Purpose:
///   Order log messages by severity for policy filtering.
pub const Level = enum(u8) {
    debug,
    info,
    warn,
    err,
};

/// Purpose:
///   Tag which engine surface emitted a message.
pub const Scope = enum {
    engine,
    plan,
    workspace,
    runtime,
    plugin,
    adapter,
    api,
};

/// Purpose:
///   Hold the minimum severity a caller wants to emit.
pub const Policy = struct {
    minimum: Level = .info,

    /// Purpose:
    ///   Report whether the policy admits the requested severity.
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
