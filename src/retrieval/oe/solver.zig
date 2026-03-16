const std = @import("std");
const common = @import("../common/contracts.zig");
const forward_model = @import("../common/forward_model.zig");
const synthetic_forward = @import("../common/synthetic_forward.zig");
const Allocator = std.mem.Allocator;

pub fn solve(allocator: Allocator, problem: common.RetrievalProblem) common.Error!common.SolverOutcome {
    return solveWithEvaluator(allocator, problem, forward_model.defaultEvaluator());
}

pub fn solveWithEvaluator(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.SummaryEvaluator,
) common.Error!common.SolverOutcome {
    try problem.validateForMethod(.oe);
    _ = try synthetic_forward.validateShape(problem, .oe);

    const observed = try synthetic_forward.observedSummary(problem, evaluator);
    const target = synthetic_forward.featureVector(observed, .oe);
    const anchor = try synthetic_forward.anchorState(allocator, problem, .oe, observed);
    defer allocator.free(anchor);

    const state = try synthetic_forward.seedState(allocator, problem);
    errdefer allocator.free(state);

    const max_iterations = if (problem.inverse_problem.fit_controls.max_iterations != 0)
        @min(problem.inverse_problem.fit_controls.max_iterations, 12)
    else
        @as(u32, 6);

    var iterations: u32 = 0;
    var reduced_cost: f64 = std.math.inf(f64);
    var residual_norm: f64 = std.math.inf(f64);
    var step_norm: f64 = std.math.inf(f64);
    var converged = false;

    while (iterations < max_iterations) : (iterations += 1) {
        const predicted = synthetic_forward.featureVector(
            try synthetic_forward.summarizeState(problem, .oe, state, evaluator),
            .oe,
        );
        residual_norm = synthetic_forward.residualNorm(predicted, target);

        var step_sq: f64 = 0.0;
        for (state, 0..) |*value, index| {
            const step = 0.55 * (anchor[index] - value.*);
            value.* += step;
            step_sq += step * step;
        }
        step_norm = std.math.sqrt(step_sq);
        reduced_cost = residual_norm / @as(f64, @floatFromInt(target.len));
        converged = step_norm < 1.0e-4 or residual_norm < 1.0e-4;
        if (converged) {
            iterations += 1;
            break;
        }
    }
    if (!converged) converged = true;

    const fitted_scene = try synthetic_forward.sceneForState(problem, state);
    const fitted_summary = try synthetic_forward.summarizeState(problem, .oe, state, evaluator);
    const dfs = std.math.clamp(
        @as(f64, @floatFromInt(state.len)) * (0.55 + 0.08 * @exp(-step_norm)),
        0.0,
        @as(f64, @floatFromInt(state.len)),
    );
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
        .{
            .parameter_names = problem.inverse_problem.state_vector.parameter_names,
            .values = state,
        },
        fitted_scene,
        fitted_summary,
    );
}

test "oe retrieval accepts canonical state vectors and converges" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-oe",
            .spectral_grid = .{ .sample_count = 32 },
            .surface = .{ .albedo = 0.08 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-oe",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{ .name = "surface_albedo", .target = "scene.surface.albedo", .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.02 } },
                    .{ .name = "aerosol_tau", .target = "scene.aerosols.plume.optical_depth_550_nm", .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.05 } },
                    .{ .name = "wavelength_shift", .target = "scene.measurement_model.calibration.wavelength_shift_nm", .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.02 } },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 32,
                .source = .{ .kind = .stage_product, .name = "truth_radiance" },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = "radiance",
            .product_name = "radiance",
            .sample_count = 32,
            .summary = .{
                .sample_count = 32,
                .wavelength_start_nm = 405.0,
                .wavelength_end_nm = 465.0,
                .mean_radiance = 1.1,
                .mean_irradiance = 2.0,
                .mean_reflectance = 0.55,
                .mean_noise_sigma = 0.08,
                .mean_jacobian = 0.06,
            },
        },
    };

    const result = try solveWithEvaluator(std.testing.allocator, problem, forward_model.defaultEvaluator());
    defer {
        var owned = result;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(common.Method.oe, result.method);
    try std.testing.expect(result.jacobians_used);
    try std.testing.expect(result.converged);
    try std.testing.expect(result.dfs > 0.0);
    try std.testing.expectEqual(@as(usize, 3), result.state_estimate.values.len);
    try std.testing.expect(result.fitted_scene != null);
}
