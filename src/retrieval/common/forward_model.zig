const std = @import("std");
const common = @import("contracts.zig");
const Measurement = @import("../../model/Measurement.zig").Measurement;
const Scene = @import("../../model/Scene.zig").Scene;
const MeasurementSpace = @import("../../kernels/transport/measurement_space.zig");
const MeasurementSpaceProduct = MeasurementSpace.MeasurementSpaceProduct;
const MeasurementSpaceSummary = MeasurementSpace.MeasurementSpaceSummary;
const Allocator = std.mem.Allocator;

pub const Evaluator = struct {
    context: *const anyopaque,
    evaluateSummary: *const fn (context: *const anyopaque, scene: Scene) anyerror!MeasurementSpaceSummary,
    evaluateProduct: *const fn (allocator: Allocator, context: *const anyopaque, scene: Scene) anyerror!MeasurementSpaceProduct,
};

pub const SpectralMeasurement = struct {
    wavelengths_nm: []f64 = &[_]f64{},
    values: []f64 = &[_]f64{},
    sigma: []f64 = &[_]f64{},
    jacobian: ?[]f64 = null,
    summary: MeasurementSpaceSummary,

    pub fn deinit(self: *SpectralMeasurement, allocator: Allocator) void {
        if (self.wavelengths_nm.len != 0) allocator.free(self.wavelengths_nm);
        if (self.values.len != 0) allocator.free(self.values);
        if (self.sigma.len != 0) allocator.free(self.sigma);
        if (self.jacobian) |values| allocator.free(values);
        self.* = .{
            .jacobian = null,
            .summary = .{
                .sample_count = 0,
                .wavelength_start_nm = 0.0,
                .wavelength_end_nm = 0.0,
                .mean_radiance = 0.0,
                .mean_irradiance = 0.0,
                .mean_reflectance = 0.0,
                .mean_noise_sigma = 0.0,
            },
        };
    }
};

pub fn observedMeasurement(
    allocator: Allocator,
    problem: common.RetrievalProblem,
) common.Error!SpectralMeasurement {
    const observed = problem.observed_measurement orelse return common.Error.MissingMeasurementProduct;
    return selectMeasurement(
        allocator,
        problem.inverse_problem.measurements,
        measurementObservable(problem),
        observed.product,
    );
}

pub fn evaluateMeasurement(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: Evaluator,
    scene: Scene,
) common.Error!SpectralMeasurement {
    var product = evaluator.evaluateProduct(allocator, evaluator.context, scene) catch |err| switch (err) {
        error.OutOfMemory => return common.Error.OutOfMemory,
        else => return common.Error.InvalidRequest,
    };
    defer product.deinit(allocator);

    return selectMeasurement(
        allocator,
        problem.inverse_problem.measurements,
        measurementObservable(problem),
        &product,
    );
}

pub fn measurementObservable(problem: common.RetrievalProblem) []const u8 {
    if (problem.inverse_problem.measurements.observable.len != 0) {
        return problem.inverse_problem.measurements.observable;
    }
    return problem.inverse_problem.measurements.product;
}

fn selectMeasurement(
    allocator: Allocator,
    measurement: Measurement,
    observable: []const u8,
    product: *const MeasurementSpaceProduct,
) common.Error!SpectralMeasurement {
    const selected_count = measurement.selectedSampleCount(product.wavelengths);
    if (selected_count != measurement.sample_count) return common.Error.ShapeMismatch;

    const wavelengths = try allocator.alloc(f64, selected_count);
    errdefer allocator.free(wavelengths);
    const values = try allocator.alloc(f64, selected_count);
    errdefer allocator.free(values);
    const sigma = try allocator.alloc(f64, selected_count);
    errdefer allocator.free(sigma);

    const source_values = measurementValues(product, observable) catch return common.Error.InvalidRequest;
    const source_jacobian = measurementJacobian(product, observable);
    const selected_jacobian = if (source_jacobian != null)
        try allocator.alloc(f64, selected_count)
    else
        null;
    errdefer if (selected_jacobian) |values_buffer| allocator.free(values_buffer);

    var output_index: usize = 0;
    for (product.wavelengths, 0..) |wavelength_nm, index| {
        if (!measurement.includesWavelength(wavelength_nm)) continue;

        wavelengths[output_index] = wavelength_nm;
        values[output_index] = source_values[index];
        sigma[output_index] = sampleSigma(measurement, product, index) catch return common.Error.InvalidRequest;
        if (selected_jacobian) |jacobian| {
            jacobian[output_index] = source_jacobian.?[index];
        }
        output_index += 1;
    }

    return .{
        .wavelengths_nm = wavelengths,
        .values = values,
        .sigma = sigma,
        .jacobian = selected_jacobian,
        .summary = product.summary,
    };
}

