const std = @import("std");
const common = @import("../common/contracts.zig");
const covariance = @import("../common/covariance.zig");
const diagnostics = @import("../common/diagnostics.zig");
const forward_model = @import("../common/forward_model.zig");
const synthetic_forward = @import("../common/synthetic_forward.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const MeasurementSpaceSummary = @import("../../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;
const noise = @import("../../kernels/spectra/noise.zig");

pub fn solve(problem: common.RetrievalProblem) common.Error!common.SolverOutcome {
    return solveWithEvaluator(problem, forward_model.defaultEvaluator());
}

pub fn solveWithEvaluator(problem: common.RetrievalProblem, evaluator: forward_model.SummaryEvaluator) common.Error!common.SolverOutcome {
    try problem.validateForMethod(.doas);
    _ = try synthetic_forward.validateShape(problem, .doas);

    var state = [_]f64{0.0};
    synthetic_forward.seedState(.doas, state[0..]);
    var target_state = [_]f64{0.0};
    synthetic_forward.targetState(problem, .doas, target_state[0..]);
    const target = synthetic_forward.featureVector(
        try synthetic_forward.summarizeState(problem, .doas, target_state[0..], evaluator),
        .doas,
    );

    var iterations: u32 = 0;
    var reduced_cost: f64 = std.math.inf(f64);
    var residual_norm: f64 = std.math.inf(f64);
    var step_norm: f64 = std.math.inf(f64);
    var converged = false;

    while (iterations < 5) : (iterations += 1) {
        const predicted = synthetic_forward.featureVector(
            try synthetic_forward.summarizeState(problem, .doas, state[0..], evaluator),
            .doas,
        );
        const residual = [_]f64{
            target.values[0] - predicted.values[0],
            target.values[1] - predicted.values[1],
        };

        const signal = [_]f64{
            @max(@abs(target.values[0]) * 200.0, 25.0),
            @max(@abs(target.values[1]) * 400.0, 25.0),
        };
        var sigma: [2]f64 = undefined;
        try noise.shotNoiseStd(&signal, 2.0, &sigma);
        var whitened: [2]f64 = undefined;
        const covariance_model: covariance.DiagonalCovariance = .{ .variances = &sigma };
        try covariance_model.whiten(&residual, &whitened);

        var perturbed = state;
        perturbed[0] += 1e-3;
        const perturbed_features = synthetic_forward.featureVector(
            try synthetic_forward.summarizeState(problem, .doas, perturbed[0..], evaluator),
            .doas,
        );
        const jacobian = [2]f64{
            (perturbed_features.values[0] - predicted.values[0]) / 1e-3,
            (perturbed_features.values[1] - predicted.values[1]) / 1e-3,
        };

        const denom = jacobian[0] * jacobian[0] / (sigma[0] * sigma[0]) +
            jacobian[1] * jacobian[1] / (sigma[1] * sigma[1]) +
            1.0 / (0.08 * 0.08);
        if (@abs(denom) < 1e-12) return common.Error.SingularMatrix;

        const numer = jacobian[0] * residual[0] / (sigma[0] * sigma[0]) +
            jacobian[1] * residual[1] / (sigma[1] * sigma[1]) -
            (state[0] - 0.10) / (0.08 * 0.08);
        const step = numer / denom;
        state[0] += 0.8 * step;

        residual_norm = synthetic_forward.residualNorm(predicted, target);
        step_norm = @abs(step);
        const summary = diagnostics.assess(
            whitened[0] * whitened[0] + whitened[1] * whitened[1],
            step_norm,
            problem.inverse_problem.measurements.sample_count,
        );
        reduced_cost = summary.reduced_chi_square;
        converged = step_norm < 1e-4 or summary.converged;
        if (converged) {
            iterations += 1;
            break;
        }
    }

    const jacobians_used = problem.derivative_mode != .none and problem.jacobians_requested;
    const dfs = std.math.clamp(0.85 + 0.10 * @exp(-step_norm), 0.0, 1.0);
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
    );
}

test "doas retrieval can run without derivative mode" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-doas",
            .spectral_grid = .{ .sample_count = 24 },
        },
        .inverse_problem = .{
            .id = "inverse-doas",
            .state_vector = .{
                .parameter_names = &[_][]const u8{"slant_column"},
                .value_count = 1,
            },
            .measurements = .{
                .product = "slant_column",
                .sample_count = 24,
            },
        },
        .derivative_mode = .none,
        .jacobians_requested = false,
    };

    const evaluator: forward_model.SummaryEvaluator = .{
        .context = undefined,
        .evaluate = struct {
            fn evaluate(_: *const anyopaque, scene: Scene) anyerror!MeasurementSpaceSummary {
                return .{
                    .sample_count = scene.spectral_grid.sample_count,
                    .wavelength_start_nm = 405.0,
                    .wavelength_end_nm = 465.0,
                    .mean_radiance = 0.9,
                    .mean_irradiance = 2.1,
                    .mean_reflectance = 0.45,
                    .mean_noise_sigma = 0.06,
                    .mean_jacobian = 0.0,
                };
            }
        }.evaluate,
    };
    const result = try solveWithEvaluator(problem, evaluator);
    try std.testing.expectEqual(common.Method.doas, result.method);
    try std.testing.expect(!result.jacobians_used);
    try std.testing.expect(result.converged);
    try std.testing.expect(result.dfs > 0.0);
}
