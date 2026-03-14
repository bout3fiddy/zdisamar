const std = @import("std");
const PlanModule = @import("../../core/Plan.zig");
const Result = @import("../../core/Result.zig").Result;

pub const abi_version: u32 = 1;
pub const plugin_abi_version: u32 = 1;
pub const plugin_entry_symbol: [:0]const u8 = "zdisamar_plugin_entry_v1";

pub const SolverMode = enum(u32) {
    scalar = 0,
    polarized = 1,
    derivative_enabled = 2,
};

pub const PluginPolicy = enum(u32) {
    declarative_only = 0,
    allow_trusted_native = 1,
};

pub const PluginLane = enum(u32) {
    declarative = 0,
    native = 1,
};

pub const EngineOptionsDesc = extern struct {
    struct_size: u32,
    abi_version: u32,
    plugin_policy: PluginPolicy,
    max_prepared_plans: u32,
};

pub const PlanDesc = extern struct {
    model_family: [*:0]const u8,
    transport_solver: [*:0]const u8,
    retrieval_algorithm: ?[*:0]const u8 = null,
    solver_mode: SolverMode = .scalar,
    expected_plugin_abi_version: u32 = plugin_abi_version,
};

pub const ResultDesc = extern struct {
    plan_id: u64,
    status: u32,
    plugin_count: u32,
};

pub fn defaultEngineOptions(plugin_policy: PluginPolicy, max_prepared_plans: u32) EngineOptionsDesc {
    return .{
        .struct_size = @sizeOf(EngineOptionsDesc),
        .abi_version = abi_version,
        .plugin_policy = plugin_policy,
        .max_prepared_plans = max_prepared_plans,
    };
}

pub fn toSolverMode(mode: PlanModule.SolverMode) SolverMode {
    return switch (mode) {
        .scalar => .scalar,
        .polarized => .polarized,
        .derivative_enabled => .derivative_enabled,
    };
}

pub fn describeResult(result: Result) ResultDesc {
    return .{
        .plan_id = result.plan_id,
        .status = switch (result.status) {
            .success => 0,
            .invalid_request => 1,
            .internal_error => 2,
        },
        .plugin_count = @as(u32, @intCast(result.provenance.plugin_versions.len)),
    };
}

test "default engine options lock C ABI fields" {
    const options = defaultEngineOptions(.declarative_only, 64);
    try std.testing.expectEqual(@as(u32, @sizeOf(EngineOptionsDesc)), options.struct_size);
    try std.testing.expectEqual(abi_version, options.abi_version);
    try std.testing.expectEqual(PluginPolicy.declarative_only, options.plugin_policy);
    try std.testing.expectEqual(@as(u32, 64), options.max_prepared_plans);
}

test "result description counts plugin provenance entries" {
    const result = Result.init(7, "workspace-a", "scene-a", .{
        .plan_id = 7,
        .workspace_label = "workspace-a",
        .scene_id = "scene-a",
    });
    const described = describeResult(result);
    try std.testing.expectEqual(@as(u64, 7), described.plan_id);
    try std.testing.expectEqual(@as(u32, 0), described.plugin_count);
}
