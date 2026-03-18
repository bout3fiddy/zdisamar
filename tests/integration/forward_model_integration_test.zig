const std = @import("std");
const zdisamar = @import("zdisamar");

fn meanVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var sum: f64 = 0.0;
    var count: usize = 0;
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        sum += value;
        count += 1;
    }
    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

fn minVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) struct { wavelength_nm: f64, value: f64 } {
    var best = std.math.inf(f64);
    var best_wavelength = start_nm;
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value < best) {
            best = value;
            best_wavelength = wavelength_nm;
        }
    }
    return .{ .wavelength_nm = best_wavelength, .value = best };
}

fn maxVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var best = -std.math.inf(f64);
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value > best) best = value;
    }
    return best;
}

fn expectBoundedO2AMorphology(
    wavelengths_nm: []const f64,
    reflectance: []const f64,
) !void {
    const trough = minVectorInRange(wavelengths_nm, reflectance, 760.8, 761.2);
    const rebound_peak = maxVectorInRange(wavelengths_nm, reflectance, 761.8, 762.4);
    const mid_band_mean = meanVectorInRange(wavelengths_nm, reflectance, 763.8, 765.5);
    const red_wing_mean = meanVectorInRange(wavelengths_nm, reflectance, 769.8, 770.6);

    try std.testing.expect(trough.wavelength_nm >= 760.8 and trough.wavelength_nm < 761.2);
    try std.testing.expect(trough.value > 0.002 and trough.value < 0.12);
    try std.testing.expect(rebound_peak > trough.value * 4.0 and rebound_peak < 0.25);
    try std.testing.expect(mid_band_mean > trough.value * 4.0 and mid_band_mean < rebound_peak * 0.8);
    try std.testing.expect(red_wing_mean > trough.value * 8.0);
    try std.testing.expect(red_wing_mean > rebound_peak * 1.1);
    try std.testing.expect(red_wing_mean > mid_band_mean * 1.4);
}

test "engine execute materializes measurement-space summaries through the typed forward path" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
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
    defer plan.deinit();

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
            .instrument = .{ .custom = "integration-synthetic" },
            .regime = .limb,
            .sampling = .operational,
            .noise_model = .shot_noise,
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

    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);
    const measurement_space = result.measurement_space orelse return error.MissingMeasurementSummary;
    const measurement_product = result.measurement_space_product orelse return error.MissingMeasurementProduct;

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqual(@as(u32, 48), measurement_space.sample_count);
    try std.testing.expect(measurement_space.mean_radiance > 0.0);
    try std.testing.expect(measurement_space.mean_irradiance > 0.0);
    try std.testing.expect(measurement_space.mean_reflectance > 0.0);
    try std.testing.expect(measurement_space.mean_noise_sigma > 0.0);
    try std.testing.expect(measurement_space.mean_jacobian != null);
    try std.testing.expectEqual(measurement_space.sample_count, @as(u32, @intCast(measurement_product.wavelengths.len)));
    try std.testing.expectEqual(@as(usize, 48), measurement_product.radiance.len);
    try std.testing.expect(measurement_product.radiance[0] > 0.0);
    try std.testing.expect(measurement_product.radiance[0] != measurement_product.radiance[measurement_product.radiance.len - 1]);
    try std.testing.expect(measurement_product.reflectance[0] != measurement_product.reflectance[measurement_product.reflectance.len - 1]);
    try std.testing.expect(measurement_product.wavelengths[0] < measurement_product.wavelengths[measurement_product.wavelengths.len - 1]);
    for (measurement_product.wavelengths, measurement_product.radiance, measurement_product.irradiance, measurement_product.reflectance, 0..) |wavelength_nm, radiance, irradiance, reflectance, index| {
        if (index > 0) try std.testing.expect(wavelength_nm > measurement_product.wavelengths[index - 1]);
        try std.testing.expect(std.math.isFinite(radiance) and radiance > 0.0);
        try std.testing.expect(std.math.isFinite(irradiance) and irradiance > 0.0);
        try std.testing.expect(std.math.isFinite(reflectance) and reflectance > 0.0 and reflectance < 1.0);
    }
    try std.testing.expect(measurement_product.jacobian != null);
}

test "engine execute produces bounded O2A morphology through the typed forward path" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .semi_analytical,
            .spectral_grid = .{
                .start_nm = 760.8,
                .end_nm = 771.5,
                .sample_count = 121,
            },
            .layer_count_hint = 24,
            .measurement_count_hint = 121,
        },
    });
    defer plan.deinit();

    var workspace = engine.createWorkspace("forward-o2a-integration");
    var request = zdisamar.Request.init(.{
        .id = "scene-forward-o2a-integration",
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = 4,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.30,
            .single_scatter_albedo = 1.0,
            .asymmetry_factor = 0.70,
            .angstrom_exponent = 0.0,
            .reference_wavelength_nm = 760.0,
            .layer_center_km = 5.4,
            .layer_width_km = 0.4,
        },
        .surface = .{
            .albedo = 0.20,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .observation_model = .{
            .instrument = .{ .custom = "integration-o2a" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
        },
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 771.5,
            .sample_count = 121,
        },
    });
    request.expected_derivative_mode = .semi_analytical;
    request.diagnostics = .{
        .provenance = true,
        .jacobians = true,
    };

    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);
    const product = result.measurement_space_product orelse return error.MissingMeasurementProduct;

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("baseline_labos", result.provenance.transport_family);
    try std.testing.expect(product.jacobian != null);
    try expectBoundedO2AMorphology(product.wavelengths, product.reflectance);
}
