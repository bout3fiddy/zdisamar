const std = @import("std");

const EngineOptions = @import("../../core/Engine.zig").EngineOptions;
const DiagnosticsSpec = @import("../../core/diagnostics.zig").DiagnosticsSpec;
const Result = @import("../../core/Result.zig").Result;
const c_api = @import("../c/bridge.zig");

pub const DiagnosticsFlags = packed struct(u32) {
    provenance: bool = true,
    jacobians: bool = false,
    _padding: u30 = 0,

    pub fn fromSpec(spec: DiagnosticsSpec) DiagnosticsFlags {
        return .{
            .provenance = spec.provenance,
            .jacobians = spec.jacobians,
        };
    }

    pub fn toMask(self: DiagnosticsFlags) u32 {
        return @bitCast(self);
    }
};

pub const EngineOptionsView = struct {
    options: EngineOptions = .{},

    pub fn toC(self: EngineOptionsView) c_api.EngineOptionsDesc {
        const max_prepared_plans = std.math.cast(u32, self.options.max_prepared_plans) orelse
            @panic("max_prepared_plans exceeds C ABI capacity");
        return c_api.defaultEngineOptions(
            if (self.options.allow_native_plugins) .allow_trusted_native else .declarative_only,
            max_prepared_plans,
        );
    }
};

pub fn describeResult(result: Result) c_api.ResultDesc {
    return c_api.describeResult(result);
}

test "diagnostics flags preserve the request spec bits" {
    const flags = DiagnosticsFlags.fromSpec(.{
        .provenance = true,
        .jacobians = true,
    });

    try std.testing.expect(flags.provenance);
    try std.testing.expect(flags.jacobians);
    try std.testing.expectEqual(@as(u32, 0b11), flags.toMask() & 0b11);
}

test "engine options view converts typed options to the C ABI descriptor" {
    const desc = (EngineOptionsView{
        .options = .{
            .allow_native_plugins = true,
            .max_prepared_plans = 12,
        },
    }).toC();

    try std.testing.expectEqual(c_api.PluginPolicy.allow_trusted_native, desc.plugin_policy);
    try std.testing.expectEqual(@as(u32, 12), desc.max_prepared_plans);
}
