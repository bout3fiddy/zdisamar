//! Purpose:
//!   Provide the optimal-estimation retrieval entrypoint.
//!
//! Physics:
//!   OE solves the full inverse problem against the bound measurement product
//!   and produces the posterior covariance and averaging-kernel outputs.
//!
//! Vendor:
//!   Rodgers OE retrieval stage.
//!
//! Design:
//!   Keep the OE entrypoint thin so the shared spectral-fit and common
//!   retrieval helpers own the core mechanics.
//!
//! Invariants:
//!   OE requires an observed measurement binding and a derivative-compatible
//!   state vector.
//!
//! Validation:
//!   OE solver tests cover the evaluator path and posterior product outputs.

const std = @import("std");
const common = @import("../common/contracts.zig");
const covariance = @import("../common/covariance.zig");
const diagnostics = @import("../common/diagnostics.zig");
const forward_model = @import("../common/forward_model.zig");
const jacobian_chain = @import("../common/jacobian_chain.zig");
const priors = @import("../common/priors.zig");
const posterior_products = @import("../common/posterior_products.zig");
const state_access = @import("../common/state_access.zig");
const solver_support = @import("../common/solver_support.zig");
const transforms = @import("../common/transforms.zig");
const cholesky = @import("../../kernels/linalg/cholesky.zig");
const dense = @import("../../kernels/linalg/small_dense.zig");
const MeasurementSpace = @import("../../kernels/transport/measurement.zig");
const svd_fallback = @import("../../kernels/linalg/svd_fallback.zig");
const vector_ops = @import("../../kernels/linalg/vector_ops.zig");
const Allocator = std.mem.Allocator;
const StateParameter = @import("../../model/Scene.zig").StateParameter;

