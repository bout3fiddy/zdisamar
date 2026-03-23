//! Purpose:
//!   Provide the DISMAS retrieval entrypoint.
//!
//! Physics:
//!   DISMAS fits the direct radiance/intensity representation of the bound
//!   measurement product.
//!
//! Vendor:
//!   Direct-intensity DISMAS solver stage.
//!
//! Design:
//!   Keep the entrypoint thin and route all method policy through the shared
//!   spectral-fit module.
//!
//! Invariants:
//!   DISMAS requires an observed measurement and a derivative-compatible state
//!   vector.
//!
//! Validation:
//!   DISMAS solver tests exercise the public evaluator path.

const std = @import("std");
const common = @import("../common/contracts.zig");
const forward_model = @import("../common/forward_model.zig");
const spectral_fit = @import("../common/spectral_fit.zig");
const surrogate_forward = @import("../common/surrogate_forward.zig");
const Allocator = std.mem.Allocator;

/// Purpose:
///   Report that the legacy no-evaluator convenience entrypoint is not used
///   by the current adapter surface.
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

/// Purpose:
///   Solve a DISMAS retrieval using the supplied evaluator.
pub fn solveWithEvaluator(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
) common.Error!common.SolverOutcome {
    return spectral_fit.solveMethod(allocator, problem, evaluator, .dismas);
}

test "dismas retrieval fits direct intensity on a spectral product" {
    const product = try surrogate_forward.testEvaluator().evaluateProduct(
        std.testing.allocator,
        surrogate_forward.testEvaluator().context,
        .{
            .id = "scene-dismas-truth",
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 96 },
            .surface = .{ .albedo = 0.18 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.12, .layer_center_km = 4.5, .layer_width_km = 1.3 },
            .observation_model = .{ .instrument = .synthetic, .wavelength_shift_nm = 0.01 },
        },
    );
    defer {
        var owned = product;
        owned.deinit(std.testing.allocator);
    }

    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-dismas",
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 96 },
            .surface = .{ .albedo = 0.12 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.07, .layer_center_km = 4.5, .layer_width_km = 1.3 },
            .observation_model = .{ .instrument = .synthetic },
        },
        .inverse_problem = .{
            .id = "inverse-dismas",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.14, .sigma = 0.06 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 2.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = -0.2, .max = 0.2 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 96,
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
            .sample_count = 96,
            .product = .init(&product),
        },
    };

    const result = try solveWithEvaluator(std.testing.allocator, problem, surrogate_forward.testEvaluator());
    defer {
        var owned = result;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(common.Method.dismas, result.method);
    try std.testing.expect(result.jacobians_used);
    try std.testing.expect(result.jacobian != null);
    try std.testing.expect(result.fit_diagnostics != null);
    try std.testing.expectEqual(common.FitSpace.radiance, result.fit_diagnostics.?.fit_space);
    try std.testing.expect(result.fit_diagnostics.?.selected_rtm_sample_count <= 64);
}
