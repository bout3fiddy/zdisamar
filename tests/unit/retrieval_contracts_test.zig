const std = @import("std");
const zdisamar = @import("zdisamar");
const retrieval = @import("retrieval");

const StateParameter = zdisamar.StateParameter;

fn testObservedProduct() zdisamar.transport.measurement_space.MeasurementSpaceProduct {
    return .{
        .summary = .{
            .sample_count = 4,
            .wavelength_start_nm = 759.5,
            .wavelength_end_nm = 762.0,
            .mean_radiance = 1.0,
            .mean_irradiance = 2.0,
            .mean_reflectance = 0.5,
            .mean_noise_sigma = 0.02,
        },
        .wavelengths = @constCast(&[_]f64{ 759.5, 760.5, 761.5, 762.0 }),
        .radiance = @constCast(&[_]f64{ 1.0, 0.8, 0.9, 0.95 }),
        .irradiance = @constCast(&[_]f64{ 2.0, 2.0, 2.0, 2.0 }),
        .reflectance = @constCast(&[_]f64{ 0.5, 0.4, 0.45, 0.475 }),
        .noise_sigma = @constCast(&[_]f64{ 0.02, 0.02, 0.02, 0.02 }),
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 1.0,
        .effective_temperature_k = 270.0,
        .effective_pressure_hpa = 700.0,
        .gas_optical_depth = 0.1,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.0,
        .cloud_optical_depth = 0.0,
        .total_optical_depth = 0.1,
        .depolarization_factor = 0.0,
        .d_optical_depth_d_temperature = 0.0,
    };
}

test "oe contracts require typed state priors and bound spectral measurements" {
    const request = zdisamar.Request{
        .scene = .{
            .id = "scene-retrieval-unit",
            .atmosphere = .{ .layer_count = 10 },
            .spectral_grid = .{
                .start_nm = 759.5,
                .end_nm = 762.0,
                .sample_count = 4,
            },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-unit",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{
                        .name = "surface_albedo",
                        .target = .surface_albedo,
                        .transform = .logit,
                        .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.03 },
                        .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 },
                    },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 4,
                .source = .{ .kind = .external_observation, .name = "truth_radiance" },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
            },
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };

    try std.testing.expectError(
        retrieval.common.contracts.Error.MissingMeasurementProduct,
        retrieval.common.contracts.RetrievalProblem.fromRequest(&request),
    );

    var observed_product = testObservedProduct();
    var bound_request = request;
    bound_request.measurement_binding = .{
        .source_name = "truth_radiance",
        .observable = "radiance",
        .product = &observed_product,
    };

    const bound_problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(&bound_request);
    try bound_problem.validateForMethod(.oe);
    try std.testing.expectEqual(retrieval.common.contracts.ImplementationClass.real, retrieval.common.contracts.Method.oe.classification());
    try std.testing.expectEqual(@as(u32, 4), bound_problem.observed_measurement.?.sample_count);
}

test "retrieval contracts validate masked measurement selection against bound products" {
    var observed_product = testObservedProduct();
    var request = zdisamar.Request{
        .scene = .{
            .id = "scene-external-binding",
            .atmosphere = .{ .layer_count = 10 },
            .spectral_grid = .{
                .start_nm = 759.5,
                .end_nm = 762.0,
                .sample_count = 4,
            },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-external-binding",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{
                        .name = "surface_albedo",
                        .target = .surface_albedo,
                        .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.02 },
                    },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 3,
                .source = .{ .kind = .external_observation, .name = "observed_radiance" },
                .mask = .{
                    .exclude = &[_]zdisamar.SpectralWindow{
                        .{ .start_nm = 760.0, .end_nm = 761.0 },
                    },
                },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
            },
        },
        .measurement_binding = .{
            .source_name = "observed_radiance",
            .observable = "radiance",
            .product = &observed_product,
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };

    try request.validate();
    const problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(&request);
    try problem.validateForMethod(.oe);
    try std.testing.expectEqual(@as(u32, 3), problem.observed_measurement.?.sample_count);
}

test "solver outcomes own oe matrix products independently of caller buffers" {
    var observed_product = testObservedProduct();
    const state_values = try std.testing.allocator.dupe(f64, &.{ 0.12, 0.08 });
    const jacobian_values = try std.testing.allocator.dupe(f64, &.{ 0.1, 0.2, 0.3, 0.4 });
    const ak_values = try std.testing.allocator.dupe(f64, &.{ 0.8, 0.1, 0.05, 0.6 });
    const posterior_values = try std.testing.allocator.dupe(f64, &.{ 0.01, 0.002, 0.002, 0.02 });

    const problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = .{
            .id = "scene-owned-outcome",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 762.0, .sample_count = 4 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-owned-outcome",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.02 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.03 } },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 4,
                .source = .{ .kind = .external_observation, .name = "truth_radiance" },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = "radiance",
            .product_name = "radiance",
            .sample_count = 4,
            .product = &observed_product,
        },
    };

    const outcome = try retrieval.common.contracts.outcome(
        std.testing.allocator,
        problem,
        .oe,
        3,
        1.25,
        true,
        true,
        1.4,
        0.2,
        0.01,
        .{
            .parameter_names = &[_][]const u8{ "surface_albedo", "aerosol_tau" },
            .values = state_values,
        },
        problem.scene,
        observed_product.summary,
        .{ .row_count = 2, .column_count = 2, .values = jacobian_values },
        .{ .row_count = 2, .column_count = 2, .values = ak_values },
        .{ .row_count = 2, .column_count = 2, .values = posterior_values },
    );
    defer {
        var owned = outcome;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(outcome.jacobian != null);
    try std.testing.expect(outcome.averaging_kernel != null);
    try std.testing.expect(outcome.posterior_covariance != null);
    try std.testing.expectEqual(@as(u32, 2), outcome.posterior_covariance.?.row_count);
    try std.testing.expectEqualStrings("truth_radiance", outcome.observed_measurement.?.source_name);
}