/// Purpose:
///   Solve an OE retrieval using the supplied evaluator.
pub fn solveWithEvaluator(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
) common.Error!common.SolverOutcome {
    try problem.validateForMethod(.oe);
    const layout = try state_access.resolveStateLayout(problem);
    const parameters = problem.inverse_problem.state_vector.parameters;
    const state_count = parameters.len;

    var observed = try forward_model.observedMeasurement(allocator, problem);
    defer observed.deinit(allocator);
    const measurement_count = observed.values.len;

    var prior = try priors.assemble(allocator, problem);
    defer prior.deinit(allocator);

    const solver_state = try allocator.alloc(f64, state_count);
    defer allocator.free(solver_state);
    try solver_support.seedSolverState(allocator, problem, layout, prior.mean_solver, solver_state);

    const max_iterations: u32 = if (problem.inverse_problem.fit_controls.max_iterations != 0)
        problem.inverse_problem.fit_controls.max_iterations
    else
        8;
    const damping: f64 = if (problem.inverse_problem.fit_controls.trust_region.enabled()) 1.0e-3 else 0.0;

    var previous_total_cost: ?f64 = null;
    var iterations: u32 = 0;
    var converged = false;
    var last_step_norm: f64 = std.math.inf(f64);
    const candidate_state = try allocator.alloc(f64, state_count);
    defer allocator.free(candidate_state);
    const accepted_physical_state = try allocator.alloc(f64, state_count);
    defer allocator.free(accepted_physical_state);
    while (iterations < max_iterations) : (iterations += 1) {
        var iteration_context = try linearizeState(allocator, problem, evaluator, layout, solver_state, observed);
        defer iteration_context.deinit(allocator);

        const backtrack_context = BacktrackContext{
            .allocator = allocator,
            .problem = problem,
            .evaluator = evaluator,
            .layout = layout,
            .observed = observed,
            .measurement_inverse_covariance = iteration_context.measurement_inverse_covariance,
            .prior = prior,
        };

        const current_total_cost = iteration_context.measurement_cost + iteration_context.prior_cost;
        const step = try allocator.alloc(f64, state_count);
        defer allocator.free(step);
        try solver_support.solveSymmetricSystem(
            allocator,
            iteration_context.hessian,
            state_count,
            iteration_context.gradient,
            damping,
            step,
        );

        const accepted = try solver_support.backtrackAcceptedStep(
            solver_state,
            step,
            1.0 / 64.0,
            current_total_cost,
            candidate_state,
            backtrack_context,
            BacktrackContext.evaluate,
        );

        if (accepted == null) {
            last_step_norm = 0.0;
            previous_total_cost = current_total_cost;
            iterations += 1;
            break;
        }

        try solver_support.normalizeSolverState(problem, candidate_state, accepted_physical_state);
        try vector_ops.copy(candidate_state, solver_state);
        const scaled_step = try allocator.alloc(f64, state_count);
        defer allocator.free(scaled_step);
        const accepted_step = accepted.?;
        for (scaled_step, step) |*slot, value| slot.* = accepted_step.scale * value;

        const summary = diagnostics.assess(
            previous_total_cost,
            accepted_step.measurement_cost,
            accepted_step.prior_cost,
            scaled_step,
            solver_state,
            problem.inverse_problem.convergence,
            @intCast(measurement_count),
            0.0,
        );
        previous_total_cost = summary.total_cost;
        last_step_norm = summary.step_norm;
        converged = summary.converged;
        if (converged) {
            iterations += 1;
            break;
        }
    }

    var final_context = try linearizeState(allocator, problem, evaluator, layout, solver_state, observed);
    errdefer final_context.deinit(allocator);

    const posterior_covariance = try solver_support.invertHessian(
        allocator,
        final_context.hessian,
        state_count,
        damping,
    );
    errdefer allocator.free(posterior_covariance);

    const averaging_kernel = try allocator.alloc(f64, state_count * state_count);
    errdefer allocator.free(averaging_kernel);
    try posterior_products.buildAveragingKernel(
        posterior_covariance,
        final_context.measurement_normal,
        state_count,
        averaging_kernel,
    );

    const dfs = try dense.trace(averaging_kernel, state_count);
    const final_physical_values = try allocator.dupe(f64, final_context.physical_state);
    errdefer allocator.free(final_physical_values);

    const parameter_names = try solver_support.parameterNames(allocator, problem);
    defer allocator.free(parameter_names);
    const final_jacobian = final_context.jacobian;
    final_context.jacobian = &[_]f64{};
    errdefer allocator.free(final_jacobian);

    const outcome = try common.outcome(
        allocator,
        problem,
        .oe,
        iterations,
        final_context.measurement_cost + final_context.prior_cost,
        converged,
        true,
        dfs,
        vector_ops.normL2(final_context.residual),
        last_step_norm,
        null,
        .{
            .parameter_names = parameter_names,
            .values = final_physical_values,
        },
        final_context.scene,
        final_context.measurement.summary,
        .{
            .row_count = @intCast(measurement_count),
            .column_count = @intCast(state_count),
            .values = final_jacobian,
        },
        .{
            .row_count = @intCast(state_count),
            .column_count = @intCast(state_count),
            .values = averaging_kernel,
        },
        .{
            .row_count = @intCast(state_count),
            .column_count = @intCast(state_count),
            .values = posterior_covariance,
        },
    );
    final_context.deinit(allocator);
    return outcome;
}

const Linearization = struct {
    measurement: forward_model.SpectralMeasurement,
    residual: []f64,
    measurement_inverse_covariance: []f64,
    measurement_normal: []f64,
    jacobian: []f64,
    hessian: []f64,
    gradient: []f64,
    physical_state: []f64,
    scene: ?@import("../../model/Scene.zig").Scene = null,
    measurement_cost: f64,
    prior_cost: f64,

    fn deinit(self: *Linearization, allocator: Allocator) void {
        self.measurement.deinit(allocator);
        if (self.residual.len != 0) allocator.free(self.residual);
        if (self.measurement_inverse_covariance.len != 0) allocator.free(self.measurement_inverse_covariance);
        if (self.measurement_normal.len != 0) allocator.free(self.measurement_normal);
        if (self.jacobian.len != 0) allocator.free(self.jacobian);
        if (self.hessian.len != 0) allocator.free(self.hessian);
        if (self.gradient.len != 0) allocator.free(self.gradient);
        if (self.physical_state.len != 0) allocator.free(self.physical_state);
        self.* = undefined;
    }
};

