const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const c_api = internal.c_api;
const zig_wrappers = internal.zig_wrappers;

test "zig API wrappers expose diagnostics flags and result descriptors" {
    const flags = zig_wrappers.DiagnosticsFlags.fromSpec(.{
        .provenance = true,
        .jacobians = false,
    });
    try std.testing.expect(flags.provenance);
    try std.testing.expect(!flags.jacobians);

    var result = try zdisamar.Result.init(std.testing.allocator, 9, "workspace-a", "scene-a", .{
        .plan_id = 9,
        .workspace_label = "workspace-a",
        .scene_id = "scene-a",
    });
    defer result.deinit(std.testing.allocator);
    const described = zig_wrappers.describeResult(result);
    try std.testing.expectEqual(@as(u64, 9), described.plan_id);
    try std.testing.expectEqual(c_api.StatusCode.ok, described.status);
}

test "zig API wrappers expose a typed C-view conversion boundary" {
    const desc = try (zig_wrappers.EngineOptionsView{
        .options = .{ .max_prepared_plans = 3 },
    }).toC();
    try std.testing.expectEqual(@as(u32, 3), desc.max_prepared_plans);
}
