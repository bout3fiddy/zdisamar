const std = @import("std");
const zdisamar = @import("zdisamar");

test "integration lifecycle preserves typed plan and provenance route" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .model_family = "disamar_standard",
        .solver_mode = .derivative_enabled,
    });
    defer plan.deinit();
    var workspace = engine.createWorkspace("integration-suite");

    const request = zdisamar.Request.init(.{
        .id = "scene-integration-derivative",
        .spectral_grid = .{ .sample_count = 32 },
    });
    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqual(@as(u64, 1), result.plan_id);
    try std.testing.expectEqualStrings("disamar_standard", result.provenance.model_family);
    try std.testing.expectEqualStrings("derivative_enabled", result.provenance.numerical_mode);
    try std.testing.expectEqualStrings("integration-suite", result.workspace_label);
    try std.testing.expect(result.measurement_space_product != null);
}
