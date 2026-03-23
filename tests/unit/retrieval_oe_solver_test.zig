const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const common = internal.retrieval.common.contracts;
const forward_model = internal.retrieval.common.forward_model;
const MeasurementSpace = internal.kernels.transport.measurement;
const solver = internal.retrieval.oe.solver;
const StateParameter = zdisamar.StateParameter;

test "oe retrieval converges on a real spectral residual with posterior products" {
    const evaluator = testSpectralEvaluator();
    var observed_product = try evaluator.evaluateProduct(std.testing.allocator, evaluator.context, .{
        .id = "truth-scene",
        .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 48 },
        .surface = .{ .albedo = 0.18 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.12, .layer_center_km = 3.0, .layer_width_km = 1.0 },
        .observation_model = .{
            .instrument = .synthetic,
            .wavelength_shift_nm = 0.015,
        },
    });
    defer observed_product.deinit(std.testing.allocator);

    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-oe",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 48 },
            .surface = .{ .albedo = 0.08 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.05, .layer_center_km = 3.0, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = .synthetic },
        },
        .inverse_problem = .{
            .id = "inverse-oe",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 3.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = -0.2, .max = 0.2 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 48,
                .source = .{ .external_observation = .{ .name = "truth_radiance" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = 48,
            .product = .init(&observed_product),
        },
    };

    const result = try solver.solveWithEvaluator(std.testing.allocator, problem, evaluator);
    defer {
        var owned = result;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(common.Method.oe, result.method);
    try std.testing.expect(result.jacobians_used);
    try std.testing.expect(result.fitted_scene != null);
    try std.testing.expect(result.fitted_measurement != null);
    try std.testing.expect(result.jacobian != null);
    try std.testing.expect(result.averaging_kernel != null);
    try std.testing.expect(result.posterior_covariance != null);
    try std.testing.expect(result.dfs > 0.0);
    try std.testing.expect(result.state_estimate.values.len == 3);
}

test "oe retrieval reports non-convergence when iteration budget is exhausted" {
    const evaluator = testSpectralEvaluator();
    var observed_product = try evaluator.evaluateProduct(std.testing.allocator, evaluator.context, .{
        .id = "truth-scene-limited",
        .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 40 },
        .surface = .{ .albedo = 0.25 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.20, .layer_center_km = 3.0, .layer_width_km = 1.0 },
        .observation_model = .{ .instrument = .synthetic, .wavelength_shift_nm = 0.02 },
    });
    defer observed_product.deinit(std.testing.allocator);

    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-oe-limited",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 40 },
            .surface = .{ .albedo = 0.02 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.02, .layer_center_km = 3.0, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = .synthetic },
        },
        .inverse_problem = .{
            .id = "inverse-oe-limited",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.02, .sigma = 0.01 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 40,
                .source = .{ .external_observation = .{ .name = "truth_radiance" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
            },
            .fit_controls = .{
                .max_iterations = 1,
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = 40,
            .product = .init(&observed_product),
        },
    };

    const result = try solver.solveWithEvaluator(std.testing.allocator, problem, evaluator);
    defer {
        var owned = result;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(!result.converged);
    try std.testing.expectEqual(@as(u32, 1), result.iterations);
}

const TestEvaluatorContext = struct {};

var test_evaluator_context: TestEvaluatorContext = .{};

fn testSpectralEvaluator() forward_model.Evaluator {
    return .{
        .context = &test_evaluator_context,
        .evaluateSummary = testEvaluateSummary,
        .evaluateProduct = testEvaluateProduct,
    };
}

fn testEvaluateSummary(_: *const anyopaque, scene: zdisamar.Scene) anyerror!MeasurementSpace.MeasurementSpaceSummary {
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    if (sample_count == 0) return error.InvalidRequest;

    const irradiance = testIrradiance();
    var radiance_sum: f64 = 0.0;
    var reflectance_sum: f64 = 0.0;
    for (0..sample_count) |index| {
        const wavelength_nm = testWavelength(scene, index);
        const radiance = testRadiance(scene, wavelength_nm);
        radiance_sum += radiance;
        reflectance_sum += radiance / irradiance;
    }

    return .{
        .sample_count = @intCast(sample_count),
        .wavelength_start_nm = testWavelength(scene, 0),
        .wavelength_end_nm = testWavelength(scene, sample_count - 1),
        .mean_radiance = radiance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_irradiance = irradiance,
        .mean_reflectance = reflectance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_noise_sigma = 0.02,
    };
}

fn testEvaluateProduct(
    allocator: std.mem.Allocator,
    _: *const anyopaque,
    scene: zdisamar.Scene,
) anyerror!MeasurementSpace.MeasurementSpaceProduct {
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    if (sample_count == 0) return error.InvalidRequest;

    const wavelengths = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(wavelengths);
    const radiance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(radiance);
    const irradiance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(irradiance);
    const reflectance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(reflectance);
    const noise_sigma = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(noise_sigma);
    const jacobian = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(jacobian);

    const irradiance_level = testIrradiance();
    var radiance_sum: f64 = 0.0;
    var reflectance_sum: f64 = 0.0;
    var jacobian_sum: f64 = 0.0;
    for (0..sample_count) |index| {
        const wavelength_nm = testWavelength(scene, index);
        const radiance_value = testRadiance(scene, wavelength_nm);
        const jacobian_value = testAerosolJacobian(scene, wavelength_nm);

        wavelengths[index] = wavelength_nm;
        radiance[index] = radiance_value;
        irradiance[index] = irradiance_level;
        reflectance[index] = radiance_value / irradiance_level;
        noise_sigma[index] = 0.02;
        jacobian[index] = jacobian_value;

        radiance_sum += radiance_value;
        reflectance_sum += reflectance[index];
        jacobian_sum += jacobian_value;
    }

    return .{
        .summary = .{
            .sample_count = @intCast(sample_count),
            .wavelength_start_nm = wavelengths[0],
            .wavelength_end_nm = wavelengths[sample_count - 1],
            .mean_radiance = radiance_sum / @as(f64, @floatFromInt(sample_count)),
            .mean_irradiance = irradiance_level,
            .mean_reflectance = reflectance_sum / @as(f64, @floatFromInt(sample_count)),
            .mean_noise_sigma = 0.02,
            .mean_jacobian = jacobian_sum / @as(f64, @floatFromInt(sample_count)),
        },
        .wavelengths = wavelengths,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .noise_sigma = noise_sigma,
        .jacobian = jacobian,
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 0.93,
        .effective_temperature_k = 270.0,
        .effective_pressure_hpa = 800.0,
        .gas_optical_depth = 0.1,
        .cia_optical_depth = 0.02,
        .aerosol_optical_depth = scene.aerosol.optical_depth,
        .cloud_optical_depth = 0.0,
        .total_optical_depth = 0.12 + scene.aerosol.optical_depth,
        .depolarization_factor = 0.0,
        .d_optical_depth_d_temperature = 0.0,
    };
}

fn testWavelength(scene: zdisamar.Scene, index: usize) f64 {
    if (scene.spectral_grid.sample_count <= 1) return scene.spectral_grid.start_nm;
    const step = (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) /
        @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    return scene.spectral_grid.start_nm + step * @as(f64, @floatFromInt(index));
}

fn testIrradiance() f64 {
    return 2.0;
}

fn testRadiance(scene: zdisamar.Scene, wavelength_nm: f64) f64 {
    const shifted_wavelength = wavelength_nm - scene.observation_model.wavelength_shift_nm;
    const profile = testAbsorptionProfile(scene, shifted_wavelength);
    const continuum = 0.55 + 2.6 * scene.surface.albedo + 0.008 * (shifted_wavelength - scene.spectral_grid.start_nm);
    const radiance = continuum - scene.aerosol.optical_depth * profile;
    return @max(radiance, 1.0e-3);
}

fn testAerosolJacobian(scene: zdisamar.Scene, wavelength_nm: f64) f64 {
    const shifted_wavelength = wavelength_nm - scene.observation_model.wavelength_shift_nm;
    return -testAbsorptionProfile(scene, shifted_wavelength);
}

fn testAbsorptionProfile(scene: zdisamar.Scene, wavelength_nm: f64) f64 {
    const height_shift = 0.03 * (scene.aerosol.layer_center_km - 3.0);
    const broad = 0.42 * testGaussian(wavelength_nm, 762.7 + height_shift, 1.35);
    const narrow =
        0.18 * testGaussian(wavelength_nm, 760.55 + height_shift, 0.12) +
        0.24 * testGaussian(wavelength_nm, 761.15 + height_shift, 0.10) +
        0.33 * testGaussian(wavelength_nm, 761.95 + height_shift, 0.11) +
        0.41 * testGaussian(wavelength_nm, 762.95 + height_shift, 0.10) +
        0.47 * testGaussian(wavelength_nm, 763.75 + height_shift, 0.09) +
        0.52 * testGaussian(wavelength_nm, 764.55 + height_shift, 0.08);
    return broad + narrow;
}

fn testGaussian(x: f64, center: f64, sigma: f64) f64 {
    const normalized = (x - center) / sigma;
    return std.math.exp(-0.5 * normalized * normalized);
}
