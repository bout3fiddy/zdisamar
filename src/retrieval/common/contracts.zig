const std = @import("std");
const Request = @import("../../core/Request.zig").Request;
const DerivativeMode = @import("../../model/Scene.zig").DerivativeMode;
const InverseProblem = @import("../../model/Scene.zig").InverseProblem;
const LayoutRequirements = @import("../../model/Scene.zig").LayoutRequirements;
const Measurement = @import("../../model/Scene.zig").Measurement;
const MeasurementQuantity = @import("../../model/Measurement.zig").Quantity;
const Scene = @import("../../model/Scene.zig").Scene;
const MeasurementSpaceProduct = @import("../../kernels/transport/measurement_space.zig").MeasurementSpaceProduct;
const MeasurementSpaceSummary = @import("../../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;
const Allocator = std.mem.Allocator;

pub const Method = enum {
    oe,
    doas,
    dismas,

    pub fn classification(self: Method) ImplementationClass {
        return switch (self) {
            .oe, .doas, .dismas => .real,
        };
    }

    pub fn implementationLabel(self: Method) []const u8 {
        return switch (self) {
            .oe => "rodgers_oe",
            .doas => "classic_doas",
            .dismas => "direct_intensity_dismas",
        };
    }
};

pub const DerivativeRequirement = enum {
    optional,
    required,
};

pub const ImplementationClass = enum {
    surrogate,
    real,
};

pub const FitSpace = enum {
    radiance,
    differential_optical_depth,
};

pub const Error = error{
    MissingInverseProblem,
    MissingStateVector,
    MissingMeasurements,
    MissingMeasurementProduct,
    DerivativeModeRequired,
    ShapeMismatch,
    InvalidStateValue,
    SingularMatrix,
    OutOfMemory,
    InvalidRequest,
    MissingScene,
    MissingObservationInstrument,
};

pub const RetrievalProblem = struct {
    pub const ObservedMeasurement = struct {
        source_name: []const u8 = "",
        observable: MeasurementQuantity = .radiance,
        product_name: []const u8 = "",
        sample_count: u32 = 0,
        product: Request.BorrowedMeasurementProduct,

        pub fn summary(self: ObservedMeasurement) MeasurementSpaceSummary {
            return self.product.product.summary;
        }
    };

    scene: Scene,
    inverse_problem: InverseProblem,
    derivative_mode: DerivativeMode,
    jacobians_requested: bool = false,
    observed_measurement: ?ObservedMeasurement = null,

    pub fn fromRequest(request: *const Request) Error!RetrievalProblem {
        validateScene(request.scene) catch |err| return err;

        const inverse_problem = request.inverse_problem orelse return Error.MissingInverseProblem;
        inverse_problem.validate() catch {
            return Error.InvalidRequest;
        };

        var observed_measurement: ?ObservedMeasurement = null;
        if (request.measurement_binding) |binding| {
            if (binding.source.kind() != inverse_problem.measurements.source.kind())
                return Error.InvalidRequest;
            const expected_source_name = inverse_problem.measurements.source.name();
            if (expected_source_name.len != 0 and
                !std.mem.eql(u8, expected_source_name, binding.source.name()))
            {
                return Error.InvalidRequest;
            }

            const expected_observable = measurementObservable(inverse_problem.measurements);
            const selected_sample_count = inverse_problem.measurements.selectedSampleCount(binding.borrowed_product.wavelengths());
            if (selected_sample_count != inverse_problem.measurements.sample_count) {
                return Error.InvalidRequest;
            }

            observed_measurement = .{
                .source_name = binding.source.name(),
                .observable = expected_observable,
                .product_name = inverse_problem.measurements.resolvedProductName(),
                .sample_count = selected_sample_count,
                .product = binding.borrowed_product,
            };
        } else if (inverse_problem.measurements.source.kind() == .stage_product or
            inverse_problem.measurements.source.kind() == .external_observation or
            inverse_problem.measurements.source.kind() == .ingest)
        {
            return Error.MissingMeasurementProduct;
        }

        return .{
            .scene = request.scene,
            .inverse_problem = inverse_problem,
            .derivative_mode = request.expected_derivative_mode orelse .none,
            .jacobians_requested = request.diagnostics.jacobians,
            .observed_measurement = observed_measurement,
        };
    }

    pub fn validate(self: RetrievalProblem) Error!void {
        try validateScene(self.scene);

        if (self.inverse_problem.id.len == 0) return Error.MissingInverseProblem;
        if (self.inverse_problem.state_vector.count() == 0) return Error.MissingStateVector;
        if (self.inverse_problem.measurements.sample_count == 0) return Error.MissingMeasurements;
        if (self.jacobians_requested and self.derivative_mode == .none) return Error.DerivativeModeRequired;
    }

    pub fn layoutRequirements(self: RetrievalProblem) LayoutRequirements {
        var requirements = self.scene.layoutRequirements();
        requirements.state_parameter_count = self.inverse_problem.state_vector.count();
        requirements.measurement_count = self.inverse_problem.measurements.sample_count;
        return requirements;
    }

    pub fn validateForMethod(self: RetrievalProblem, method: Method) Error!void {
        try self.validate();
        if (derivativeRequirement(method) == .required and self.derivative_mode == .none) {
            return Error.DerivativeModeRequired;
        }
        switch (method) {
            .oe => self.inverse_problem.validateForOptimalEstimation() catch return Error.InvalidRequest,
            .doas => self.inverse_problem.validateForDoas() catch return Error.InvalidRequest,
            .dismas => self.inverse_problem.validateForDismas() catch return Error.InvalidRequest,
        }
        if (self.observed_measurement == null) {
            return Error.MissingMeasurementProduct;
        }
    }
};

pub const SolverOutcome = struct {
    pub const FitDiagnostics = struct {
        fit_space: FitSpace = .radiance,
        polynomial_order: u32 = 0,
        fit_sample_count: u32 = 0,
        selected_rtm_sample_count: u32 = 0,
        selection_zero_crossing_count: u32 = 0,
        window_start_nm: f64 = 0.0,
        window_end_nm: f64 = 0.0,
        effective_air_mass_factor: f64 = 0.0,
        weighted_residual_rms: f64 = 0.0,
        effective_cross_section_rms: ?f64 = null,
    };

    pub const StateEstimate = struct {
        parameter_names: []const []const u8 = &[_][]const u8{},
        values: []f64 = &[_]f64{},

        pub fn deinit(self: *StateEstimate, allocator: Allocator) void {
            if (self.parameter_names.len != 0) {
                for (self.parameter_names) |name| allocator.free(name);
                allocator.free(self.parameter_names);
            }
            if (self.values.len != 0) allocator.free(self.values);
            self.* = .{};
        }
    };

    pub const Matrix = struct {
        row_count: u32 = 0,
        column_count: u32 = 0,
        values: []f64 = &[_]f64{},

        pub fn deinit(self: *Matrix, allocator: Allocator) void {
            if (self.values.len != 0) allocator.free(self.values);
            self.* = .{};
        }
    };

    pub const ObservedMeasurementSummary = struct {
        source_name: []const u8 = "",
        observable: MeasurementQuantity = .radiance,
        product_name: []const u8 = "",
        sample_count: u32 = 0,
        summary: MeasurementSpaceSummary,

        pub fn deinitOwned(self: *ObservedMeasurementSummary, allocator: Allocator) void {
            if (self.source_name.len != 0) allocator.free(self.source_name);
            if (self.product_name.len != 0) allocator.free(self.product_name);
            self.* = undefined;
        }
    };

    method: Method,
    scene_id: []const u8,
    inverse_problem_id: []const u8,
    derivative_mode: DerivativeMode,
    iterations: u32,
    cost: f64,
    converged: bool,
    jacobians_used: bool,
    dfs: f64,
    residual_norm: f64,
    step_norm: f64,
    fit_diagnostics: ?FitDiagnostics = null,
    observed_measurement: ?ObservedMeasurementSummary = null,
    fitted_measurement: ?MeasurementSpaceSummary = null,
    state_estimate: StateEstimate = .{},
    fitted_scene: ?Scene = null,
    jacobian: ?Matrix = null,
    averaging_kernel: ?Matrix = null,
    posterior_covariance: ?Matrix = null,

    pub fn deinit(self: *SolverOutcome, allocator: Allocator) void {
        if (self.scene_id.len != 0) allocator.free(self.scene_id);
        if (self.inverse_problem_id.len != 0) allocator.free(self.inverse_problem_id);
        if (self.observed_measurement) |*measurement| {
            measurement.deinitOwned(allocator);
            self.observed_measurement = null;
        }
        self.state_estimate.deinit(allocator);
        if (self.jacobian) |*matrix| {
            matrix.deinit(allocator);
            self.jacobian = null;
        }
        if (self.averaging_kernel) |*matrix| {
            matrix.deinit(allocator);
            self.averaging_kernel = null;
        }
        if (self.posterior_covariance) |*matrix| {
            matrix.deinit(allocator);
            self.posterior_covariance = null;
        }
        self.* = undefined;
    }
};

pub fn derivativeRequirement(method: Method) DerivativeRequirement {
    return switch (method) {
        .oe => .required,
        .doas => .optional,
        .dismas => .required,
    };
}

pub fn outcome(
    allocator: Allocator,
    problem: RetrievalProblem,
    method: Method,
    iterations: u32,
    cost: f64,
    converged: bool,
    jacobians_used: bool,
    dfs: f64,
    residual_norm: f64,
    step_norm: f64,
    fit_diagnostics: ?SolverOutcome.FitDiagnostics,
    state_estimate: SolverOutcome.StateEstimate,
    fitted_scene: ?Scene,
    fitted_measurement: ?MeasurementSpaceSummary,
    jacobian: ?SolverOutcome.Matrix,
    averaging_kernel: ?SolverOutcome.Matrix,
    posterior_covariance: ?SolverOutcome.Matrix,
) !SolverOutcome {
    const scene_id = try allocator.dupe(u8, problem.scene.id);
    errdefer allocator.free(scene_id);
    const inverse_problem_id = try allocator.dupe(u8, problem.inverse_problem.id);
    errdefer allocator.free(inverse_problem_id);

    var owned_observed_measurement = try duplicateObservedMeasurement(allocator, problem.observed_measurement);
    errdefer if (owned_observed_measurement) |*measurement| measurement.deinitOwned(allocator);

    const owned_state_estimate = try duplicateStateEstimate(allocator, state_estimate);
    errdefer {
        var owned = owned_state_estimate;
        owned.deinit(allocator);
    }

    return .{
        .method = method,
        .scene_id = scene_id,
        .inverse_problem_id = inverse_problem_id,
        .derivative_mode = problem.derivative_mode,
        .iterations = iterations,
        .cost = cost,
        .converged = converged,
        .jacobians_used = jacobians_used,
        .dfs = dfs,
        .residual_norm = residual_norm,
        .step_norm = step_norm,
        .fit_diagnostics = fit_diagnostics,
        .observed_measurement = owned_observed_measurement,
        .fitted_measurement = fitted_measurement,
        .state_estimate = owned_state_estimate,
        .fitted_scene = fitted_scene,
        .jacobian = jacobian,
        .averaging_kernel = averaging_kernel,
        .posterior_covariance = posterior_covariance,
    };
}

fn duplicateObservedMeasurement(
    allocator: Allocator,
    measurement: ?RetrievalProblem.ObservedMeasurement,
) !?SolverOutcome.ObservedMeasurementSummary {
    if (measurement) |observed| {
        const source_name = try allocator.dupe(u8, observed.source_name);
        errdefer allocator.free(source_name);
        const product_name = try allocator.dupe(u8, observed.product_name);
        errdefer allocator.free(product_name);
        return .{
            .source_name = source_name,
            .observable = observed.observable,
            .product_name = product_name,
            .sample_count = observed.sample_count,
            .summary = observed.summary(),
        };
    }
    return null;
}

fn duplicateStateEstimate(
    allocator: Allocator,
    state_estimate: SolverOutcome.StateEstimate,
) !SolverOutcome.StateEstimate {
    const parameter_names = try allocator.alloc([]const u8, state_estimate.parameter_names.len);
    errdefer allocator.free(parameter_names);

    var copied_names: usize = 0;
    errdefer {
        for (parameter_names[0..copied_names]) |name| allocator.free(name);
    }
    for (state_estimate.parameter_names, 0..) |name, index| {
        parameter_names[index] = try allocator.dupe(u8, name);
        copied_names = index + 1;
    }

    return .{
        .parameter_names = parameter_names,
        .values = state_estimate.values,
    };
}

fn measurementObservable(measurement: Measurement) MeasurementQuantity {
    return measurement.observable;
}

fn validateScene(scene: Scene) Error!void {
    scene.validate() catch |err| switch (err) {
        error.MissingScene => return Error.MissingScene,
        error.MissingObservationInstrument => return Error.MissingObservationInstrument,
        else => return Error.InvalidRequest,
    };
}

test "retrieval contracts enforce canonical problem invariants" {
    const product = MeasurementSpaceProduct{
        .summary = .{
            .sample_count = 16,
            .wavelength_start_nm = 759.5,
            .wavelength_end_nm = 762.5,
            .mean_radiance = 1.0,
            .mean_irradiance = 2.0,
            .mean_reflectance = 0.5,
            .mean_noise_sigma = 0.02,
        },
        .wavelengths = &[_]f64{ 759.5, 759.7, 759.9, 760.1, 760.3, 760.5, 760.7, 760.9, 761.1, 761.3, 761.5, 761.7, 761.9, 762.1, 762.3, 762.5 },
        .radiance = &[_]f64{ 1.0, 0.99, 0.98, 0.97, 0.96, 0.95, 0.94, 0.93, 0.92, 0.91, 0.90, 0.89, 0.88, 0.87, 0.86, 0.85 },
        .irradiance = &[_]f64{ 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0 },
        .reflectance = &[_]f64{ 0.5, 0.495, 0.49, 0.485, 0.48, 0.475, 0.47, 0.465, 0.46, 0.455, 0.45, 0.445, 0.44, 0.435, 0.43, 0.425 },
        .noise_sigma = &[_]f64{ 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02 },
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

    const request = Request{
        .scene = .{
            .id = "scene-common",
            .atmosphere = .{ .layer_count = 18 },
            .spectral_grid = .{ .sample_count = 16 },
        },
        .inverse_problem = .{
            .id = "inverse-common",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{
                        .name = "albedo",
                        .target = .surface_albedo,
                        .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.05 },
                    },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 16,
                .source = .{ .external_observation = .{ .name = "obs" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
            },
        },
        .measurement_binding = .{
            .source = .{ .external_observation = .{ .name = "obs" } },
            .borrowed_product = .init(&product),
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };

    const valid = try RetrievalProblem.fromRequest(&request);
    try valid.validateForMethod(.oe);
    try valid.validateForMethod(.doas);
    try valid.validateForMethod(.dismas);

    const layout = valid.layoutRequirements();
    try std.testing.expectEqual(@as(u32, 18), layout.layer_count);
    try std.testing.expectEqual(@as(u32, 1), layout.state_parameter_count);
    try std.testing.expectEqual(@as(u32, 16), layout.measurement_count);

    const missing_mode: RetrievalProblem = .{
        .scene = request.scene,
        .inverse_problem = request.inverse_problem.?,
        .derivative_mode = .none,
        .jacobians_requested = true,
    };
    try std.testing.expectError(Error.DerivativeModeRequired, missing_mode.validateForMethod(.oe));
    try std.testing.expectError(Error.DerivativeModeRequired, missing_mode.validateForMethod(.doas));
    try std.testing.expectError(Error.DerivativeModeRequired, missing_mode.validateForMethod(.dismas));
    try std.testing.expectEqual(ImplementationClass.real, Method.oe.classification());
    try std.testing.expectEqual(ImplementationClass.real, Method.doas.classification());
    try std.testing.expectEqual(ImplementationClass.real, Method.dismas.classification());
    try std.testing.expectEqualStrings("rodgers_oe", Method.oe.implementationLabel());
    try std.testing.expectEqualStrings("classic_doas", Method.doas.implementationLabel());
    try std.testing.expectEqualStrings("direct_intensity_dismas", Method.dismas.implementationLabel());
}

test "retrieval problem validates masked measurement counts against bound products" {
    const product = MeasurementSpaceProduct{
        .summary = .{
            .sample_count = 4,
            .wavelength_start_nm = 759.5,
            .wavelength_end_nm = 762.0,
            .mean_radiance = 1.0,
            .mean_irradiance = 2.0,
            .mean_reflectance = 0.5,
            .mean_noise_sigma = 0.02,
        },
        .wavelengths = &[_]f64{ 759.5, 760.5, 761.5, 762.0 },
        .radiance = &[_]f64{ 1.0, 0.8, 0.85, 0.9 },
        .irradiance = &[_]f64{ 2.0, 2.0, 2.0, 2.0 },
        .reflectance = &[_]f64{ 0.5, 0.4, 0.425, 0.45 },
        .noise_sigma = &[_]f64{ 0.02, 0.02, 0.02, 0.02 },
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

    const request = Request{
        .scene = .{
            .id = "scene-bound-measurement",
            .atmosphere = .{ .layer_count = 18 },
            .spectral_grid = .{
                .start_nm = 759.5,
                .end_nm = 762.0,
                .sample_count = 4,
            },
        },
        .inverse_problem = .{
            .id = "inverse-bound-measurement",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{
                        .name = "albedo",
                        .target = .surface_albedo,
                        .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.05 },
                    },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 3,
                .source = .{ .external_observation = .{ .name = "obs" } },
                .mask = .{
                    .exclude = &[_]@import("../../model/Scene.zig").SpectralWindow{
                        .{ .start_nm = 760.0, .end_nm = 761.0 },
                    },
                },
            },
        },
        .measurement_binding = .{
            .source = .{ .external_observation = .{ .name = "obs" } },
            .borrowed_product = .init(&product),
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };

    const problem = try RetrievalProblem.fromRequest(&request);
    try std.testing.expectEqual(@as(u32, 3), problem.observed_measurement.?.sample_count);
}

test "solver outcomes own identifiers independently of request buffers" {
    const scene_id = try std.fmt.allocPrint(std.testing.allocator, "scene-{d}", .{17});
    const inverse_problem_id = try std.fmt.allocPrint(std.testing.allocator, "inverse-{d}", .{23});
    const source_name = try std.fmt.allocPrint(std.testing.allocator, "source-{d}", .{5});
    const product_name = try std.testing.allocator.dupe(u8, "radiance");
    const state_values = try std.testing.allocator.dupe(f64, &.{0.42});
    const jacobian_values = try std.testing.allocator.dupe(f64, &.{ 0.1, 0.2, 0.3, 0.4 });

    const observed_product = MeasurementSpaceProduct{
        .summary = .{
            .sample_count = 1,
            .wavelength_start_nm = 760.5,
            .wavelength_end_nm = 760.5,
            .mean_radiance = 1.2,
            .mean_irradiance = 2.0,
            .mean_reflectance = 0.6,
            .mean_noise_sigma = 0.01,
        },
        .wavelengths = &[_]f64{760.5},
        .radiance = &[_]f64{1.2},
        .irradiance = &[_]f64{2.0},
        .reflectance = &[_]f64{0.6},
        .noise_sigma = &[_]f64{0.01},
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

    const owned_outcome = try outcome(
        std.testing.allocator,
        .{
            .scene = .{
                .id = scene_id,
                .spectral_grid = .{ .sample_count = 1 },
            },
            .inverse_problem = .{
                .id = inverse_problem_id,
                .state_vector = .{
                    .parameter_names = &[_][]const u8{"x0"},
                    .value_count = 1,
                },
                .measurements = .{
                    .product_name = "radiance",
                    .observable = .radiance,
                    .sample_count = 1,
                },
            },
            .derivative_mode = .semi_analytical,
            .observed_measurement = .{
                .source_name = source_name,
                .observable = .radiance,
                .product_name = product_name,
                .sample_count = 1,
                .product = .init(&observed_product),
            },
        },
        .oe,
        2,
        1.0,
        true,
        true,
        0.5,
        0.2,
        0.1,
        null,
        .{
            .parameter_names = &[_][]const u8{"x0"},
            .values = state_values,
        },
        null,
        null,
        .{
            .row_count = 2,
            .column_count = 2,
            .values = jacobian_values,
        },
        null,
        null,
    );
    defer {
        var owned = owned_outcome;
        owned.deinit(std.testing.allocator);
    }

    std.testing.allocator.free(scene_id);
    std.testing.allocator.free(inverse_problem_id);
    std.testing.allocator.free(source_name);
    std.testing.allocator.free(product_name);

    try std.testing.expectEqualStrings("scene-17", owned_outcome.scene_id);
    try std.testing.expectEqualStrings("inverse-23", owned_outcome.inverse_problem_id);
    try std.testing.expectEqualStrings("source-5", owned_outcome.observed_measurement.?.source_name);
    try std.testing.expectEqualStrings("x0", owned_outcome.state_estimate.parameter_names[0]);
    try std.testing.expectEqual(@as(u32, 2), owned_outcome.jacobian.?.row_count);
}
