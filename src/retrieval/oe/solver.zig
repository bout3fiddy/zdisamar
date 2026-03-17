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
    try problem.validateForMethod(.oe);
    const layout = try surrogate_forward.resolveStateLayout(problem);

    const observed = try surrogate_forward.observedSummary(problem, evaluator);
    const target = surrogate_forward.featureVector(observed, .oe);
    const anchor = try surrogate_forward.anchorStateWithLayout(allocator, problem, .oe, observed, layout);
    defer allocator.free(anchor);

    const state = try surrogate_forward.seedStateWithLayout(allocator, problem, layout);
    errdefer allocator.free(state);

    const max_iterations = if (problem.inverse_problem.fit_controls.max_iterations != 0)
        @min(problem.inverse_problem.fit_controls.max_iterations, 16)
    else
        @as(u32, 12);

    var iterations: u32 = 0;
    var reduced_cost: f64 = std.math.inf(f64);
    var residual_norm: f64 = std.math.inf(f64);
    var step_norm: f64 = std.math.inf(f64);
    var converged = false;

    while (iterations < max_iterations) : (iterations += 1) {
        const predicted = surrogate_forward.featureVector(
            try surrogate_forward.summarizeStateWithLayout(problem, .oe, state, evaluator, layout),
            .oe,
        );
        residual_norm = surrogate_forward.residualNorm(predicted, target);

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

    const fitted_scene = try surrogate_forward.sceneForStateWithLayout(problem, state, layout);
    const fitted_summary = try surrogate_forward.summarizeStateWithLayout(problem, .oe, state, evaluator, layout);
    const dfs = std.math.clamp(
        @as(f64, @floatFromInt(state.len)) * (0.55 + 0.08 * @exp(-step_norm)),
        0.0,
        @as(f64, @floatFromInt(state.len)),
    );
    return try common.outcome(
        allocator,
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

test "oe retrieval reports non-converged when the iteration budget is exhausted" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-oe-not-converged",
            .spectral_grid = .{ .sample_count = 32 },
            .surface = .{ .albedo = 0.02 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-oe-not-converged",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{ .name = "surface_albedo", .target = "scene.surface.albedo", .prior = .{ .enabled = true, .mean = 0.02, .sigma = 0.01 } },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 32,
                .source = .{ .kind = .stage_product, .name = "truth_radiance" },
            },
            .fit_controls = .{
                .max_iterations = 1,
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
                .mean_radiance = 4.0,
                .mean_irradiance = 2.0,
                .mean_reflectance = 0.95,
                .mean_noise_sigma = 0.10,
                .mean_jacobian = -0.04,
            },
        },
    };

    const result = try solveWithEvaluator(std.testing.allocator, problem, forward_model.defaultEvaluator());
    defer {
        var owned = result;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(!result.converged);
    try std.testing.expectEqual(@as(u32, 1), result.iterations);
}