fn sampleSigma(
    measurement: Measurement,
    product: *const MeasurementSpaceProduct,
    index: usize,
) !f64 {
    var variance: f64 = 0.0;
    if (measurement.error_model.from_source_noise) {
        if (index >= product.noise_sigma.len or product.noise_sigma.len == 0) {
            return error.InvalidRequest;
        }
        const source_sigma = product.noise_sigma[index];
        if (!std.math.isFinite(source_sigma) or source_sigma < 0.0) return error.InvalidRequest;
        variance += source_sigma * source_sigma;
    }
    if (measurement.error_model.floor > 0.0) {
        variance += measurement.error_model.floor * measurement.error_model.floor;
    }
    if (variance <= 0.0) return error.InvalidRequest;
    return std.math.sqrt(variance);
}

fn measurementValues(product: *const MeasurementSpaceProduct, observable: []const u8) ![]const f64 {
    if (std.mem.eql(u8, observable, "radiance")) return product.radiance;
    if (std.mem.eql(u8, observable, "irradiance")) return product.irradiance;
    if (std.mem.eql(u8, observable, MeasurementSpace.reflectance_export_name)) return product.reflectance;
    return error.InvalidRequest;
}

fn measurementJacobian(product: *const MeasurementSpaceProduct, observable: []const u8) ?[]const f64 {
    if (!std.mem.eql(u8, observable, "radiance")) return null;
    return product.jacobian;
}

test "spectral evaluator selects masked observable vectors with sigma" {
    const product = MeasurementSpaceProduct{
        .summary = .{
            .sample_count = 4,
            .wavelength_start_nm = 759.5,
            .wavelength_end_nm = 762.0,
            .mean_radiance = 1.525,
            .mean_irradiance = 2.0,
            .mean_reflectance = 0.7625,
            .mean_noise_sigma = 0.0225,
        },
        .wavelengths = &[_]f64{ 759.5, 760.0, 761.0, 762.0 },
        .radiance = &[_]f64{ 1.6, 1.5, 1.4, 1.6 },
        .irradiance = &[_]f64{ 2.0, 2.0, 2.0, 2.0 },
        .reflectance = &[_]f64{ 0.8, 0.75, 0.70, 0.8 },
        .noise_sigma = &[_]f64{ 0.02, 0.02, 0.03, 0.02 },
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

    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-forward-model",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 762.0, .sample_count = 4 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-forward-model",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{
                        .name = "surface_albedo",
                        .target = .surface_albedo,
                        .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.02 },
                    },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 3,
                .mask = .{
                    .exclude = &[_]@import("../../model/Scene.zig").SpectralWindow{
                        .{ .start_nm = 760.0, .end_nm = 761.0 },
                    },
                },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "synthetic-observed",
            .observable = "radiance",
            .product_name = "radiance",
            .sample_count = 3,
            .product = &product,
        },
    };

    const selected = try observedMeasurement(std.testing.allocator, problem);
    defer {
        var owned = selected;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), selected.values.len);
    try std.testing.expect(selected.sigma[0] > 0.0);
    try std.testing.expect(selected.jacobian == null);
}

test "spectral evaluator carries routed radiance jacobian when available" {
    const jacobian = [_]f64{ -0.3, -0.2, -0.1, -0.05 };
    const product = MeasurementSpaceProduct{
        .summary = .{
            .sample_count = 4,
            .wavelength_start_nm = 759.5,
            .wavelength_end_nm = 762.0,
            .mean_radiance = 1.525,
            .mean_irradiance = 2.0,
            .mean_reflectance = 0.7625,
            .mean_noise_sigma = 0.0225,
            .mean_jacobian = -0.1625,
        },
        .wavelengths = &[_]f64{ 759.5, 760.0, 761.0, 762.0 },
        .radiance = &[_]f64{ 1.6, 1.5, 1.4, 1.6 },
        .irradiance = &[_]f64{ 2.0, 2.0, 2.0, 2.0 },
        .reflectance = &[_]f64{ 0.8, 0.75, 0.70, 0.8 },
        .noise_sigma = &[_]f64{ 0.02, 0.02, 0.03, 0.02 },
        .jacobian = &jacobian,
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

    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-forward-model-jacobian",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 762.0, .sample_count = 4 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-forward-model-jacobian",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{
                        .name = "aerosol_tau",
                        .target = .aerosol_optical_depth_550_nm,
                        .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.02 },
                    },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 3,
                .mask = .{
                    .exclude = &[_]@import("../../model/Scene.zig").SpectralWindow{
                        .{ .start_nm = 760.0, .end_nm = 761.0 },
                    },
                },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "synthetic-observed",
            .observable = "radiance",
            .product_name = "radiance",
            .sample_count = 3,
            .product = &product,
        },
    };

    const selected = try observedMeasurement(std.testing.allocator, problem);
    defer {
        var owned = selected;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(selected.jacobian != null);
    try std.testing.expectApproxEqAbs(@as(f64, -0.3), selected.jacobian.?[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -0.1), selected.jacobian.?[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -0.05), selected.jacobian.?[2], 1.0e-12);
}
