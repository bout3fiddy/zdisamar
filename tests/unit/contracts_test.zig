const std = @import("std");
const zdisamar = @import("zdisamar");

test "engine lifecycle increments plan ids and returns successful result" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();

    var first_plan = try engine.preparePlan(.{});
    defer first_plan.deinit();
    var second_plan = try engine.preparePlan(.{});
    defer second_plan.deinit();
    try std.testing.expectEqual(@as(u64, 1), first_plan.id);
    try std.testing.expectEqual(@as(u64, 2), second_plan.id);

    var workspace = engine.createWorkspace("unit-suite");
    const request = zdisamar.Request.init(.{
        .id = "scene-unit-001",
        .spectral_grid = .{ .sample_count = 16 },
    });
    var result = try engine.execute(&first_plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("scene-unit-001", result.scene_id);
    try std.testing.expectEqualStrings("builtin.dispatcher", result.provenance.solver_route);
    try std.testing.expect(result.measurement_space_product != null);
}

test "engine execute rejects missing scene id" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();
    var plan = try engine.preparePlan(.{});
    defer plan.deinit();
    var workspace = engine.createWorkspace("unit-suite");

    var invalid_request = zdisamar.Request.init(.{ .id = "" });
    try std.testing.expectError(
        error.MissingScene,
        engine.execute(&plan, &workspace, &invalid_request),
    );
}
