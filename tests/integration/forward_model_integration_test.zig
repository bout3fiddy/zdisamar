const std = @import("std");
const zdisamar = @import("zdisamar");

test "engine execute materializes measurement-space summaries through the typed forward path" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .limb,
            .derivative_mode = .semi_analytical,
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 48,
            },
            .layer_count_hint = 24,
            .measurement_count_hint = 48,
        },
    });

    var workspace = engine.createWorkspace("forward-integration");
    var request = zdisamar.Request.init(.{
        .id = "scene-forward-integration",
        .atmosphere = .{
            .layer_count = 24,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.15,
        },
        .surface = .{
            .albedo = 0.08,
        },
        .observation_model = .{
            .instrument = "integration-synthetic",
            .regime = .limb,
            .sampling = "operational",
            .noise_model = "shot_noise",
        },
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 48,
        },
    });
    request.expected_derivative_mode = .semi_analytical;
    request.diagnostics = .{
        .provenance = true,
        .jacobians = true,
    };

    const result = try engine.execute(&plan, &workspace, request);
    const measurement_space = result.measurement_space orelse return error.MissingMeasurementSummary;

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqual(@as(u32, 48), measurement_space.sample_count);
    try std.testing.expect(measurement_space.mean_radiance > 0.0);
    try std.testing.expect(measurement_space.mean_irradiance > 0.0);
    try std.testing.expect(measurement_space.mean_reflectance > 0.0);
    try std.testing.expect(measurement_space.mean_noise_sigma > 0.0);
    try std.testing.expect(measurement_space.mean_jacobian != null);
}
