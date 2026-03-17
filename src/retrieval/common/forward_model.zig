const std = @import("std");
const common = @import("contracts.zig");
const Request = @import("../../core/Request.zig").Request;
const Measurement = @import("../../model/Measurement.zig").Measurement;
const MeasurementQuantity = @import("../../model/Measurement.zig").Quantity;
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

pub const MeasurementMetadata = struct {
    effective_air_mass_factor: f64 = 0.0,
    effective_single_scatter_albedo: f64 = 0.0,
    effective_temperature_k: f64 = 0.0,
    effective_pressure_hpa: f64 = 0.0,
    gas_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    depolarization_factor: f64 = 0.0,
    d_optical_depth_d_temperature: f64 = 0.0,
};

pub const SpectralMeasurement = struct {
    wavelengths_nm: []f64 = &[_]f64{},
    values: []f64 = &[_]f64{},
    sigma: []f64 = &[_]f64{},
    radiance: []f64 = &[_]f64{},
    irradiance: []f64 = &[_]f64{},
    reflectance: []f64 = &[_]f64{},
    jacobian: ?[]f64 = null,
    summary: MeasurementSpaceSummary,
    metadata: MeasurementMetadata = .{},

    pub fn deinit(self: *SpectralMeasurement, allocator: Allocator) void {
        if (self.wavelengths_nm.len != 0) allocator.free(self.wavelengths_nm);
        if (self.values.len != 0) allocator.free(self.values);
        if (self.sigma.len != 0) allocator.free(self.sigma);
        if (self.radiance.len != 0) allocator.free(self.radiance);
        if (self.irradiance.len != 0) allocator.free(self.irradiance);
        if (self.reflectance.len != 0) allocator.free(self.reflectance);
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

pub fn measurementFromProduct(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    product: *const MeasurementSpaceProduct,
) common.Error!SpectralMeasurement {
    return selectMeasurement(
        allocator,
        problem.inverse_problem.measurements,
        measurementObservable(problem),
        .init(product),
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
        .init(&product),
    );
}

pub fn measurementObservable(problem: common.RetrievalProblem) MeasurementQuantity {
    return problem.inverse_problem.measurements.observable;
}

fn selectMeasurement(
    allocator: Allocator,
    measurement: Measurement,
    observable: MeasurementQuantity,
    product: Request.BorrowedMeasurementProduct,
) common.Error!SpectralMeasurement {
    const raw_product = product.product;
    const selected_count = measurement.selectedSampleCount(product.wavelengths());
    if (selected_count != measurement.sample_count) return common.Error.ShapeMismatch;

    const wavelengths = try allocator.alloc(f64, selected_count);
    errdefer allocator.free(wavelengths);
    const values = try allocator.alloc(f64, selected_count);
    errdefer allocator.free(values);
    const sigma = try allocator.alloc(f64, selected_count);
    errdefer allocator.free(sigma);
    const radiance = try allocator.alloc(f64, selected_count);
    errdefer allocator.free(radiance);
    const irradiance = try allocator.alloc(f64, selected_count);
    errdefer allocator.free(irradiance);
    const reflectance = try allocator.alloc(f64, selected_count);
    errdefer allocator.free(reflectance);

    const source_values = measurementValues(raw_product, observable) catch return common.Error.InvalidRequest;
    const source_jacobian = measurementJacobian(raw_product, observable);
    const selected_jacobian = if (source_jacobian != null)
        try allocator.alloc(f64, selected_count)
    else
        null;
    errdefer if (selected_jacobian) |values_buffer| allocator.free(values_buffer);

    var output_index: usize = 0;
    for (raw_product.wavelengths, 0..) |wavelength_nm, index| {
        if (!measurement.includesWavelength(wavelength_nm)) continue;

        wavelengths[output_index] = wavelength_nm;
        values[output_index] = source_values[index];
        sigma[output_index] = sampleSigma(measurement, raw_product, index) catch return common.Error.InvalidRequest;
        radiance[output_index] = raw_product.radiance[index];
        irradiance[output_index] = raw_product.irradiance[index];
        reflectance[output_index] = raw_product.reflectance[index];
        if (selected_jacobian) |jacobian| {
            jacobian[output_index] = source_jacobian.?[index];
        }
        output_index += 1;
    }

    return .{
        .wavelengths_nm = wavelengths,
        .values = values,
        .sigma = sigma,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .jacobian = selected_jacobian,
        .summary = raw_product.summary,
        .metadata = metadataForProduct(raw_product),
    };
}

fn metadataForProduct(product: *const MeasurementSpaceProduct) MeasurementMetadata {
    return .{
        .effective_air_mass_factor = product.effective_air_mass_factor,
        .effective_single_scatter_albedo = product.effective_single_scatter_albedo,
        .effective_temperature_k = product.effective_temperature_k,
        .effective_pressure_hpa = product.effective_pressure_hpa,
        .gas_optical_depth = product.gas_optical_depth,
        .cia_optical_depth = product.cia_optical_depth,
        .aerosol_optical_depth = product.aerosol_optical_depth,
        .cloud_optical_depth = product.cloud_optical_depth,
        .total_optical_depth = product.total_optical_depth,
        .depolarization_factor = product.depolarization_factor,
        .d_optical_depth_d_temperature = product.d_optical_depth_d_temperature,
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

fn measurementValues(product: *const MeasurementSpaceProduct, observable: MeasurementQuantity) ![]const f64 {
    return switch (observable) {
        .radiance => product.radiance,
        .irradiance => product.irradiance,
        .reflectance => product.reflectance,
        .slant_column => error.InvalidRequest,
    };
}

fn measurementJacobian(product: *const MeasurementSpaceProduct, observable: MeasurementQuantity) ?[]const f64 {
    return if (observable == .radiance) product.jacobian else null;
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
            .observation_model = .{ .instrument = .synthetic },
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
                .product_name = "radiance",
                .observable = .radiance,
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
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = 3,
            .product = .init(&product),
        },
    };

    const selected = try observedMeasurement(std.testing.allocator, problem);
    defer {
        var owned = selected;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), selected.values.len);
    try std.testing.expect(selected.sigma[0] > 0.0);
    try std.testing.expectEqual(@as(usize, 3), selected.radiance.len);
    try std.testing.expectEqual(@as(f64, 1.0), selected.metadata.effective_air_mass_factor);
    try std.testing.expectEqual(@as(f64, 0.1), selected.metadata.total_optical_depth);
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
            .observation_model = .{ .instrument = .synthetic },
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
                .product_name = "radiance",
                .observable = .radiance,
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
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = 3,
            .product = .init(&product),
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
