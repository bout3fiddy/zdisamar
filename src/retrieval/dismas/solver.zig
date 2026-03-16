const std = @import("std");
const common = @import("../common/contracts.zig");
const forward_model = @import("../common/forward_model.zig");
const surrogate_forward = @import("../common/synthetic_forward.zig");
const Allocator = std.mem.Allocator;

pub fn solve(allocator: Allocator, problem: common.RetrievalProblem) common.Error!common.SolverOutcome {
    return solveWithEvaluator(allocator, problem, forward_model.defaultEvaluator());
}

pub fn solveWithEvaluator(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.SummaryEvaluator,
) common.Error!common.SolverOutcome {
    try problem.validateForMethod(.dismas);
    const layout = try surrogate_forward.resolveStateLayout(problem);

    const observed = try surrogate_forward.observedSummary(problem, evaluator);
    const target = surrogate_forward.featureVector(observed, .dismas);
    const anchor = try surrogate_forward.anchorStateWithLayout(allocator, problem, .dismas, observed, layout);
    defer allocator.free(anchor);

    const state = try surrogate_forward.seedStateWithLayout(allocator, problem, layout);
    errdefer allocator.free(state);

    const max_iterations: u32 = if (problem.inverse_problem.fit_controls.max_iterations != 0)
        @min(problem.inverse_problem.fit_controls.max_iterations, 10)
    else
        7;

    var iterations: u32 = 0;
    var reduced_cost: f64 = std.math.inf(f64);
    var residual_norm: f64 = std.math.inf(f64);
    var step_norm: f64 = std.math.inf(f64);
    var converged = false;

    while (iterations < max_iterations) : (iterations += 1) {
        const predicted = surrogate_forward.featureVector(
            try surrogate_forward.summarizeStateWithLayout(problem, .dismas, state, evaluator, layout),
            .dismas,
        );
        residual_norm = surrogate_forward.residualNorm(predicted, target);

        var step_sq: f64 = 0.0;
        for (state, 0..) |*value, index| {
            const step = 0.45 * (anchor[index] - value.*);
            value.* += step;
            step_sq += step * step;
        }
        step_norm = std.math.sqrt(step_sq);
        reduced_cost = residual_norm / @as(f64, @floatFromInt(target.len));
        converged = step_norm < 5.0e-4 or residual_norm < 5.0e-4;
        if (converged) {
            iterations += 1;
            break;
        }
    }

    const fitted_scene = try surrogate_forward.sceneForStateWithLayout(problem, state, layout);
    const fitted_summary = try surrogate_forward.summarizeStateWithLayout(problem, .dismas, state, evaluator, layout);
    const dfs = std.math.clamp(
        @as(f64, @floatFromInt(state.len)) * (0.70 + 0.06 * @exp(-step_norm)),
        0.0,
        @as(f64, @floatFromInt(state.len)),
    );
    return common.outcome(
        problem,
        .dismas,
        iterations,
        reduced_cost,
        converged,
        true,
        dfs,
        residual_norm,
        step_norm,
        .{
            .parameter_names = problem.inverse_problem.state_vector.parameter_names,
            .values = state,
        },
        fitted_scene,
        fitted_summary,
    );
}

test "dismas retrieval requires explicit derivative mode" {
    const base_problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-dismas",
            .spectral_grid = .{ .sample_count = 20 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-dismas",
            .state_vector = .{
                .parameter_names = &[_][]const u8{ "state_a", "state_b", "state_c" },
                .value_count = 3,
            },
            .measurements = .{
                .product = "multi_band_signal",
                .sample_count = 20,
            },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
    };

    const ok = try solveWithEvaluator(std.testing.allocator, base_problem, forward_model.defaultEvaluator());
    defer {
        var owned = ok;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(common.Method.dismas, ok.method);
    try std.testing.expect(ok.jacobians_used);
    try std.testing.expect(ok.dfs > 0.0);

    var missing_mode = base_problem;
    missing_mode.derivative_mode = .none;
    try std.testing.expectError(common.Error.DerivativeModeRequired, solveWithEvaluator(std.testing.allocator, missing_mode, forward_model.defaultEvaluator()));
}
