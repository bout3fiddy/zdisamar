const std = @import("std");
const zdisamar = @import("zdisamar");

fn uniqueScratchPath(prefix: []const u8, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "zig-cache/{s}-{d}.txt",
        .{ prefix, @as(u64, @intCast(@abs(std.time.nanoTimestamp()))) },
    );
}

fn averageSpacingNm(wavelengths_nm: []const f64) f64 {
    if (wavelengths_nm.len < 2) return 1.0;

    var spacing_sum: f64 = 0.0;
    for (wavelengths_nm[0 .. wavelengths_nm.len - 1], wavelengths_nm[1..]) |left_nm, right_nm| {
        spacing_sum += right_nm - left_nm;
    }
    return spacing_sum / @as(f64, @floatFromInt(wavelengths_nm.len - 1));
}

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
    var result = try engine.execute(&plan, &workspace, &mission_run.request);
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
    var result = try engine.execute(&plan, &workspace, &mission_run.request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("s5p-operational", result.scene_id);
    try std.testing.expectEqual(@as(u32, 2), mission_run.measurement_summary.?.sample_count);
    try std.testing.expect(mission_run.observed_measurement_product != null);
    try std.testing.expect(mission_run.request.measurement_binding != null);
    try std.testing.expectApproxEqAbs(@as(f64, 1.116153e13), mission_run.observed_measurement_product.?.radiance[0], 1.0e8);
    try std.testing.expectApproxEqAbs(@as(f64, 3.402296e14), mission_run.observed_measurement_product.?.irradiance[0], 1.0e9);
    try std.testing.expectEqual(zdisamar.Instrument.SamplingMode.measured_channels, mission_run.request.scene.observation_model.sampling);
    try std.testing.expectEqual(@as(usize, 2), mission_run.request.scene.observation_model.measured_wavelengths_nm.len);
    try std.testing.expectApproxEqAbs(@as(f64, 405.0), mission_run.request.scene.observation_model.measured_wavelengths_nm[0], 1.0e-12);
    try std.testing.expect(mission_run.request.scene.observation_model.operational_solar_spectrum.enabled());
    try std.testing.expect(result.measurement_space_product != null);
    try std.testing.expect(result.measurement_space_product.?.noise_sigma[0] > 0.0);
    try std.testing.expect(result.measurement_space_product.?.noise_sigma[1] > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 405.0), result.measurement_space_product.?.wavelengths[0], 1.0e-12);
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
    var result = try engine.execute(&plan, &workspace, &mission_run.request);
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
    try std.testing.expect(result.measurement_space_product != null);
    try std.testing.expectApproxEqAbs(@as(f64, 405.0), result.measurement_space_product.?.wavelengths[0], 1.0e-12);
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
    var result = try engine.execute(&plan, &workspace, &mission_run.request);
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
        .sampling = .operational,
        .noise_model = .s5p_operational,
    });
    defer mission_run.deinit(std.testing.allocator);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(mission_run.plan_template);
    defer plan.deinit();
    var workspace = engine.createWorkspace("mission-operational-refspec");
    var result = try engine.execute(&plan, &workspace, &mission_run.request);
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

    const product = result.measurement_space_product.?;
    const reference_radiance = mission_run.request.scene.observation_model.reference_radiance;
    const reference_sigma = mission_run.request.scene.observation_model.ingested_noise_sigma;
    const reference_spacing = mission_run.request.scene.observation_model.resolvedChannelControls(.radiance).noise.reference_bin_width_nm;
    const current_spacing = averageSpacingNm(product.wavelengths);
    const spacing_factor = std.math.sqrt(reference_spacing / current_spacing);
    for (product.radiance, product.noise_sigma, reference_radiance, reference_sigma) |radiance, sigma, ref_radiance, ref_sigma| {
        const expected_sigma = ref_sigma * std.math.sqrt(radiance / ref_radiance) * spacing_factor;
        try std.testing.expectApproxEqRel(expected_sigma, sigma, 1.0e-9);
    }
}

test "s5p operational mission adapter rejects irradiance-only observed input files" {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try uniqueScratchPath("irr-only-operational", &path_buffer);
    defer std.fs.cwd().deleteFile(path) catch {};

    const fixture =
        \\meta solar_zenith_deg 31.9
        \\meta viewing_zenith_deg 7.8
        \\meta relative_azimuth_deg 142.6
        \\start_channel_irr
        \\irr 760.8 3020.0 2.702296E+14
        \\irr 761.0 3010.0 2.682296E+14
        \\irr 761.2 3000.0 2.662296E+14
        \\end_channel_irr
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = fixture });

    try std.testing.expectError(error.InvalidOperationalInput, zdisamar.mission_s5p.buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-operational-irr-only",
        .spectral_input_path = path,
        .destination_uri = "file://out/s5p-operational-irr-only.nc",
    }));
}

