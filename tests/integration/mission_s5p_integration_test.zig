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

    var plan = try engine.preparePlan(mission_run.plan_template);
    defer plan.deinit();
    var workspace = engine.createWorkspace("mission-suite");
    var result = try engine.execute(&plan, &workspace, mission_run.request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("s5p-no2", result.scene_id);
    try std.testing.expectEqualStrings("builtin.dispatcher", result.provenance.solver_route);
    try std.testing.expectEqual(.netcdf_cf, mission_run.export_request.format);
    try std.testing.expect(result.measurement_space_product != null);
}

test "s5p operational mission adapter drives engine execution from measured spectral input" {
    var mission_run = try zdisamar.mission_s5p.buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-operational",
        .spectral_input_path = "data/examples/irr_rad_channels_demo.txt",
        .destination_uri = "file://out/s5p-operational.nc",
    });
    defer mission_run.deinit(std.testing.allocator);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(mission_run.plan_template);
    defer plan.deinit();
    var workspace = engine.createWorkspace("mission-operational");
    var result = try engine.execute(&plan, &workspace, mission_run.request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("s5p-operational", result.scene_id);
    try std.testing.expectEqual(@as(u32, 2), mission_run.measurement_summary.?.sample_count);
    try std.testing.expectEqualStrings("measured_channels", mission_run.request.scene.observation_model.sampling);
    try std.testing.expect(result.measurement_space_product != null);
    try std.testing.expect(result.measurement_space_product.?.noise_sigma[0] > 0.0);
    try std.testing.expect(result.measurement_space_product.?.noise_sigma[1] > 0.0);
}

test "s5p operational mission adapter applies geometry and auxiliary metadata replacements" {
    var mission_run = try zdisamar.mission_s5p.buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-operational-aux",
        .spectral_input_path = "data/examples/irr_rad_channels_operational_aux_demo.txt",
        .destination_uri = "file://out/s5p-operational-aux.nc",
    });
    defer mission_run.deinit(std.testing.allocator);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(mission_run.plan_template);
    defer plan.deinit();
    var workspace = engine.createWorkspace("mission-operational-aux");
    var result = try engine.execute(&plan, &workspace, mission_run.request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqual(@as(f64, 31.7), mission_run.request.scene.geometry.solar_zenith_deg);
    try std.testing.expectEqual(@as(f64, 143.4), mission_run.request.scene.geometry.relative_azimuth_deg);
    try std.testing.expect(mission_run.request.scene.atmosphere.has_clouds);
    try std.testing.expect(mission_run.request.scene.atmosphere.has_aerosols);
    try std.testing.expectEqual(@as(f64, 0.065), mission_run.request.scene.surface.albedo);
    try std.testing.expectEqual(@as(f64, 0.018), mission_run.request.scene.observation_model.wavelength_shift_nm);
    try std.testing.expectEqual(@as(f64, 0.54), mission_run.request.scene.observation_model.instrument_line_fwhm_nm);
    try std.testing.expectEqual(@as(u32, 3), mission_run.measurement_summary.?.sample_count);
    try std.testing.expect(result.measurement_space_product.?.wavelengths[0] > 405.0);
    try std.testing.expect(result.measurement_space_product != null);
}

test "s5p operational mission adapter executes explicit isrf table metadata" {
    var mission_run = try zdisamar.mission_s5p.buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-operational-isrf-table",
        .spectral_input_path = "data/examples/irr_rad_channels_operational_isrf_table_demo.txt",
        .destination_uri = "file://out/s5p-operational-isrf-table.nc",
    });
    defer mission_run.deinit(std.testing.allocator);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(mission_run.plan_template);
    defer plan.deinit();
    var workspace = engine.createWorkspace("mission-operational-isrf-table");
    var result = try engine.execute(&plan, &workspace, mission_run.request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqual(@as(f64, 0.08), mission_run.request.scene.observation_model.high_resolution_step_nm);
    try std.testing.expectEqual(@as(f64, 0.32), mission_run.request.scene.observation_model.high_resolution_half_span_nm);
    try std.testing.expectEqual(@as(u8, 5), mission_run.request.scene.observation_model.instrument_line_shape.sample_count);
    try std.testing.expectEqual(@as(u16, 3), mission_run.request.scene.observation_model.instrument_line_shape_table.nominal_count);
    try std.testing.expectEqual(@as(f64, 406.0), mission_run.request.scene.observation_model.instrument_line_shape_table.nominal_wavelengths_nm[1]);
    try std.testing.expect(result.measurement_space_product != null);
    try std.testing.expect(result.measurement_space_product.?.radiance[0] > 0.0);
}

test "s5p operational mission adapter executes O2 and O2-O2 refspec replacement metadata" {
    var mission_run = try zdisamar.mission_s5p.buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-operational-refspec",
        .spectral_input_path = "data/examples/irr_rad_channels_operational_refspec_demo.txt",
        .destination_uri = "file://out/s5p-operational-refspec.nc",
        .sampling = "operational",
        .noise_model = "s5p_operational",
    });
    defer mission_run.deinit(std.testing.allocator);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(mission_run.plan_template);
    defer plan.deinit();
    var workspace = engine.createWorkspace("mission-operational-refspec");
    var result = try engine.execute(&plan, &workspace, mission_run.request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expect(mission_run.request.scene.observation_model.operational_refspec_grid.enabled());
    try std.testing.expect(mission_run.request.scene.observation_model.operational_solar_spectrum.enabled());
    try std.testing.expect(mission_run.request.scene.observation_model.o2_operational_lut.enabled());
    try std.testing.expect(mission_run.request.scene.observation_model.o2o2_operational_lut.enabled());
    try std.testing.expect(result.measurement_space_product != null);
    try std.testing.expect(result.measurement_space_product.?.cia_optical_depth > 0.0);
    try std.testing.expect(result.measurement_space_product.?.radiance.len == 3);
    try std.testing.expect(result.measurement_space_product.?.radiance[0] > 0.0);
    try std.testing.expect(result.measurement_space_product.?.radiance[1] > 0.0);
    try std.testing.expect(result.measurement_space_product.?.radiance[2] > 0.0);
    try std.testing.expect(result.measurement_space_product.?.irradiance[0] > result.measurement_space_product.?.irradiance[1]);
    try std.testing.expect(result.measurement_space_product.?.irradiance[1] > result.measurement_space_product.?.irradiance[2]);
}
