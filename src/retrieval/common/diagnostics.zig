const std = @import("std");
const Convergence = @import("../../model/InverseProblem.zig").Convergence;
const vector_ops = @import("../../kernels/linalg/vector_ops.zig");

pub const Summary = struct {
    measurement_cost: f64,
    prior_cost: f64,
    total_cost: f64,
    reduced_chi_square: f64,
    step_norm: f64,
    state_relative: f64,
    cost_relative: f64,
    dfs: f64,
    converged: bool,
};

pub fn assess(
    previous_total_cost: ?f64,
    measurement_cost: f64,
    prior_cost: f64,
    step: []const f64,
    state: []const f64,
    convergence: Convergence,
    measurement_count: u32,
    dfs: f64,
) Summary {
    const total_cost = measurement_cost + prior_cost;
    const step_norm = vector_ops.normL2(step);
    const state_relative = vector_ops.relativeNorm(step, state) catch 0.0;
    const cost_relative = if (previous_total_cost) |previous|
        @abs(previous - total_cost) / @max(@abs(previous), 1.0)
    else
        std.math.inf(f64);
    const reduced_chi_square = measurement_cost / @max(@as(f64, @floatFromInt(measurement_count)), 1.0);

    const cost_threshold = if (convergence.cost_relative > 0.0) convergence.cost_relative else 1.0e-4;
    const state_threshold = if (convergence.state_relative > 0.0) convergence.state_relative else 1.0e-4;

    return .{
        .measurement_cost = measurement_cost,
        .prior_cost = prior_cost,
        .total_cost = total_cost,
        .reduced_chi_square = reduced_chi_square,
        .step_norm = step_norm,
        .state_relative = state_relative,
        .cost_relative = cost_relative,
        .dfs = dfs,
        .converged = cost_relative <= cost_threshold and state_relative <= state_threshold,
    };
}

test "retrieval diagnostics compute Rodgers-style convergence metrics" {
    const summary = assess(
        10.0,
        2.0,
        0.5,
        &.{ 0.01, 0.02 },
        &.{ 1.0, 2.0 },
        .{ .cost_relative = 0.9, .state_relative = 0.1 },
        8,
        1.3,
    );
    try std.testing.expect(summary.converged);
    try std.testing.expectApproxEqRel(@as(f64, 0.25), summary.reduced_chi_square, 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.3), summary.dfs, 1e-12);
}
