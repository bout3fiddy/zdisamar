//! Purpose:
//!   Materialize owned retrieval products from a solver outcome.
//!
//! Physics:
//!   Converts solver-space state, Jacobian, averaging-kernel, and posterior products into
//!   result-owned measurement/state products derived from the fitted scene.
//!
//! Vendor:
//!   `retrieval product materialization`
//!
//! Design:
//!   Keep the solver outcome generic and build result-facing owned products here so retrieval
//!   providers do not need to duplicate output-shaping and fitted-measurement logic.
//!
//! Invariants:
//!   Fitted products are materialized from the fitted scene using the prepared plan's provider
//!   set. OE results must expose Jacobian, averaging-kernel, and posterior covariance products.
//!
//! Validation:
//!   Retrieval integration tests and golden/parity tests that inspect fitted measurements and
//!   solver-derived matrix outputs.

const std = @import("std");

const errors = @import("../errors.zig");
const PreparedPlan = @import("../Plan.zig").PreparedPlan;
const Result = @import("../Result.zig").Result;
const RetrievalContracts = @import("../../retrieval/common/contracts.zig");
const RetrievalStateAccess = @import("../../retrieval/common/state_access.zig");
const MeasurementSpace = @import("../../kernels/transport/measurement.zig");
const MeasurementSpaceProduct = MeasurementSpace.MeasurementSpaceProduct;
const MeasurementQuantity = @import("../../model/Measurement.zig").Quantity;
const shared = @import("shared.zig");

/// Purpose:
///   Convert a solver outcome into the owned retrieval products attached to a result.
pub fn materialize(
    allocator: std.mem.Allocator,
    plan: *const PreparedPlan,
    problem: RetrievalContracts.RetrievalProblem,
    outcome: RetrievalContracts.SolverOutcome,
) errors.Error!Result.RetrievalProducts {
    const fitted_scene = outcome.fitted_scene orelse return error.InvalidRequest;

    var prepared_optics = plan.providers.optics.prepareForScene(allocator, &fitted_scene) catch |err| switch (err) {
        error.OutOfMemory => return errors.Error.OutOfMemory,
        else => return errors.Error.InvalidRequest,
    };
    defer prepared_optics.deinit(allocator);

    var fitted_measurement = MeasurementSpace.simulateProduct(
        allocator,
        &fitted_scene,
        plan.transport_route,
        &prepared_optics,
        shared.measurementProviders(plan),
    ) catch |err| switch (err) {
        error.OutOfMemory => return errors.Error.OutOfMemory,
        else => return errors.Error.InvalidRequest,
    };
    errdefer fitted_measurement.deinit(allocator);

    const state_vector = try materializeStateVectorProduct(allocator, problem, outcome);
    errdefer {
        var owned = state_vector;
        owned.deinit(allocator);
    }

    const jacobian = if (outcome.jacobian) |matrix|
        try materializeMatrixProduct(allocator, problem, matrix)
    else if (outcome.method.classification() == .surrogate and outcome.jacobians_used)
        // DECISION:
        //   Surrogate methods that report Jacobian usage but do not expose an explicit matrix are
        //   materialized through a typed finite-difference fallback on the fitted scene.
        try materializeSurrogateJacobianProduct(
            allocator,
            plan,
            problem,
            outcome,
            fitted_measurement,
        )
    else
        null;
    errdefer if (jacobian) |product| {
        var owned = product;
        owned.deinit(allocator);
    };

    const averaging_kernel = if (outcome.averaging_kernel) |matrix|
        try materializeMatrixProduct(allocator, problem, matrix)
    else
        null;
    errdefer if (averaging_kernel) |kernel| {
        var owned = kernel;
        owned.deinit(allocator);
    };

    const posterior_covariance = if (outcome.posterior_covariance) |matrix|
        try materializeMatrixProduct(allocator, problem, matrix)
    else
        null;
    errdefer if (posterior_covariance) |matrix| {
        var owned = matrix;
        owned.deinit(allocator);
    };

    if (outcome.method == .oe and
        (jacobian == null or averaging_kernel == null or posterior_covariance == null))
    {
        return error.InvalidRequest;
    }

    return .{
        .state_vector = state_vector,
        .fitted_measurement = fitted_measurement,
        .averaging_kernel = averaging_kernel,
        .jacobian = jacobian,
        .posterior_covariance = posterior_covariance,
    };
}

/// Purpose:
///   Duplicate the solver state estimate into a result-owned state-vector product.
fn materializeStateVectorProduct(
    allocator: std.mem.Allocator,
    problem: RetrievalContracts.RetrievalProblem,
    outcome: RetrievalContracts.SolverOutcome,
) !Result.RetrievalStateVectorProduct {
    const parameter_names = try duplicateParameterNames(allocator, problem);
    errdefer freeStringSlice(allocator, parameter_names);

    const values = try allocator.dupe(f64, outcome.state_estimate.values);
    errdefer allocator.free(values);

    return .{
        .parameter_names = parameter_names,
        .values = values,
    };
}

