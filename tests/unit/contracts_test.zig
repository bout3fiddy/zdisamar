const std = @import("std");
const zdisamar = @import("zdisamar");

test "engine lifecycle increments plan ids and returns successful result" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();

    const first_plan = try engine.preparePlan(.{});
    const second_plan = try engine.preparePlan(.{});
    try std.testing.expectEqual(@as(u64, 1), first_plan.id);
    try std.testing.expectEqual(@as(u64, 2), second_plan.id);

    var workspace = engine.createWorkspace("unit-suite");
    const request = zdisamar.Request.init(.{
        .id = "scene-unit-001",
        .spectral_grid = .{ .sample_count = 16 },
    });
    const result = try engine.execute(&first_plan, &workspace, request);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("scene-unit-001", result.scene_id);
    try std.testing.expectEqualStrings("transport.dispatcher", result.provenance.solver_route);
}

test "engine execute rejects missing scene id" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();
    const plan = try engine.preparePlan(.{});
    var workspace = engine.createWorkspace("unit-suite");

    try std.testing.expectError(
        error.MissingScene,
        engine.execute(&plan, &workspace, zdisamar.Request.init(.{ .id = "" })),
    );
}
