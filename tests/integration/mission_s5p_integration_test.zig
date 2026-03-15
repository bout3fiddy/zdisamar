const std = @import("std");
const zdisamar = @import("zdisamar");

test "s5p mission adapter drives typed engine execution" {
    const mission_run = zdisamar.mission_s5p.build(.{
        .scene_id = "s5p-no2",
        .destination_uri = "file://out/s5p-no2.nc",
    });

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const plan = try engine.preparePlan(mission_run.plan_template);
    var workspace = engine.createWorkspace("mission-suite");
    const result = try engine.execute(&plan, &workspace, mission_run.request);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("s5p-no2", result.scene_id);
    try std.testing.expectEqualStrings("transport.dispatcher", result.provenance.solver_route);
    try std.testing.expectEqual(.netcdf_cf, mission_run.export_request.format);
}

test "s5p operational mission adapter drives engine execution from measured spectral input" {
    const mission_run = try zdisamar.mission_s5p.buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-operational",
        .spectral_input_path = "data/examples/irr_rad_channels_demo.txt",
        .destination_uri = "file://out/s5p-operational.nc",
    });

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const plan = try engine.preparePlan(mission_run.plan_template);
    var workspace = engine.createWorkspace("mission-operational");
    const result = try engine.execute(&plan, &workspace, mission_run.request);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("s5p-operational", result.scene_id);
    try std.testing.expectEqual(@as(u32, 2), mission_run.measurement_summary.?.sample_count);
    try std.testing.expectEqualStrings("measured_channels", mission_run.request.scene.observation_model.sampling);
}