const BacktrackContext = struct {
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
    layout: state_access.ResolvedStateLayout,
    observed: forward_model.SpectralMeasurement,
    measurement_inverse_covariance: []const f64,
    prior: priors.Assembly,

    fn evaluate(self: @This(), candidate_state: []const f64) common.Error!solver_support.TrialCosts {
        const normalized_state = try self.allocator.dupe(f64, candidate_state);
        defer self.allocator.free(normalized_state);
        const physical_state = try self.allocator.alloc(f64, candidate_state.len);
        defer self.allocator.free(physical_state);
        try solver_support.normalizeSolverState(self.problem, normalized_state, physical_state);

        const candidate_scene = try state_access.sceneForStateWithLayout(self.problem, physical_state, self.layout);
        var candidate_measurement = try forward_model.evaluateMeasurement(self.allocator, self.problem, self.evaluator, candidate_scene);
        defer candidate_measurement.deinit(self.allocator);

        const candidate_measurement_cost = try measurementCostFromValues(
            self.measurement_inverse_covariance,
            self.observed.values,
            candidate_measurement.values,
        );
        const candidate_prior_cost = solver_support.priorCost(self.prior.inverse_covariance, normalized_state, self.prior.mean_solver);
        return .{
            .measurement_cost = candidate_measurement_cost,
            .prior_cost = candidate_prior_cost,
        };
    }
};

fn linearizeState(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
    layout: state_access.ResolvedStateLayout,
    solver_state: []f64,
    observed: forward_model.SpectralMeasurement,
) common.Error!Linearization {
    const state_count = solver_state.len;
    const measurement_count = observed.values.len;

    const normalized_state = try allocator.dupe(f64, solver_state);
    errdefer allocator.free(normalized_state);
    const physical_state = try allocator.alloc(f64, state_count);
    errdefer allocator.free(physical_state);
    try solver_support.normalizeSolverState(problem, normalized_state, physical_state);

    const scene = try state_access.sceneForStateWithLayout(problem, physical_state, layout);
    var measurement = try forward_model.evaluateMeasurement(allocator, problem, evaluator, scene);
    errdefer measurement.deinit(allocator);

    const residual = try allocator.alloc(f64, measurement_count);
    errdefer allocator.free(residual);
    try vector_ops.subtract(observed.values, measurement.values, residual);

    var measurement_covariance = covariance.diagonalFromSigma(allocator, observed.sigma) catch |err| switch (err) {
        error.OutOfMemory => return common.Error.OutOfMemory,
        error.SingularVariance, error.ShapeMismatch => return common.Error.InvalidRequest,
    };
    defer measurement_covariance.deinit(allocator);

    const measurement_inverse_covariance = try allocator.dupe(f64, measurement_covariance.inverse_values);
    errdefer allocator.free(measurement_inverse_covariance);

    const jacobian_physical = try allocator.alloc(f64, measurement_count * state_count);
    defer allocator.free(jacobian_physical);
    const jacobian_solver = try allocator.alloc(f64, measurement_count * state_count);

    const column_scales = try allocator.alloc(f64, state_count);
    defer allocator.free(column_scales);

    try buildPhysicalJacobian(
        allocator,
        problem,
        evaluator,
        layout,
        normalized_state,
        physical_state,
        measurement,
        jacobian_physical,
        column_scales,
    );
    try jacobian_chain.applyColumnScales(
        jacobian_physical,
        measurement_count,
        state_count,
        column_scales,
        jacobian_solver,
    );

    const hessian = try allocator.alloc(f64, state_count * state_count);
    errdefer allocator.free(hessian);
    const measurement_normal = try allocator.alloc(f64, state_count * state_count);
    errdefer allocator.free(measurement_normal);
    const gradient = try allocator.alloc(f64, state_count);
    errdefer allocator.free(gradient);

    try jacobian_chain.accumulateNormalMatrixWithInverseCovariance(
        jacobian_solver,
        measurement_count,
        state_count,
        measurement_inverse_covariance,
        measurement_normal,
    );
    try jacobian_chain.accumulateNormalMatrixWithInverseCovariance(
        jacobian_solver,
        measurement_count,
        state_count,
        measurement_inverse_covariance,
        hessian,
    );
    try jacobian_chain.accumulateWeightedResidualWithInverseCovariance(
        jacobian_solver,
        measurement_count,
        state_count,
        measurement_inverse_covariance,
        residual,
        gradient,
    );

    var prior = try priors.assemble(allocator, problem);
    defer prior.deinit(allocator);
    solver_support.addMatrixInPlace(hessian, prior.inverse_covariance);
    solver_support.subtractMatVec(gradient, prior.inverse_covariance, normalized_state, prior.mean_solver);

    const measurement_cost_value = measurementCost(measurement_inverse_covariance, residual) catch return common.Error.InvalidRequest;
    const prior_cost_value = solver_support.priorCost(prior.inverse_covariance, normalized_state, prior.mean_solver);

    allocator.free(normalized_state);
    return .{
        .measurement = measurement,
        .residual = residual,
        .measurement_inverse_covariance = measurement_inverse_covariance,
        .measurement_normal = measurement_normal,
        .jacobian = jacobian_solver,
        .hessian = hessian,
        .gradient = gradient,
        .physical_state = physical_state,
        .scene = scene,
        .measurement_cost = measurement_cost_value,
        .prior_cost = prior_cost_value,
    };
}

