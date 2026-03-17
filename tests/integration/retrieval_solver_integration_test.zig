const std = @import("std");
const zdisamar = @import("zdisamar");
const retrieval = @import("retrieval");

const StateParameter = zdisamar.StateParameter;

const RealEvaluatorContext = struct {
    allocator: std.mem.Allocator,
    plan: *const zdisamar.Plan,
};

fn realEvaluator(context: *const RealEvaluatorContext) retrieval.common.forward_model.Evaluator {
    return .{
        .context = context,
        .evaluateSummary = evaluateSummary,
        .evaluateProduct = evaluateProduct,
    };
}

fn realObservedProduct(
    allocator: std.mem.Allocator,
    context: *const RealEvaluatorContext,
    scene: zdisamar.Scene,
) !zdisamar.transport.measurement_space.MeasurementSpaceProduct {
    return evaluateProduct(allocator, context, scene);
}

fn evaluateSummary(
    context_ptr: *const anyopaque,
    scene: zdisamar.Scene,
) anyerror!zdisamar.transport.measurement_space.MeasurementSpaceSummary {
    const context: *const RealEvaluatorContext = @ptrCast(@alignCast(context_ptr));
    var measurement = try evaluateProduct(context.allocator, context_ptr, scene);
    defer measurement.deinit(context.allocator);
    return measurement.summary;
}

fn evaluateProduct(
    allocator: std.mem.Allocator,
    context_ptr: *const anyopaque,
    scene: zdisamar.Scene,
) anyerror!zdisamar.transport.measurement_space.MeasurementSpaceProduct {
    const context: *const RealEvaluatorContext = @ptrCast(@alignCast(context_ptr));
    var prepared_optics = try context.plan.providers.optics.prepareForScene(allocator, &scene);
    defer prepared_optics.deinit(allocator);
    return zdisamar.transport.measurement_space.simulateProduct(
        allocator,
        &scene,
        context.plan.transport_route,
        &prepared_optics,
        .{
            .transport = context.plan.providers.transport,
            .surface = context.plan.providers.surface,
            .instrument = context.plan.providers.instrument,
            .noise = context.plan.providers.noise,
        },
    );
}

test "retrieval solvers share canonical problem model with oe spectral products and surrogate method policy" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{ .retrieval_algorithm = "builtin.oe_solver" },
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .semi_analytical,
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 48 },
            .measurement_count_hint = 48,
        },
    });
    defer plan.deinit();

    const context: RealEvaluatorContext = .{
        .allocator = std.testing.allocator,
        .plan = &plan,
    };
    const evaluator = realEvaluator(&context);

    var observed_product = try realObservedProduct(std.testing.allocator, &context, .{
        .id = "truth-scene-oe",
        .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 48 },
        .surface = .{ .albedo = 0.16 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.10, .layer_center_km = 3.0, .layer_width_km = 1.0 },
        .observation_model = .{ .instrument = "synthetic", .wavelength_shift_nm = 0.012 },
    });
    defer observed_product.deinit(std.testing.allocator);

    const oe_problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = .{
            .id = "scene-retrieval-integration",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 48 },
            .surface = .{ .albedo = 0.08 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.05, .layer_center_km = 3.0, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-integration",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 3.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = -0.2, .max = 0.2 } },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 48,
                .source = .{ .kind = .external_observation, .name = "truth_radiance" },
                .error_model = .{ .from_source_noise = false, .floor = 1.0e-4 },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = "radiance",
            .product_name = "radiance",
            .sample_count = 48,
            .product = &observed_product,
        },
    };

    const oe_result = try retrieval.oe.solver.solveWithEvaluator(std.testing.allocator, oe_problem, evaluator);
    defer {
        var owned = oe_result;
        owned.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(retrieval.common.contracts.Method.oe, oe_result.method);
    try std.testing.expect(oe_result.jacobians_used);
    try std.testing.expect(oe_result.fitted_measurement != null);
    try std.testing.expect(oe_result.jacobian != null);
    try std.testing.expect(oe_result.averaging_kernel != null);
    try std.testing.expect(oe_result.posterior_covariance != null);
    try std.testing.expect(oe_result.dfs > 0.0);
    try std.testing.expectEqual(@as(u32, 48), oe_result.jacobian.?.row_count);
    try std.testing.expectEqual(@as(u32, 3), oe_result.jacobian.?.column_count);
    try std.testing.expect(oe_result.fitted_scene != null);

    var fitted_product = try realObservedProduct(std.testing.allocator, &context, oe_result.fitted_scene.?);
    defer fitted_product.deinit(std.testing.allocator);
    try std.testing.expect(fitted_product.jacobian != null);
    const state_count = @as(usize, @intCast(oe_result.jacobian.?.column_count));
    const aerosol_tau = oe_result.state_estimate.values[1];
    for (fitted_product.jacobian.?, 0..) |expected, row| {
        const routed_column = oe_result.jacobian.?.values[row * state_count + 1];
        try std.testing.expectApproxEqAbs(expected * aerosol_tau, routed_column, 1.0e-9);
    }

    const surrogate_evaluator = retrieval.common.surrogate_forward.testEvaluator();

    const doas_problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = .{
            .id = "scene-retrieval-doas",
            .spectral_grid = .{ .sample_count = 40 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-doas",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "slant_column", .target = .surface_albedo, .prior = .{ .enabled = true, .mean = 0.12, .sigma = 0.05 } },
                },
            },
            .measurements = .{
                .product = "slant_column",
                .observable = "radiance",
                .sample_count = 40,
            },
        },
        .derivative_mode = .none,
        .jacobians_requested = false,
    };
    const doas_result = try retrieval.doas.solver.solveWithEvaluator(std.testing.allocator, doas_problem, surrogate_evaluator);
    defer {
        var owned = doas_result;
        owned.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(retrieval.common.contracts.Method.doas, doas_result.method);
    try std.testing.expect(!doas_result.jacobians_used);
    try std.testing.expect(doas_result.jacobian == null);

    const dismas_problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = .{
            .id = "scene-retrieval-dismas",
            .observation_model = .{
                .instrument = "compatibility-harness",
                .regime = .limb,
                .sampling = .synthetic,
                .noise_model = .shot_noise,
            },
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 40 },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-dismas",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "state_a", .target = .surface_albedo, .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.04 } },
                    .{ .name = "state_b", .target = .aerosol_optical_depth_550_nm, .prior = .{ .enabled = true, .mean = 0.12, .sigma = 0.05 } },
                    .{ .name = "state_c", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.05 } },
                },
            },
            .measurements = .{
                .product = "multi_band_signal",
                .observable = "radiance",
                .sample_count = 40,
            },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
    };
    const dismas_result = try retrieval.dismas.solver.solveWithEvaluator(std.testing.allocator, dismas_problem, surrogate_evaluator);
    defer {
        var owned = dismas_result;
        owned.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(retrieval.common.contracts.Method.dismas, dismas_result.method);
    try std.testing.expect(dismas_result.jacobians_used);
    try std.testing.expect(dismas_result.jacobian == null);
}
