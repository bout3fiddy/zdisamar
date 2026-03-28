const std = @import("std");
const zdisamar = @import("zdisamar");

const o2a_lut_absorbers = [_]zdisamar.Absorber{
    .{
        .id = "o2",
        .species = "o2",
        .profile_source = .atmosphere,
        .spectroscopy = .{ .mode = .line_by_line },
    },
    .{
        .id = "o2o2",
        .species = "o2_o2",
        .profile_source = .atmosphere,
        .spectroscopy = .{ .mode = .cia },
    },
};

const consumed_o2_lut: zdisamar.OperationalCrossSectionLut = .{
    .wavelengths_nm = &[_]f64{ 760.8, 761.0, 761.2 },
    .coefficients = &[_]f64{
        2.0e-24, 0.30e-24, 0.20e-24, 0.05e-24,
        2.6e-24, 0.35e-24, 0.25e-24, 0.06e-24,
        2.2e-24, 0.32e-24, 0.22e-24, 0.05e-24,
    },
    .temperature_coefficient_count = 2,
    .pressure_coefficient_count = 2,
    .min_temperature_k = 220.0,
    .max_temperature_k = 320.0,
    .min_pressure_hpa = 150.0,
    .max_pressure_hpa = 1000.0,
};

const consumed_o2o2_lut: zdisamar.OperationalCrossSectionLut = .{
    .wavelengths_nm = &[_]f64{ 760.8, 761.0, 761.2 },
    .coefficients = &[_]f64{
        1.2e-46, 0.20e-46, 0.10e-46, 0.03e-46,
        1.5e-46, 0.20e-46, 0.10e-46, 0.03e-46,
        1.1e-46, 0.18e-46, 0.08e-46, 0.02e-46,
    },
    .temperature_coefficient_count = 2,
    .pressure_coefficient_count = 2,
    .min_temperature_k = 220.0,
    .max_temperature_k = 320.0,
    .min_pressure_hpa = 150.0,
    .max_pressure_hpa = 1000.0,
};

fn generatedXsecControls() zdisamar.LutControls {
    return .{
        .xsec = .{
            .mode = .generate,
            .min_temperature_k = 180.0,
            .max_temperature_k = 325.0,
            .min_pressure_hpa = 0.03,
            .max_pressure_hpa = 1050.0,
            .temperature_grid_count = 6,
            .pressure_grid_count = 8,
            .temperature_coefficient_count = 3,
            .pressure_coefficient_count = 4,
        },
    };
}

fn expectedGeneratedXsecSpectralBins(scene: zdisamar.Scene) !u32 {
    const support = scene.observation_model.primaryOperationalBandSupport();
    const lut_sampling_half_span_nm = scene.observation_model.lutSamplingHalfSpanNm();
    if (support.high_resolution_step_nm <= 0.0 or lut_sampling_half_span_nm <= 0.0) {
        return scene.spectral_grid.sample_count;
    }

    const nominal_bounds = scene.lutNominalWavelengthBounds();
    const start_nm = nominal_bounds.start_nm - lut_sampling_half_span_nm;
    const end_nm = nominal_bounds.end_nm + lut_sampling_half_span_nm;
    const span_nm = end_nm - start_nm;
    return @as(u32, @intFromFloat(@floor((span_nm / support.high_resolution_step_nm) + 0.5))) + 1;
}

fn makeO2ALutScene(id: []const u8) zdisamar.Scene {
    return .{
        .id = id,
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .surface = .{
            .kind = .lambertian,
            .albedo = 0.20,
        },
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 9,
        },
        .absorbers = .{
            .items = o2a_lut_absorbers[0..],
        },
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = 3,
        },
        .observation_model = .{
            .regime = .nadir,
            .instrument = .synthetic,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
        },
    };
}

fn executeMeasurementScene(
    engine: *zdisamar.Engine,
    scene: zdisamar.Scene,
    workspace_label: []const u8,
) !zdisamar.Result {
    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .id = scene.id,
            .observation_regime = scene.observation_model.regime,
            .spectral_grid = scene.spectral_grid,
            .layer_count_hint = scene.atmosphere.layer_count,
            .measurement_count_hint = scene.spectral_grid.sample_count,
            .lut_compatibility = scene.lutCompatibilityKey(),
        },
    });
    defer plan.deinit();

    var workspace = engine.createWorkspace(workspace_label);
    var request = zdisamar.Request.init(scene);
    return try engine.execute(&plan, &workspace, &request);
}

fn hasLabel(entries: []const []const u8, expected: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry, expected)) return true;
    }
    return false;
}