fn buildPhysicalJacobian(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
    layout: state_access.ResolvedStateLayout,
    solver_state: []const f64,
    physical_state: []const f64,
    base_measurement: forward_model.SpectralMeasurement,
    jacobian_physical: []f64,
    column_scales: []f64,
) common.Error!void {
    const measurement_count = base_measurement.values.len;
    const state_count = physical_state.len;
    @memset(jacobian_physical, 0.0);

    for (problem.inverse_problem.state_vector.parameters, 0..) |parameter, column| {
        column_scales[column] = solver_support.transformScale(parameter, solver_state[column], physical_state[column]);
        if (@abs(column_scales[column]) <= 1.0e-15) continue;

        if (try fillProviderJacobianColumnIfSupported(
            problem,
            parameter,
            base_measurement,
            column,
            state_count,
            jacobian_physical,
        )) {
            continue;
        }

        const step = solver_support.finiteDifferenceStep(parameter, physical_state[column]);
        const lower_allowed = if (parameter.bounds.enabled) parameter.bounds.min else -std.math.inf(f64);
        const upper_allowed = if (parameter.bounds.enabled) parameter.bounds.max else std.math.inf(f64);
        const can_step_backward = physical_state[column] - step > lower_allowed;
        const can_step_forward = physical_state[column] + step < upper_allowed;

        if (can_step_forward and can_step_backward) {
            const plus = try evaluatePerturbedMeasurement(
                allocator,
                problem,
                evaluator,
                layout,
                physical_state,
                column,
                step,
            );
            defer {
                var owned = plus;
                owned.deinit(allocator);
            }
            const minus = try evaluatePerturbedMeasurement(
                allocator,
                problem,
                evaluator,
                layout,
                physical_state,
                column,
                -step,
            );
            defer {
                var owned = minus;
                owned.deinit(allocator);
            }

            for (0..measurement_count) |row| {
                jacobian_physical[dense.index(row, column, state_count)] =
                    (plus.values[row] - minus.values[row]) / (2.0 * step);
            }
        } else {
            const direction = if (can_step_forward) step else -step;
            const perturbed = try evaluatePerturbedMeasurement(
                allocator,
                problem,
                evaluator,
                layout,
                physical_state,
                column,
                direction,
            );
            defer {
                var owned = perturbed;
                owned.deinit(allocator);
            }
            for (0..measurement_count) |row| {
                jacobian_physical[dense.index(row, column, state_count)] =
                    (perturbed.values[row] - base_measurement.values[row]) / direction;
            }
        }
    }
}

