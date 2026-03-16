const std = @import("std");
const zdisamar = @import("zdisamar");

test "zig API wrappers expose diagnostics flags and result descriptors" {
    const flags = zdisamar.zig_wrappers.DiagnosticsFlags.fromSpec(.{
        .provenance = true,
        .jacobians = false,
        .internal_fields = true,
        .materialize_cache_keys = true,
    });
    try std.testing.expect(flags.provenance);
    try std.testing.expect(!flags.jacobians);
    try std.testing.expect(flags.internal_fields);
    try std.testing.expect(flags.materialize_cache_keys);

    const result = zdisamar.Result.init(9, "workspace-a", "scene-a", .{
        .plan_id = 9,
        .workspace_label = "workspace-a",
        .scene_id = "scene-a",
    });
    const described = zdisamar.zig_wrappers.describeResult(result);
    try std.testing.expectEqual(@as(u64, 9), described.plan_id);
    try std.testing.expectEqual(zdisamar.c_api.StatusCode.ok, described.status);
}
