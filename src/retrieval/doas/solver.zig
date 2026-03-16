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
    try problem.validateForMethod(.doas);
    const layout = try surrogate_forward.resolveStateLayout(problem);

    const observed = try surrogate_forward.observedSummary(problem, evaluator);
    const target = surrogate_forward.featureVector(observed, .doas);
    const anchor = try surrogate_forward.anchorStateWithLayout(allocator, problem, .doas, observed, layout);
    defer allocator.free(anchor);

    const state = try surrogate_forward.seedStateWithLayout(allocator, problem, layout);
    errdefer allocator.free(state);

    const max_iterations: u32 = if (problem.inverse_problem.fit_controls.max_iterations != 0)
        @min(problem.inverse_problem.fit_controls.max_iterations, 12)
    else
        8;

    var iterations: u32 = 0;
    var reduced_cost: f64 = std.math.inf(f64);
    var residual_norm: f64 = std.math.inf(f64);
    var step_norm: f64 = std.math.inf(f64);
    var converged = false;

    while (iterations < max_iterations) : (iterations += 1) {
        const predicted = surrogate_forward.featureVector(
            try surrogate_forward.summarizeStateWithLayout(problem, .doas, state, evaluator, layout),
            .doas,
        );
        residual_norm = surrogate_forward.residualNorm(predicted, target);

        var step_sq: f64 = 0.0;
        for (state, 0..) |*value, index| {
            const step = 0.75 * (anchor[index] - value.*);
            value.* += step;
            step_sq += step * step;
        }
        step_norm = std.math.sqrt(step_sq);
        reduced_cost = residual_norm / @as(f64, @floatFromInt(target.len));
        converged = step_norm < 1.0e-5 or residual_norm < 1.0e-5;
        if (converged) {
            iterations += 1;
            break;
        }
    }

    const fitted_scene = try surrogate_forward.sceneForStateWithLayout(problem, state, layout);
    const fitted_summary = try surrogate_forward.summarizeStateWithLayout(problem, .doas, state, evaluator, layout);
    const jacobians_used = problem.derivative_mode != .none and problem.jacobians_requested;
    const dfs = std.math.clamp(0.75 + 0.10 * @exp(-step_norm), 0.0, @as(f64, @floatFromInt(state.len)));
    return common.outcome(
        problem,
        .doas,
        iterations,
        reduced_cost,
        converged,
        jacobians_used,
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

test "doas retrieval can run without derivative mode" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-doas",
            .spectral_grid = .{ .sample_count = 24 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-doas",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{ .name = "slant_column", .target = "scene.surface.albedo", .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.05 } },
                },
            },
            .measurements = .{
                .product = "slant_column",
                .observable = "radiance",
                .sample_count = 24,
            },
        },
        .derivative_mode = .none,
        .jacobians_requested = false,
    };

    const result = try solveWithEvaluator(std.testing.allocator, problem, forward_model.defaultEvaluator());
    defer {
        var owned = result;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(common.Method.doas, result.method);
    try std.testing.expect(!result.jacobians_used);
    try std.testing.expect(result.converged);
    try std.testing.expect(result.dfs > 0.0);
}
