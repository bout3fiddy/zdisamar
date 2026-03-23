//! Purpose:
//!   Shared retrieval solver mechanics for state transforms, damping, and
//!   linear-system handling.
//!
//! Physics:
//!   This module owns the reusable numeric plumbing that turns a solver-space
//!   state into a physical scene, evaluates prior penalties, and solves the
//!   damped normal equations used by retrieval methods.
//!
//! Vendor:
//!   Retrieval solver state normalization, damping, and step-acceptance stages.
//!
//! Design:
//!   Keep the method-specific policy in the solver modules. Share only the
//!   algebra, state transform helpers, and backtracking mechanics that are
//!   identical across OE, DOAS, and DISMAS.
//!
//! Invariants:
//!   State vectors and Jacobians must remain shape-consistent, and transform
//!   conversions must never silently bypass the typed parameter bounds.
//!
//! Validation:
//!   Retrieval solver integration and parity tests exercise these helpers
//!   through the public solver entrypoints.

const std = @import("std");
const common = @import("contracts.zig");
const transforms = @import("transforms.zig");
const state_access = @import("state_access.zig");
const dense = @import("../../kernels/linalg/small_dense.zig");
const cholesky = @import("../../kernels/linalg/cholesky.zig");
const svd_fallback = @import("../../kernels/linalg/svd_fallback.zig");
const vector_ops = @import("../../kernels/linalg/vector_ops.zig");
const Allocator = std.mem.Allocator;
const StateParameter = @import("../../model/Scene.zig").StateParameter;

pub const TrialCosts = struct {
    measurement_cost: f64,
    prior_cost: f64,
};

pub const BacktrackResult = struct {
    scale: f64,
    measurement_cost: f64,
    prior_cost: f64,
};

pub fn backtrackAcceptedStep(
    base_state: []const f64,
    step: []const f64,
    min_scale: f64,
    current_total_cost: f64,
    candidate_state: []f64,
    context: anytype,
    comptime evaluate: anytype,
) common.Error!?BacktrackResult {
    if (min_scale <= 0.0) return common.Error.InvalidRequest;
    if (base_state.len != step.len or candidate_state.len != base_state.len) {
        return common.Error.ShapeMismatch;
    }

    var scale: f64 = 1.0;
    while (scale >= min_scale) : (scale *= 0.5) {
        try vector_ops.copy(base_state, candidate_state);
        for (candidate_state, step) |*slot, step_value| {
            slot.* += scale * step_value;
        }

        const trial = try evaluate(context, candidate_state);
        if (trial.measurement_cost + trial.prior_cost <= current_total_cost) {
            return .{
                .scale = scale,
                .measurement_cost = trial.measurement_cost,
                .prior_cost = trial.prior_cost,
            };
        }
    }
    return null;
}

pub fn normalizeSolverState(
    problem: common.RetrievalProblem,
    solver_state: []f64,
    physical_state: []f64,
) common.Error!void {
    if (solver_state.len != physical_state.len) return common.Error.ShapeMismatch;
    for (problem.inverse_problem.state_vector.parameters, solver_state, physical_state) |parameter, *solver_value, *physical_value| {
        const clamped = clampPhysical(parameter, transforms.toPhysicalSpace(parameter.transform, solver_value.*));
        physical_value.* = clamped;
        solver_value.* = safeSolverValue(parameter, clamped) catch return common.Error.InvalidRequest;
    }
}

pub fn seedSolverState(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    layout: state_access.ResolvedStateLayout,
    prior_mean_solver: []const f64,
    out: []f64,
) common.Error!void {
    const seeded_physical = try state_access.seedStateWithLayout(allocator, problem, layout);
    defer allocator.free(seeded_physical);

    if (prior_mean_solver.len != out.len) return common.Error.ShapeMismatch;
    for (problem.inverse_problem.state_vector.parameters, seeded_physical, prior_mean_solver, out) |parameter, seeded_value, prior_solver, *slot| {
        slot.* = safeSolverValue(parameter, seeded_value) catch prior_solver;
    }
}

pub fn parameterNames(allocator: Allocator, problem: common.RetrievalProblem) ![]const []const u8 {
    const parameters = problem.inverse_problem.state_vector.parameters;
    const names = try allocator.alloc([]const u8, parameters.len);
    for (parameters, 0..) |parameter, index| {
        names[index] = parameter.name;
    }
    return names;
}

pub fn addMatrixInPlace(lhs: []f64, rhs: []const f64) void {
    for (lhs, rhs) |*left, right| left.* += right;
}

pub fn subtractMatVec(out: []f64, matrix: []const f64, lhs: []const f64, rhs: []const f64) void {
    const dimension = out.len;
    for (0..dimension) |row| {
        var total: f64 = 0.0;
        for (0..dimension) |column| {
            total += matrix[dense.index(row, column, dimension)] * (lhs[column] - rhs[column]);
        }
        out[row] -= total;
    }
}

pub fn addDiagonal(matrix: []f64, dimension: usize, value: f64) void {
    if (value == 0.0) return;
    for (0..dimension) |diag_index| {
        matrix[dense.index(diag_index, diag_index, dimension)] += value;
    }
}

pub fn priorCost(inverse_covariance: []const f64, solver_state: []const f64, prior_mean_solver: []const f64) f64 {
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

pub fn clampPhysical(parameter: StateParameter, value: f64) f64 {
    if (!parameter.bounds.enabled) return value;
    return std.math.clamp(value, parameter.bounds.min, parameter.bounds.max);
}

pub fn safeSolverValue(parameter: StateParameter, physical_value: f64) !f64 {
    return switch (parameter.transform) {
        .none => physical_value,
        .log => transforms.toSolverSpace(.log, @max(physical_value, 1.0e-9)),
        .logit => transforms.toSolverSpace(.logit, std.math.clamp(physical_value, 1.0e-9, 1.0 - 1.0e-9)),
    };
}

pub fn transformScale(parameter: StateParameter, solver_value: f64, physical_value: f64) f64 {
    const derivative = transforms.dPhysicalDsolver(parameter.transform, solver_value);
    if (parameter.bounds.enabled and (physical_value <= parameter.bounds.min or physical_value >= parameter.bounds.max)) {
        return 0.0;
    }
    return derivative;
}

pub fn finiteDifferenceStep(parameter: StateParameter, physical_value: f64) f64 {
    var step = @max(@abs(physical_value) * 1.0e-3, 1.0e-6);
    if (parameter.bounds.enabled) {
        step = @min(step, 0.25 * @max(parameter.bounds.max - parameter.bounds.min, 1.0e-6));
    }
    return step;
}

pub fn solveSymmetricSystem(
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

pub fn invertHessian(
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
