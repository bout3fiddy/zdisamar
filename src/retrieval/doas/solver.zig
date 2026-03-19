const std = @import("std");
const common = @import("../common/contracts.zig");
const forward_model = @import("../common/forward_model.zig");
const spectral_fit = @import("../common/spectral_fit.zig");
const surrogate_forward = @import("../common/surrogate_forward.zig");
const Allocator = std.mem.Allocator;

pub fn solve(allocator: Allocator, problem: common.RetrievalProblem) common.Error!common.SolverOutcome {
    _ = allocator;
    _ = problem;
    return common.Error.InvalidRequest;
}

pub fn solveWithTestEvaluator(
    allocator: Allocator,
    problem: common.RetrievalProblem,
) common.Error!common.SolverOutcome {
    return solveWithEvaluator(allocator, problem, surrogate_forward.testEvaluator());
}

pub fn solveWithEvaluator(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
) common.Error!common.SolverOutcome {
    return spectral_fit.solveMethod(allocator, problem, evaluator, .doas);
}

test "doas retrieval requires an observed spectrum and reports differential fit metadata" {
    const product = try surrogate_forward.testEvaluator().evaluateProduct(
        std.testing.allocator,
        surrogate_forward.testEvaluator().context,
        .{
            .id = "scene-doas-truth",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 32 },
            .surface = .{ .albedo = 0.13 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.08, .layer_center_km = 2.8, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = .synthetic, .wavelength_shift_nm = 0.008 },
        },
    );
    defer {
        var owned = product;
        owned.deinit(std.testing.allocator);
    }

    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-doas",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 32 },
            .surface = .{ .albedo = 0.08 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.05, .layer_center_km = 2.8, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = .synthetic },
        },
        .inverse_problem = .{
            .id = "inverse-doas",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.07, .sigma = 0.03 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 1.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.03 }, .bounds = .{ .enabled = true, .min = -0.1, .max = 0.1 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 32,
                .source = .{ .external_observation = .{ .name = "truth" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-5 },
            },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = 32,
            .product = .init(&product),
        },
    };

    const result = try solveWithEvaluator(std.testing.allocator, problem, surrogate_forward.testEvaluator());
    defer {
        var owned = result;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(common.Method.doas, result.method);
    try std.testing.expect(result.jacobians_used);
    try std.testing.expect(result.jacobian != null);
    try std.testing.expect(result.fit_diagnostics != null);
    try std.testing.expectEqual(common.FitSpace.differential_optical_depth, result.fit_diagnostics.?.fit_space);
    try std.testing.expect(result.fit_diagnostics.?.polynomial_order > 0);
}