fn fillProviderJacobianColumnIfSupported(
    problem: common.RetrievalProblem,
    parameter: StateParameter,
    base_measurement: forward_model.SpectralMeasurement,
    column: usize,
    state_count: usize,
    jacobian_physical: []f64,
) common.Error!bool {
    const routed = base_measurement.jacobian orelse return false;
    if (problem.derivative_mode == .none) return false;
    if (!providerJacobianSupportsTarget(parameter.target)) return false;
    if (routed.len != base_measurement.values.len) return common.Error.ShapeMismatch;

    for (routed, 0..) |value, row| {
        jacobian_physical[dense.index(row, column, state_count)] = value;
    }
    return true;
}

fn providerJacobianSupportsTarget(target: @import("../../model/Scene.zig").StateTarget) bool {
    return switch (target) {
        // Current transport providers only expose a routed optical-depth sensitivity proxy.
        .aerosol_optical_depth_550_nm => true,
        else => false,
    };
}

fn evaluatePerturbedMeasurement(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
    layout: state_access.ResolvedStateLayout,
    base_physical_state: []const f64,
    column: usize,
    delta: f64,
) common.Error!forward_model.SpectralMeasurement {
    const perturbed_state = try allocator.dupe(f64, base_physical_state);
    defer allocator.free(perturbed_state);
    perturbed_state[column] += delta;
    const parameter = problem.inverse_problem.state_vector.parameters[column];
    if (parameter.bounds.enabled) {
        perturbed_state[column] = std.math.clamp(
            perturbed_state[column],
            parameter.bounds.min,
            parameter.bounds.max,
        );
    }
    const perturbed_scene = try state_access.sceneForStateWithLayout(problem, perturbed_state, layout);
    return forward_model.evaluateMeasurement(allocator, problem, evaluator, perturbed_scene);
}

fn solveSymmetricSystem(
    allocator: Allocator,
    hessian: []const f64,
    dimension: usize,
    gradient: []const f64,
    damping: f64,
    out: []f64,
) common.Error!void {
    const factor = try allocator.dupe(f64, hessian);
    defer allocator.free(factor);
    addDiagonal(factor, dimension, damping);

    cholesky.factorInPlace(factor, dimension) catch {
        const workspace = try allocator.alloc(f64, dimension * (dimension + 1));
        defer allocator.free(workspace);
        svd_fallback.dampedSolve(hessian, dimension, gradient, @max(damping, 1.0e-6), out, workspace[0 .. dimension * (dimension + 1)]) catch {
            return common.Error.SingularMatrix;
        };
        return;
    };
    try vector_ops.copy(gradient, out);
    cholesky.solveWithFactor(factor, dimension, gradient, out) catch return common.Error.SingularMatrix;
}