test "generated LUT assets register typed cache entries and provenance labels" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var scene = makeO2ALutScene("validation-o2a-generated");
    scene.lut_controls = generatedXsecControls();
    scene.lut_controls.reflectance = .{
        .reflectance_mode = .generate,
        .correction_mode = .generate,
        .use_chandra_formula = true,
        .surface_albedo = scene.surface.albedo,
    };

    var result = try executeMeasurementScene(&engine, scene, "parity-assets-generate");
    defer result.deinit(std.testing.allocator);

    _ = result.measurement_space_product orelse return error.MissingMeasurementProduct;

    const compatibility = scene.lutCompatibilityKey();
    try std.testing.expectEqual(@as(usize, 4), result.provenance.lut_execution_entries.len);
    try std.testing.expect(hasLabel(result.provenance.lut_execution_entries, "reflectance_lut:generate"));
    try std.testing.expect(hasLabel(result.provenance.lut_execution_entries, "correction_lut:generate"));
    try std.testing.expect(hasLabel(result.provenance.lut_execution_entries, "o2:xsec_lut:generated"));
    try std.testing.expect(hasLabel(result.provenance.lut_execution_entries, "o2o2:xsec_lut:generated"));
    try std.testing.expectEqual(@as(usize, 4), engine.lut_cache.count());

    const reflectance_entry = engine.lut_cache.getCompatible(
        "generated.reflectance.reflectance",
        scene.id,
        compatibility,
    ).?;
    try std.testing.expectEqual(@as(u32, scene.spectral_grid.sample_count), reflectance_entry.shape.spectral_bins);
    try std.testing.expectEqual(@as(u32, scene.atmosphere.layer_count), reflectance_entry.shape.layer_count);
    try std.testing.expectEqual(@as(u32, 0), reflectance_entry.shape.coefficient_count);

    const correction_entry = engine.lut_cache.getCompatible(
        "generated.correction.correction",
        scene.id,
        compatibility,
    ).?;
    try std.testing.expectEqual(@as(u32, scene.spectral_grid.sample_count), correction_entry.shape.spectral_bins);
    try std.testing.expectEqual(@as(u32, scene.atmosphere.layer_count), correction_entry.shape.layer_count);
    try std.testing.expectEqual(@as(u32, 0), correction_entry.shape.coefficient_count);

    const expected_xsec_bins = try expectedGeneratedXsecSpectralBins(scene);
    const o2_entry = engine.lut_cache.getCompatible(
        "generated.xsec.o2",
        scene.id,
        compatibility,
    ).?;
    try std.testing.expectEqual(expected_xsec_bins, o2_entry.shape.spectral_bins);
    try std.testing.expectEqual(@as(u32, scene.atmosphere.layer_count), o2_entry.shape.layer_count);
    try std.testing.expectEqual(scene.lut_controls.xsec.coefficientCount(), o2_entry.shape.coefficient_count);

    const o2o2_entry = engine.lut_cache.getCompatible(
        "generated.xsec.o2o2",
        scene.id,
        compatibility,
    ).?;
    try std.testing.expectEqual(expected_xsec_bins, o2o2_entry.shape.spectral_bins);
    try std.testing.expectEqual(@as(u32, scene.atmosphere.layer_count), o2o2_entry.shape.layer_count);
    try std.testing.expectEqual(scene.lut_controls.xsec.coefficientCount(), o2o2_entry.shape.coefficient_count);
}

test "consume-mode LUT execution records provenance without creating cache entries" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var scene = makeO2ALutScene("validation-o2a-consume");
    scene.lut_controls = .{
        .xsec = .{
            .mode = .consume,
            .min_temperature_k = 220.0,
            .max_temperature_k = 320.0,
            .min_pressure_hpa = 150.0,
            .max_pressure_hpa = 1000.0,
            .temperature_grid_count = 2,
            .pressure_grid_count = 2,
            .temperature_coefficient_count = 2,
            .pressure_coefficient_count = 2,
        },
    };
    scene.observation_model.o2_operational_lut = consumed_o2_lut;
    scene.observation_model.o2o2_operational_lut = consumed_o2o2_lut;

    var result = try executeMeasurementScene(&engine, scene, "parity-assets-consume");
    defer result.deinit(std.testing.allocator);

    _ = result.measurement_space_product orelse return error.MissingMeasurementProduct;

    try std.testing.expectEqual(@as(usize, 2), result.provenance.lut_execution_entries.len);
    try std.testing.expect(hasLabel(result.provenance.lut_execution_entries, "o2:xsec_lut:consume"));
    try std.testing.expect(hasLabel(result.provenance.lut_execution_entries, "o2o2:xsec_lut:consume"));
    try std.testing.expectEqual(@as(usize, 0), engine.lut_cache.count());
}
