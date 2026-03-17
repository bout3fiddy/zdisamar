const std = @import("std");
const Request = @import("../../core/Request.zig").Request;
const DerivativeMode = @import("../../model/Scene.zig").DerivativeMode;
const InverseProblem = @import("../../model/Scene.zig").InverseProblem;
const LayoutRequirements = @import("../../model/Scene.zig").LayoutRequirements;
const Scene = @import("../../model/Scene.zig").Scene;
const MeasurementSpaceSummary = @import("../../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;
const Allocator = std.mem.Allocator;

pub const Method = enum {
    oe,
    doas,
    dismas,

    pub fn classification(self: Method) ImplementationClass {
        _ = self;
        return .surrogate;
    }

    pub fn implementationLabel(self: Method) []const u8 {
        return switch (self) {
            .oe => "surrogate_oe",
            .doas => "surrogate_doas",
            .dismas => "surrogate_dismas",
        };
    }
};

pub const DerivativeRequirement = enum {
    optional,
    required,
};

pub const ImplementationClass = enum {
    surrogate,
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
        observable: []const u8 = "",
        product_name: []const u8 = "",
        sample_count: u32 = 0,
        summary: MeasurementSpaceSummary,

        pub fn deinitOwned(self: *ObservedMeasurement, allocator: Allocator) void {
            if (self.source_name.len != 0) allocator.free(self.source_name);
            if (self.observable.len != 0) allocator.free(self.observable);
            if (self.product_name.len != 0) allocator.free(self.product_name);
            self.* = undefined;
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
            if (inverse_problem.measurements.source.name.len != 0 and
                !std.mem.eql(u8, inverse_problem.measurements.source.name, binding.source_name))
            {
                return Error.InvalidRequest;
            }
            if (binding.observable.len != 0 and
                inverse_problem.measurements.observable.len != 0 and
                !std.mem.eql(u8, inverse_problem.measurements.observable, binding.observable))
            {
                return Error.InvalidRequest;
            }
            if (binding.product.summary.sample_count != inverse_problem.measurements.sample_count) {
                return Error.InvalidRequest;
            }
            observed_measurement = .{
                .source_name = binding.source_name,
                .observable = if (binding.observable.len != 0) binding.observable else inverse_problem.measurements.observable,
                .product_name = inverse_problem.measurements.product,
                .sample_count = binding.product.summary.sample_count,
                .summary = binding.product.summary,
            };
        } else if (inverse_problem.measurements.source.kind == .stage_product or inverse_problem.measurements.source.kind == .external_observation) {
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

        if (self.inverse_problem.id.len == 0) {
            return Error.MissingInverseProblem;
        }
        if (self.inverse_problem.state_vector.count() == 0) {
            return Error.MissingStateVector;
        }
        if (self.inverse_problem.measurements.sample_count == 0) {
            return Error.MissingMeasurements;
        }
        if (self.inverse_problem.measurements.product.len == 0) {
            return Error.MissingMeasurementProduct;
        }
        if (self.jacobians_requested and self.derivative_mode == .none) {
            return Error.DerivativeModeRequired;
        }
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
    }
};

pub const SolverOutcome = struct {
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
    observed_measurement: ?RetrievalProblem.ObservedMeasurement = null,
    fitted_measurement: ?MeasurementSpaceSummary = null,
    state_estimate: StateEstimate = .{},
    fitted_scene: ?Scene = null,

    pub fn deinit(self: *SolverOutcome, allocator: Allocator) void {
        if (self.scene_id.len != 0) allocator.free(self.scene_id);
        if (self.inverse_problem_id.len != 0) allocator.free(self.inverse_problem_id);
        if (self.observed_measurement) |*measurement| {
            measurement.deinitOwned(allocator);
            self.observed_measurement = null;
        }
        self.state_estimate.deinit(allocator);
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
    state_estimate: SolverOutcome.StateEstimate,
    fitted_scene: ?Scene,
    fitted_measurement: ?MeasurementSpaceSummary,
) !SolverOutcome {
    const scene_id = try allocator.dupe(u8, problem.scene.id);
    errdefer allocator.free(scene_id);
    const inverse_problem_id = try allocator.dupe(u8, problem.inverse_problem.id);
    errdefer allocator.free(inverse_problem_id);
    var owned_observed_measurement: ?RetrievalProblem.ObservedMeasurement = null;
    if (problem.observed_measurement) |observed| {
        const source_name = try allocator.dupe(u8, observed.source_name);
        errdefer allocator.free(source_name);
        const observable = try allocator.dupe(u8, observed.observable);
        errdefer allocator.free(observable);
        const product_name = try allocator.dupe(u8, observed.product_name);
        errdefer allocator.free(product_name);
        owned_observed_measurement = .{
            .source_name = source_name,
            .observable = observable,
            .product_name = product_name,
            .sample_count = observed.sample_count,
            .summary = observed.summary,
        };
    }

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
        .observed_measurement = owned_observed_measurement,
        .fitted_measurement = fitted_measurement,
        .state_estimate = .{
            .parameter_names = parameter_names,
            .values = state_estimate.values,
        },
        .fitted_scene = fitted_scene,
    };
}

test "retrieval contracts enforce canonical problem invariants" {
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
                    .{ .name = "albedo", .target = "scene.surface.albedo" },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 16,
            },
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };

    const valid = try RetrievalProblem.fromRequest(&request);
    try valid.validateForMethod(.oe);

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
    try std.testing.expectEqual(ImplementationClass.surrogate, Method.oe.classification());
    try std.testing.expectEqualStrings("surrogate_oe", Method.oe.implementationLabel());
}