fn invertHessian(
    allocator: Allocator,
    hessian: []const f64,
    dimension: usize,
    damping: f64,
) common.Error![]f64 {
    const inverse = try allocator.alloc(f64, dimension * dimension);
    errdefer allocator.free(inverse);

    const factor = try allocator.dupe(f64, hessian);
    defer allocator.free(factor);
    addDiagonal(factor, dimension, damping);

    if (cholesky.factorInPlace(factor, dimension)) |_| {
        const workspace = try allocator.alloc(f64, 2 * dimension);
        defer allocator.free(workspace);
        cholesky.invertFromFactor(factor, dimension, inverse, workspace) catch return common.Error.SingularMatrix;
        return inverse;
    } else |_| {
        const solve_workspace = try allocator.alloc(f64, dimension * (dimension + 1));
        defer allocator.free(solve_workspace);
        const basis = try allocator.alloc(f64, dimension);
        defer allocator.free(basis);
        const solution = try allocator.alloc(f64, dimension);
        defer allocator.free(solution);

        for (0..dimension) |column| {
            @memset(basis, 0.0);
            basis[column] = 1.0;
            svd_fallback.dampedSolve(hessian, dimension, basis, @max(damping, 1.0e-6), solution, solve_workspace) catch {
                return common.Error.SingularMatrix;
            };
            for (0..dimension) |row| {
                inverse[dense.index(row, column, dimension)] = solution[row];
            }
        }
        return inverse;
    }
}

fn buildGainMatrix(
    allocator: Allocator,
    posterior_covariance: []const f64,
    state_count: usize,
    jacobian: []const f64,
    measurement_count: usize,
    inverse_measurement_covariance: []const f64,
    out: []f64,
) !void {
    if (posterior_covariance.len != state_count * state_count or
        jacobian.len != measurement_count * state_count or
        inverse_measurement_covariance.len != measurement_count * measurement_count or
        out.len != state_count * measurement_count)
    {
        return error.ShapeMismatch;
    }

    @memset(out, 0.0);
    const weighted_jacobian_transpose = try allocator.alloc(f64, state_count * measurement_count);
    defer allocator.free(weighted_jacobian_transpose);
    @memset(weighted_jacobian_transpose, 0.0);

    for (0..state_count) |state_index| {
        for (0..measurement_count) |measurement_index| {
            var total: f64 = 0.0;
            for (0..measurement_count) |inner| {
                total += jacobian[dense.index(inner, state_index, state_count)] *
                    inverse_measurement_covariance[dense.index(inner, measurement_index, measurement_count)];
            }
            weighted_jacobian_transpose[dense.index(state_index, measurement_index, measurement_count)] = total;
        }
    }

    for (0..state_count) |row| {
        for (0..measurement_count) |column| {
            var total: f64 = 0.0;
            for (0..state_count) |inner| {
                total += posterior_covariance[dense.index(row, inner, state_count)] *
                    weighted_jacobian_transpose[dense.index(inner, column, measurement_count)];
            }
            out[dense.index(row, column, measurement_count)] = total;
        }
    }
}

fn buildAveragingKernelFromGain(
    gain_matrix: []const f64,
    state_count: usize,
    jacobian: []const f64,
    measurement_count: usize,
    out: []f64,
) !void {
    if (gain_matrix.len != state_count * measurement_count or
        jacobian.len != measurement_count * state_count or
        out.len != state_count * state_count)
    {
        return error.ShapeMismatch;
    }

    @memset(out, 0.0);
    for (0..state_count) |row| {
        for (0..state_count) |column| {
            var total: f64 = 0.0;
            for (0..measurement_count) |measurement_index| {
                total += gain_matrix[dense.index(row, measurement_index, measurement_count)] *
                    jacobian[dense.index(measurement_index, column, state_count)];
            }
            out[dense.index(row, column, state_count)] = total;
        }
    }
}

fn normalizeSolverState(
    problem: common.RetrievalProblem,
    solver_state: []f64,
    physical_state: []f64,
) common.Error!void {
    for (problem.inverse_problem.state_vector.parameters, solver_state, physical_state) |parameter, *solver_value, *physical_value| {
        const clamped = clampPhysical(parameter, transforms.toPhysicalSpace(parameter.transform, solver_value.*));
        physical_value.* = clamped;
        solver_value.* = safeSolverValue(parameter, clamped) catch return common.Error.InvalidRequest;
    }
}