/// Purpose:
///   Duplicate a solver matrix into a result-owned retrieval matrix product.
fn materializeMatrixProduct(
    allocator: std.mem.Allocator,
    problem: RetrievalContracts.RetrievalProblem,
    matrix: RetrievalContracts.SolverOutcome.Matrix,
) !Result.RetrievalMatrixProduct {
    const parameter_names = try duplicateParameterNames(allocator, problem);
    errdefer freeStringSlice(allocator, parameter_names);

    const values = try allocator.dupe(f64, matrix.values);
    errdefer allocator.free(values);

    return .{
        .row_count = matrix.row_count,
        .column_count = matrix.column_count,
        .parameter_names = parameter_names,
        .values = values,
    };
}

/// Purpose:
///   Materialize a fitted-scene Jacobian when the solver used surrogate Jacobians internally but
///   did not return an explicit matrix.
fn materializeSurrogateJacobianProduct(
    allocator: std.mem.Allocator,
    plan: *const PreparedPlan,
    problem: RetrievalContracts.RetrievalProblem,
    outcome: RetrievalContracts.SolverOutcome,
    fitted_measurement: MeasurementSpaceProduct,
) errors.Error!Result.RetrievalMatrixProduct {
    const parameter_names = try duplicateParameterNames(allocator, problem);
    errdefer freeStringSlice(allocator, parameter_names);

    const sample_count = fitted_measurement.wavelengths.len;
    const state_count = outcome.state_estimate.values.len;
    const values = try allocator.alloc(f64, sample_count * state_count);
    errdefer allocator.free(values);

    const observable = measurementObservable(problem);
    for (0..state_count) |state_index| {
        const perturbed_values = try allocator.dupe(f64, outcome.state_estimate.values);
        defer allocator.free(perturbed_values);

        const delta = jacobianStep(perturbed_values[state_index]);
        perturbed_values[state_index] += delta;

        const perturbed_scene = RetrievalStateAccess.sceneForState(problem, perturbed_values) catch |err| switch (err) {
            error.OutOfMemory => return errors.Error.OutOfMemory,
            else => return errors.Error.InvalidRequest,
        };
        var prepared_optics = plan.providers.optics.prepareForScene(allocator, &perturbed_scene) catch |err| switch (err) {
            error.OutOfMemory => return errors.Error.OutOfMemory,
            else => return errors.Error.InvalidRequest,
        };
        defer prepared_optics.deinit(allocator);

        var perturbed_product = MeasurementSpace.simulateProduct(
            allocator,
            &perturbed_scene,
            plan.transport_route,
            &prepared_optics,
            shared.measurementProviders(plan),
        ) catch |err| switch (err) {
            error.OutOfMemory => return errors.Error.OutOfMemory,
            else => return errors.Error.InvalidRequest,
        };
        defer perturbed_product.deinit(allocator);

        for (0..sample_count) |sample_index| {
            const base_value = try measurementValue(fitted_measurement, observable, sample_index);
            const perturbed_value = try measurementValue(perturbed_product, observable, sample_index);
            values[sample_index * state_count + state_index] = (perturbed_value - base_value) / delta;
        }
    }

    return .{
        .row_count = @intCast(sample_count),
        .column_count = @intCast(state_count),
        .parameter_names = parameter_names,
        .values = values,
    };
}

/// Purpose:
///   Duplicate the retrieval parameter names into owned result storage.
fn duplicateParameterNames(
    allocator: std.mem.Allocator,
    problem: RetrievalContracts.RetrievalProblem,
) ![]const []const u8 {
    const state_vector = problem.inverse_problem.state_vector;
    if (state_vector.parameters.len == 0) return &[_][]const u8{};

    const names = try allocator.alloc([]const u8, state_vector.parameters.len);
    errdefer allocator.free(names);

    var copied: usize = 0;
    errdefer {
        for (names[0..copied]) |value| allocator.free(value);
    }
    for (state_vector.parameters, 0..) |parameter, index| {
        names[index] = try allocator.dupe(u8, parameter.name);
        copied = index + 1;
    }
    return names;
}

/// Purpose:
///   Free an owned slice of owned strings.
fn freeStringSlice(allocator: std.mem.Allocator, values: []const []const u8) void {
    if (values.len == 0) return;
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

/// Purpose:
///   Return the observable used to interpret a fitted measurement-space product for this problem.
fn measurementObservable(problem: RetrievalContracts.RetrievalProblem) MeasurementQuantity {
    return problem.inverse_problem.measurements.observable;
}

/// Purpose:
///   Read one observable value from a measurement-space product by sample index.
fn measurementValue(product: MeasurementSpaceProduct, observable: MeasurementQuantity, index: usize) errors.Error!f64 {
    return switch (observable) {
        .radiance => product.radiance[index],
        .irradiance => product.irradiance[index],
        .reflectance => product.reflectance[index],
        .slant_column => errors.Error.InvalidRequest,
    };
}

/// Purpose:
///   Choose a finite-difference step for surrogate Jacobian materialization in physical state
///   space.
fn jacobianStep(value: f64) f64 {
    return if (@abs(value) > 1.0e-6) 1.0e-3 * @abs(value) else 1.0e-3;
}