test "s5p operational mission adapter corrects irradiance onto the radiance grid when wavelengths differ slightly" {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try uniqueScratchPath("irr-rad-shifted", &path_buffer);
    defer std.fs.cwd().deleteFile(path) catch {};

    const fixture =
        \\meta hires_wavelength_1 406.0
        \\meta hires_wavelength_2 406.1
        \\meta hires_wavelength_3 406.2
        \\meta hires_solar_1 4.00e14
        \\meta hires_solar_2 3.90e14
        \\meta hires_solar_3 3.80e14
        \\start_channel_irr
        \\irr 406.00 3000.0 4.00E+14
        \\irr 406.10 3000.0 3.90E+14
        \\end_channel_irr
        \\start_channel_rad
        \\rad 406.01 1500.0 1.20E+13
        \\rad 406.11 1500.0 1.10E+13
        \\end_channel_rad
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = fixture });

    var mission_run = try zdisamar.mission_s5p.buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-operational-shifted",
        .spectral_input_path = path,
        .destination_uri = "file://out/s5p-operational-shifted.nc",
    });
    defer mission_run.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 3.99e14), mission_run.observed_measurement_product.?.irradiance[0], 1.0e9);
    try std.testing.expectApproxEqAbs(@as(f64, 3.89e14), mission_run.observed_measurement_product.?.irradiance[1], 1.0e9);
}

test "s5p operational mission adapter rejects irradiance wavelengths that drift too far from radiance wavelengths" {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try uniqueScratchPath("irr-rad-mismatch", &path_buffer);
    defer std.fs.cwd().deleteFile(path) catch {};

    const fixture =
        \\meta hires_wavelength_1 406.0
        \\meta hires_wavelength_2 406.2
        \\meta hires_solar_1 4.00e14
        \\meta hires_solar_2 3.80e14
        \\start_channel_irr
        \\irr 406.00 3000.0 4.00E+14
        \\irr 406.10 3000.0 3.90E+14
        \\end_channel_irr
        \\start_channel_rad
        \\rad 406.08 1500.0 1.20E+13
        \\rad 406.18 1500.0 1.10E+13
        \\end_channel_rad
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = fixture });

    try std.testing.expectError(error.InvalidOperationalInput, zdisamar.mission_s5p.buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-operational-mismatch",
        .spectral_input_path = path,
        .destination_uri = "file://out/s5p-operational-mismatch.nc",
    }));
}

test "s5p operational mission adapter carries non-unity reference-bin scaling through engine execution" {
    var mission_run = try zdisamar.mission_s5p.buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-operational-bin-scale",
        .spectral_input_path = "data/examples/irr_rad_channels_operational_refspec_demo.txt",
        .destination_uri = "file://out/s5p-operational-bin-scale.nc",
        .sampling = .operational,
        .noise_model = .s5p_operational,
    });
    defer mission_run.deinit(std.testing.allocator);

    std.testing.allocator.free(mission_run.request.scene.observation_model.measured_wavelengths_nm);
    mission_run.request.scene.observation_model.measured_wavelengths_nm = &.{};
    mission_run.request.scene.observation_model.owns_measured_wavelengths = false;
    mission_run.request.scene.spectral_grid = .{
        .start_nm = 760.8,
        .end_nm = 761.4,
        .sample_count = 3,
    };
    mission_run.plan_template.scene_blueprint.spectral_grid = mission_run.request.scene.spectral_grid;

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(mission_run.plan_template);
    defer plan.deinit();
    var workspace = engine.createWorkspace("mission-operational-bin-scale");
    var result = try engine.execute(&plan, &workspace, &mission_run.request);
    defer result.deinit(std.testing.allocator);

    const product = result.measurement_space_product.?;
    const reference_radiance = mission_run.request.scene.observation_model.reference_radiance;
    const reference_sigma = mission_run.request.scene.observation_model.ingested_noise_sigma;
    const reference_spacing = mission_run.request.scene.observation_model.resolvedChannelControls(.radiance).noise.reference_bin_width_nm;
    const current_spacing = averageSpacingNm(product.wavelengths);
    const spacing_factor = std.math.sqrt(reference_spacing / current_spacing);

    for (product.radiance, product.noise_sigma, reference_radiance, reference_sigma) |radiance, sigma, ref_radiance, ref_sigma| {
        const expected_sigma = ref_sigma * std.math.sqrt(radiance / ref_radiance) * spacing_factor;
        try std.testing.expectApproxEqRel(expected_sigma, sigma, 1.0e-9);
    }
}