fn seedSolverState(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    layout: state_access.ResolvedStateLayout,
    prior_mean_solver: []const f64,
    out: []f64,
) common.Error!void {
    const seeded_physical = try state_access.seedStateWithLayout(allocator, problem, layout);
    defer allocator.free(seeded_physical);

    for (problem.inverse_problem.state_vector.parameters, seeded_physical, prior_mean_solver, out) |parameter, seeded_value, prior_solver, *slot| {
        slot.* = safeSolverValue(parameter, seeded_value) catch prior_solver;
    }
}

fn parameterNames(allocator: Allocator, problem: common.RetrievalProblem) ![]const []const u8 {
    const parameters = problem.inverse_problem.state_vector.parameters;
    const names = try allocator.alloc([]const u8, parameters.len);
    for (parameters, 0..) |parameter, index| {
        names[index] = parameter.name;
    }
    return names;
}

fn addMatrixInPlace(lhs: []f64, rhs: []const f64) void {
    for (lhs, rhs) |*left, right| left.* += right;
}

fn subtractMatVec(out: []f64, matrix: []const f64, lhs: []const f64, rhs: []const f64) void {
    const dimension = out.len;
    for (0..dimension) |row| {
        var total: f64 = 0.0;
        for (0..dimension) |column| {
            total += matrix[dense.index(row, column, dimension)] * (lhs[column] - rhs[column]);
        }
        out[row] -= total;
    }
}

fn addDiagonal(matrix: []f64, dimension: usize, value: f64) void {
    if (value == 0.0) return;
    for (0..dimension) |diag_index| {
        matrix[dense.index(diag_index, diag_index, dimension)] += value;
    }
}

fn measurementCost(inverse_measurement_covariance: []const f64, residual: []const f64) !f64 {
    return covariance.quadraticForm(inverse_measurement_covariance, residual);
}

fn measurementCostFromValues(
    inverse_measurement_covariance: []const f64,
    observed_values: []const f64,
    fitted_values: []const f64,
) !f64 {
    if (observed_values.len != fitted_values.len) return error.ShapeMismatch;

    var total: f64 = 0.0;
    for (0..observed_values.len) |row| {
        var row_total: f64 = 0.0;
        for (0..observed_values.len) |column| {
            row_total += inverse_measurement_covariance[dense.index(row, column, observed_values.len)] *
                (observed_values[column] - fitted_values[column]);
        }
        total += (observed_values[row] - fitted_values[row]) * row_total;
    }
    return total;
}

fn priorCost(inverse_covariance: []const f64, solver_state: []const f64, prior_mean_solver: []const f64) f64 {
    const dimension = solver_state.len;
    var total: f64 = 0.0;
    for (0..dimension) |row| {
        var row_total: f64 = 0.0;
        for (0..dimension) |column| {
            row_total += inverse_covariance[dense.index(row, column, dimension)] *
                (solver_state[column] - prior_mean_solver[column]);
        }
        total += (solver_state[row] - prior_mean_solver[row]) * row_total;
    }
    return total;
}

fn clampPhysical(parameter: StateParameter, value: f64) f64 {
    if (!parameter.bounds.enabled) return value;
    return std.math.clamp(value, parameter.bounds.min, parameter.bounds.max);
}

fn safeSolverValue(parameter: StateParameter, physical_value: f64) !f64 {
    return switch (parameter.transform) {
        .none => physical_value,
        .log => transforms.toSolverSpace(.log, @max(physical_value, 1.0e-9)),
        .logit => transforms.toSolverSpace(.logit, std.math.clamp(physical_value, 1.0e-9, 1.0 - 1.0e-9)),
    };
}

fn transformScale(parameter: StateParameter, solver_value: f64, physical_value: f64) f64 {
    const derivative = transforms.dPhysicalDsolver(parameter.transform, solver_value);
    if (parameter.bounds.enabled and (physical_value <= parameter.bounds.min or physical_value >= parameter.bounds.max)) {
        return 0.0;
    }
    return derivative;
}