test "retrieval problem requires inverse problem in request conversion" {
    const request = Request{
        .scene = .{
            .id = "scene-no-inverse",
            .spectral_grid = .{ .sample_count = 8 },
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };

    try std.testing.expectError(
        Error.MissingInverseProblem,
        RetrievalProblem.fromRequest(&request),
    );
}

test "solver outcomes own identifiers independently of request buffers" {
    const scene_id = try std.fmt.allocPrint(std.testing.allocator, "scene-{d}", .{17});
    const inverse_problem_id = try std.fmt.allocPrint(std.testing.allocator, "inverse-{d}", .{23});
    const source_name = try std.fmt.allocPrint(std.testing.allocator, "source-{d}", .{5});
    const observable = try std.fmt.allocPrint(std.testing.allocator, "radiance", .{});
    const product_name = try std.fmt.allocPrint(std.testing.allocator, "radiance", .{});
    const state_values = try std.testing.allocator.dupe(f64, &.{0.42});

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
                    .product = "radiance",
                    .observable = "radiance",
                    .sample_count = 1,
                },
            },
            .derivative_mode = .semi_analytical,
            .observed_measurement = .{
                .source_name = source_name,
                .observable = observable,
                .product_name = product_name,
                .sample_count = 1,
                .summary = .{
                    .sample_count = 1,
                    .wavelength_start_nm = 760.5,
                    .wavelength_end_nm = 760.5,
                    .mean_radiance = 1.2,
                    .mean_irradiance = 2.0,
                    .mean_reflectance = 0.6,
                    .mean_noise_sigma = 0.01,
                },
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
        .{
            .parameter_names = &[_][]const u8{"x0"},
            .values = state_values,
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
    std.testing.allocator.free(observable);
    std.testing.allocator.free(product_name);

    try std.testing.expectEqualStrings("scene-17", owned_outcome.scene_id);
    try std.testing.expectEqualStrings("inverse-23", owned_outcome.inverse_problem_id);
    try std.testing.expectEqualStrings("source-5", owned_outcome.observed_measurement.?.source_name);
    try std.testing.expectEqualStrings("x0", owned_outcome.state_estimate.parameter_names[0]);
}

fn validateScene(scene: Scene) Error!void {
    scene.validate() catch |err| switch (err) {
        error.MissingScene => return Error.MissingScene,
        error.MissingObservationInstrument => return Error.MissingObservationInstrument,
        else => return Error.InvalidRequest,
    };
}
