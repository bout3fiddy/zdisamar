const core = @import("../../core/diagnostics.zig");

pub const Provider = struct {
    id: []const u8,
    materialize: *const fn (spec: core.DiagnosticsSpec, summary: []const u8) core.Diagnostics,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.default_diagnostics")) {
        return .{
            .id = provider_id,
            .materialize = core.Diagnostics.fromSpec,
        };
    }
    return null;
}

const std = @import("std");
