const std = @import("std");
const common = @import("../common/contracts.zig");
const diagnostics = @import("../common/diagnostics.zig");
const synthetic_forward = @import("../common/synthetic_forward.zig");
const zdisamar = @import("zdisamar");
const small_dense = zdisamar.linalg.small_dense;

pub fn solve(problem: common.RetrievalProblem) common.Error!common.SolverOutcome {
    try problem.validateForMethod(.dismas);
    _ = try synthetic_forward.validateShape(problem, .dismas);

    var prior_state = [_]f64{ 0.0, 0.0, 0.0 };
    synthetic_forward.seedState(.dismas, prior_state[0..]);
    var target_state = [_]f64{ 0.0, 0.0, 0.0 };
    synthetic_forward.targetState(problem, .dismas, target_state[0..]);
    const target = synthetic_forward.featureVector(
        try synthetic_forward.summarizeState(problem, .dismas, target_state[0..]),
        .dismas,
    );

    var state = prior_state;
    var iterations: u32 = 0;
    var reduced_cost: f64 = std.math.inf(f64);
    var residual_norm: f64 = std.math.inf(f64);
    var step_norm: f64 = std.math.inf(f64);
    var converged = false;

    while (iterations < 7) : (iterations += 1) {
        const predicted = synthetic_forward.featureVector(
            try synthetic_forward.summarizeState(problem, .dismas, state[0..]),
            .dismas,
        );
        const residual = [3]f64{
            target.values[0] - predicted.values[0],
            target.values[1] - predicted.values[1],
            target.values[2] - predicted.values[2],
        };

        var jacobian: [3][3]f64 = undefined;
        for (0..3) |column| {
            var perturbed = state;
            perturbed[column] += 1e-3;
            const perturbed_features = synthetic_forward.featureVector(
                try synthetic_forward.summarizeState(problem, .dismas, perturbed[0..]),
                .dismas,
            );
            for (0..3) |row| {
                jacobian[row][column] = (perturbed_features.values[row] - predicted.values[row]) / 1e-3;
            }
        }

        const damping = 0.25;
        const normal = [3][3]f64{
            .{
                jacobian[0][0] * jacobian[0][0] + jacobian[1][0] * jacobian[1][0] + jacobian[2][0] * jacobian[2][0] + damping,
                jacobian[0][0] * jacobian[0][1] + jacobian[1][0] * jacobian[1][1] + jacobian[2][0] * jacobian[2][1],
                jacobian[0][0] * jacobian[0][2] + jacobian[1][0] * jacobian[1][2] + jacobian[2][0] * jacobian[2][2],
            },
            .{
                jacobian[0][1] * jacobian[0][0] + jacobian[1][1] * jacobian[1][0] + jacobian[2][1] * jacobian[2][0],
                jacobian[0][1] * jacobian[0][1] + jacobian[1][1] * jacobian[1][1] + jacobian[2][1] * jacobian[2][1] + damping,
                jacobian[0][1] * jacobian[0][2] + jacobian[1][1] * jacobian[1][2] + jacobian[2][1] * jacobian[2][2],
            },
            .{
                jacobian[0][2] * jacobian[0][0] + jacobian[1][2] * jacobian[1][0] + jacobian[2][2] * jacobian[2][0],
                jacobian[0][2] * jacobian[0][1] + jacobian[1][2] * jacobian[1][1] + jacobian[2][2] * jacobian[2][1],
                jacobian[0][2] * jacobian[0][2] + jacobian[1][2] * jacobian[1][2] + jacobian[2][2] * jacobian[2][2] + damping,
            },
        };
        const gradient = [3]f64{
            jacobian[0][0] * residual[0] + jacobian[1][0] * residual[1] + jacobian[2][0] * residual[2] - 0.5 * (state[0] - prior_state[0]),
            jacobian[0][1] * residual[0] + jacobian[1][1] * residual[1] + jacobian[2][1] * residual[2] - 0.5 * (state[1] - prior_state[1]),
            jacobian[0][2] * residual[0] + jacobian[1][2] * residual[1] + jacobian[2][2] * residual[2] - 0.5 * (state[2] - prior_state[2]),
        };

        const step = try small_dense.solve3x3(normal, gradient);
        for (0..3) |index| state[index] += 0.7 * step[index];

        residual_norm = synthetic_forward.residualNorm(predicted, target);
        step_norm = std.math.sqrt(step[0] * step[0] + step[1] * step[1] + step[2] * step[2]);
        const summary = diagnostics.assess(
            residual[0] * residual[0] + residual[1] * residual[1] + residual[2] * residual[2],
            step_norm,
            problem.inverse_problem.measurements.sample_count,
        );
        reduced_cost = summary.reduced_chi_square;
        converged = step_norm < 5e-3 or summary.converged;
        if (converged) {
            iterations += 1;
            break;
        }
    }

    const dfs = std.math.clamp(2.4 + 0.3 * @exp(-step_norm), 0.0, 3.0);
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
    );
}

test "dismas retrieval requires explicit derivative mode" {
    const base_problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-dismas",
            .spectral_grid = .{ .sample_count = 20 },
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

    const ok = try solve(base_problem);
    try std.testing.expectEqual(common.Method.dismas, ok.method);
    try std.testing.expect(ok.jacobians_used);
    try std.testing.expect(ok.dfs > 0.0);

    var missing_mode = base_problem;
    missing_mode.derivative_mode = .none;
    try std.testing.expectError(common.Error.DerivativeModeRequired, solve(missing_mode));
}
