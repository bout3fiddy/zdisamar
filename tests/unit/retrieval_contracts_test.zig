const std = @import("std");
const zdisamar = @import("zdisamar");
const retrieval = @import("retrieval");

test "retrieval common contracts enforce derivative requirement by method" {
    const request = zdisamar.Request{
        .scene = .{
            .id = "scene-retrieval-unit",
            .atmosphere = .{ .layer_count = 10 },
            .spectral_grid = .{ .sample_count = 12 },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-unit",
            .state_vector = .{
                .parameter_names = &[_][]const u8{"x0"},
                .value_count = 1,
            },
            .measurements = .{
                .product = "radiance",
                .sample_count = 12,
            },
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };

    const base_problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(&request);
    try base_problem.validateForMethod(.oe);

    const layout = base_problem.layoutRequirements();
    try std.testing.expectEqual(@as(u32, 10), layout.layer_count);
    try std.testing.expectEqual(@as(u32, 1), layout.state_parameter_count);
    try std.testing.expectEqual(@as(u32, 12), layout.measurement_count);

    var no_derivative = base_problem;
    no_derivative.derivative_mode = .none;
    no_derivative.jacobians_requested = true;
    try std.testing.expectError(
        retrieval.common.contracts.Error.DerivativeModeRequired,
        no_derivative.validateForMethod(.oe),
    );

    no_derivative.jacobians_requested = false;
    try no_derivative.validateForMethod(.doas);
}

test "retrieval contracts require explicit external-observation bindings" {
    var wavelengths = [_]f64{ 760.5, 760.6 };
    var radiance = [_]f64{ 1.2, 1.1 };
    var irradiance = [_]f64{ 2.0, 2.0 };
    var reflectance = [_]f64{ 0.6, 0.55 };
    var noise_sigma = [_]f64{ 0.01, 0.01 };
    var observed_product: zdisamar.transport.measurement_space.MeasurementSpaceProduct = .{
        .summary = .{
            .sample_count = 2,
            .wavelength_start_nm = 760.5,
            .wavelength_end_nm = 760.6,
            .mean_radiance = 1.15,
            .mean_irradiance = 2.0,
            .mean_reflectance = 0.575,
            .mean_noise_sigma = 0.01,
        },
        .wavelengths = wavelengths[0..],
        .radiance = radiance[0..],
        .irradiance = irradiance[0..],
        .reflectance = reflectance[0..],
        .noise_sigma = noise_sigma[0..],
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 0.0,
        .effective_temperature_k = 250.0,
        .effective_pressure_hpa = 900.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.0,
        .cloud_optical_depth = 0.0,
        .total_optical_depth = 0.0,
        .depolarization_factor = 0.0,
        .d_optical_depth_d_temperature = 0.0,
    };

    const request = zdisamar.Request{
        .scene = .{
            .id = "scene-external-binding",
            .atmosphere = .{ .layer_count = 10 },
            .spectral_grid = .{ .sample_count = 2 },
        },
        .inverse_problem = .{
            .id = "inverse-external-binding",
            .state_vector = .{
                .parameter_names = &[_][]const u8{"x0"},
                .value_count = 1,
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 2,
                .source = .{ .kind = .external_observation, .name = "observed_radiance" },
            },
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };

    try std.testing.expectError(
        retrieval.common.contracts.Error.MissingMeasurementProduct,
        retrieval.common.contracts.RetrievalProblem.fromRequest(&request),
    );

    var bound_request = request;
    bound_request.measurement_binding = .{
        .source_name = "observed_radiance",
        .observable = "radiance",
        .product = &observed_product,
    };
    const bound_problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(&bound_request);
    try std.testing.expect(bound_problem.observed_measurement != null);
    try std.testing.expectEqualStrings("observed_radiance", bound_problem.observed_measurement.?.source_name);

    var mismatched_observable_request = request;
    mismatched_observable_request.measurement_binding = .{
        .source_name = "observed_radiance",
        .observable = zdisamar.transport.measurement_space.reflectance_export_name,
        .product = &observed_product,
    };
    try std.testing.expectError(
        retrieval.common.contracts.Error.InvalidRequest,
        retrieval.common.contracts.RetrievalProblem.fromRequest(&mismatched_observable_request),
    );
}

test "retrieval covariance rejects singular variances" {
    const covariance: retrieval.common.covariance.DiagonalCovariance = .{
        .variances = &[_]f64{ 0.04, 0.0 },
    };
    const residual = [_]f64{ 0.2, 0.1 };
    var whitened: [2]f64 = undefined;

    try std.testing.expectError(error.SingularVariance, covariance.whiten(&residual, &whitened));
}
