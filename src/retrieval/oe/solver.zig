const std = @import("std");
const common = @import("../common/contracts.zig");
const covariance = @import("../common/covariance.zig");
const diagnostics = @import("../common/diagnostics.zig");
const forward_model = @import("../common/forward_model.zig");
const priors = @import("../common/priors.zig");
const synthetic_forward = @import("../common/synthetic_forward.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const MeasurementSpaceSummary = @import("../../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;
const small_dense = @import("../../kernels/linalg/small_dense.zig");

pub fn solve(problem: common.RetrievalProblem) common.Error!common.SolverOutcome {
    return solveWithEvaluator(problem, forward_model.defaultEvaluator());
}

pub fn solveWithEvaluator(problem: common.RetrievalProblem, evaluator: forward_model.SummaryEvaluator) common.Error!common.SolverOutcome {
    try problem.validateForMethod(.oe);
    _ = try synthetic_forward.validateShape(problem, .oe);

    var prior_state = [_]f64{ 0.0, 0.0 };
    synthetic_forward.seedState(.oe, prior_state[0..]);
    var target_state = [_]f64{ 0.0, 0.0 };
    synthetic_forward.targetState(problem, .oe, target_state[0..]);
    const target = synthetic_forward.featureVector(
        try synthetic_forward.summarizeState(problem, .oe, target_state[0..], evaluator),
        .oe,
    );

    var state = prior_state;
    var iterations: u32 = 0;
    var reduced_cost: f64 = std.math.inf(f64);
    var residual_norm: f64 = std.math.inf(f64);
    var step_norm: f64 = std.math.inf(f64);
    var converged = false;

    while (iterations < 6) : (iterations += 1) {
        const predicted = synthetic_forward.featureVector(
            try synthetic_forward.summarizeState(problem, .oe, state[0..], evaluator),
            .oe,
        );
        const residual = [2]f64{
            target.values[0] - predicted.values[0],
            target.values[1] - predicted.values[1],
        };

        const sigma = [_]f64{
            @max(0.05 * @abs(target.values[0]), 1e-4),
            @max(0.05 * @abs(target.values[1]), 1e-4),
        };
        var whitened: [2]f64 = undefined;
        const covariance_model: covariance.DiagonalCovariance = .{ .variances = &[_]f64{
            sigma[0] * sigma[0],
            sigma[1] * sigma[1],
        } };
        try covariance_model.whiten(&residual, &whitened);

        var jacobian: [2][2]f64 = undefined;
        for (0..2) |column| {
            var perturbed = state;
            perturbed[column] += 1e-3;
            const perturbed_features = synthetic_forward.featureVector(
                try synthetic_forward.summarizeState(problem, .oe, perturbed[0..], evaluator),
                .oe,
            );
            jacobian[0][column] = (perturbed_features.values[0] - predicted.values[0]) / 1e-3;
            jacobian[1][column] = (perturbed_features.values[1] - predicted.values[1]) / 1e-3;
        }

        const prior_residual = [2]f64{
            (priors.GaussianPrior{ .mean = prior_state[0], .variance = 0.05 * 0.05 }).residual(state[0]),
            (priors.GaussianPrior{ .mean = prior_state[1], .variance = 0.05 * 0.05 }).residual(state[1]),
        };

        const h00 = jacobian[0][0] * jacobian[0][0] / (sigma[0] * sigma[0]) +
            jacobian[1][0] * jacobian[1][0] / (sigma[1] * sigma[1]) +
            1.0 / (0.05 * 0.05);
        const h01 = jacobian[0][0] * jacobian[0][1] / (sigma[0] * sigma[0]) +
            jacobian[1][0] * jacobian[1][1] / (sigma[1] * sigma[1]);
        const h11 = jacobian[0][1] * jacobian[0][1] / (sigma[0] * sigma[0]) +
            jacobian[1][1] * jacobian[1][1] / (sigma[1] * sigma[1]) +
            1.0 / (0.05 * 0.05);

        const gradient = [2]f64{
            jacobian[0][0] * residual[0] / (sigma[0] * sigma[0]) +
                jacobian[1][0] * residual[1] / (sigma[1] * sigma[1]) -
                prior_residual[0] / 0.05,
            jacobian[0][1] * residual[0] / (sigma[0] * sigma[0]) +
                jacobian[1][1] * residual[1] / (sigma[1] * sigma[1]) -
                prior_residual[1] / 0.05,
        };

        const step = try small_dense.solve2x2(.{
            .{ h00, h01 },
            .{ h01, h11 },
        }, gradient);
        state[0] += 0.75 * step[0];
        state[1] += 0.75 * step[1];

        residual_norm = synthetic_forward.residualNorm(predicted, target);
        step_norm = std.math.sqrt(step[0] * step[0] + step[1] * step[1]);
        const summary = diagnostics.assess(
            whitened[0] * whitened[0] + whitened[1] * whitened[1],
            step_norm,
            problem.inverse_problem.measurements.sample_count,
        );
        reduced_cost = summary.reduced_chi_square;
        converged = step_norm < 1e-3 or summary.converged;
        if (converged) {
            iterations += 1;
            break;
        }
    }

    const dfs = std.math.clamp(2.0 - 0.25 * @min(step_norm, 4.0), 0.0, 2.0);
    return common.outcome(
        problem,
        .oe,
        iterations,
        reduced_cost,
        converged,
        true,
        dfs,
        residual_norm,
        step_norm,
    );
}

test "oe retrieval requires derivative mode and converges with jacobians" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-oe",
            .spectral_grid = .{ .sample_count = 32 },
        },
        .inverse_problem = .{
            .id = "inverse-oe",
            .state_vector = .{
                .parameter_names = &[_][]const u8{ "albedo", "aerosol" },
                .value_count = 2,
            },
            .measurements = .{
                .product = "radiance",
                .sample_count = 32,
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
    };

    const evaluator: forward_model.SummaryEvaluator = .{
        .context = undefined,
        .evaluate = struct {
            fn evaluate(_: *const anyopaque, scene: Scene) anyerror!MeasurementSpaceSummary {
                return .{
                    .sample_count = scene.spectral_grid.sample_count,
                    .wavelength_start_nm = 405.0,
                    .wavelength_end_nm = 465.0,
                    .mean_radiance = 1.1,
                    .mean_irradiance = 2.0,
                    .mean_reflectance = 0.55,
                    .mean_noise_sigma = 0.08,
                    .mean_jacobian = 0.06,
                };
            }
        }.evaluate,
    };
    const result = try solveWithEvaluator(problem, evaluator);
    try std.testing.expectEqual(common.Method.oe, result.method);
    try std.testing.expect(result.jacobians_used);
    try std.testing.expect(result.converged);
    try std.testing.expect(result.dfs > 0.0);
}
