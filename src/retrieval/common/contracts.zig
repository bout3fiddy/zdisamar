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
};

pub const DerivativeRequirement = enum {
    optional,
    required,
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
    InvalidSampleCount,
    InvalidBounds,
    IndexOutOfRange,
    KernelShapeMismatch,
    CatalogNotBootstrapped,
    InvalidPlan,
    InvalidRequest,
    MissingScene,
    MissingModelFamily,
    MissingTransportRoute,
    MissingObservationInstrument,
    UnsupportedModelFamily,
    PreparedPlanLimitExceeded,
    WorkspacePlanMismatch,
    DerivativeModeMismatch,
    UnsupportedDerivativeMode,
    UnsupportedCapability,
    PluginPrepareFailed,
    PluginExecutionFailed,
};

pub const RetrievalProblem = struct {
    pub const ObservedMeasurement = struct {
        source_name: []const u8 = "",
        observable: []const u8 = "",
        product_name: []const u8 = "",
        sample_count: u32 = 0,
        summary: MeasurementSpaceSummary,
    };

    scene: Scene,
    inverse_problem: InverseProblem,
    derivative_mode: DerivativeMode,
    jacobians_requested: bool = false,
    observed_measurement: ?ObservedMeasurement = null,

    pub fn fromRequest(request: Request) Error!RetrievalProblem {
        try request.scene.validate();

        const inverse_problem = request.inverse_problem orelse return Error.MissingInverseProblem;
        try inverse_problem.validate();

        var observed_measurement: ?ObservedMeasurement = null;
        if (request.measurement_binding) |binding| {
            observed_measurement = .{
                .source_name = binding.source_name,
                .observable = if (binding.observable.len != 0) binding.observable else inverse_problem.measurements.observable,
                .product_name = inverse_problem.measurements.product,
                .sample_count = binding.product.summary.sample_count,
                .summary = binding.product.summary,
            };
        } else if (inverse_problem.measurements.source.kind == .stage_product) {
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
        try self.scene.validate();

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
) SolverOutcome {
    return .{
        .method = method,
        .scene_id = problem.scene.id,
        .inverse_problem_id = problem.inverse_problem.id,
        .derivative_mode = problem.derivative_mode,
        .iterations = iterations,
        .cost = cost,
        .converged = converged,
        .jacobians_used = jacobians_used,
        .dfs = dfs,
        .residual_norm = residual_norm,
        .step_norm = step_norm,
        .observed_measurement = problem.observed_measurement,
        .fitted_measurement = fitted_measurement,
        .state_estimate = state_estimate,
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

    const valid = try RetrievalProblem.fromRequest(request);
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
        RetrievalProblem.fromRequest(request),
    );
}
