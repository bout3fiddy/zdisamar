const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const retrieval = @import("zdisamar_internal").retrieval;

const StateParameter = zdisamar.StateParameter;
const oe_sample_count: u32 = 24;
const doas_sample_count: u32 = 12;
const dismas_sample_count: u32 = 128;

const RealEvaluatorContext = struct {
    allocator: std.mem.Allocator,
    plan: *const zdisamar.PreparedPlan,
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
) !internal.kernels.transport.measurement.MeasurementSpaceProduct {
    return evaluateProduct(allocator, context, scene);
}

fn evaluateSummary(
    context_ptr: *const anyopaque,
    scene: zdisamar.Scene,
) anyerror!internal.kernels.transport.measurement.MeasurementSpaceSummary {
    const context: *const RealEvaluatorContext = @ptrCast(@alignCast(context_ptr));
    var measurement = try evaluateProduct(context.allocator, context_ptr, scene);
    defer measurement.deinit(context.allocator);
    return measurement.summary;
}

fn evaluateProduct(
    allocator: std.mem.Allocator,
    context_ptr: *const anyopaque,
    scene: zdisamar.Scene,
) anyerror!internal.kernels.transport.measurement.MeasurementSpaceProduct {
    const context: *const RealEvaluatorContext = @ptrCast(@alignCast(context_ptr));
    var prepared_optics = try context.plan.providers.optics.prepareForScene(allocator, &scene);
    defer prepared_optics.deinit(allocator);
    return internal.kernels.transport.measurement.simulateProduct(
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

fn l2ResidualNorm(lhs: []const f64, rhs: []const f64) f64 {
    var sum_sq: f64 = 0.0;
    for (lhs, rhs) |left, right| {
        const delta = left - right;
        sum_sq += delta * delta;
    }
    return std.math.sqrt(sum_sq);
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
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = oe_sample_count },
            .measurement_count_hint = oe_sample_count,
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
        .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = oe_sample_count },
        .surface = .{ .albedo = 0.16 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.10, .layer_center_km = 3.0, .layer_width_km = 1.0 },
        .observation_model = .{ .instrument = .synthetic, .wavelength_shift_nm = 0.012 },
    });
    defer observed_product.deinit(std.testing.allocator);

    const oe_problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = .{
            .id = "scene-retrieval-integration",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = oe_sample_count },
            .surface = .{ .albedo = 0.08 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.05, .layer_center_km = 3.0, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = .synthetic },
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
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = oe_sample_count,
                .source = .{ .external_observation = .{ .name = "truth_radiance" } },
                .error_model = .{ .from_source_noise = false, .floor = 1.0e-4 },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = oe_sample_count,
            .product = .init(&observed_product),
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
    try std.testing.expectEqual(oe_sample_count, oe_result.jacobian.?.row_count);
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

    const doas_problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = .{
            .id = "scene-retrieval-doas",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = doas_sample_count },
            .surface = .{ .albedo = 0.09 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.06, .layer_center_km = 3.0, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = .synthetic, .noise_model = .shot_noise },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-doas",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 1.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = -0.1, .max = 0.1 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = doas_sample_count,
                .source = .{ .external_observation = .{ .name = "truth_radiance_doas" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-5 },
            },
            .fit_controls = .{ .max_iterations = 4 },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
    };
    var doas_observed_product = try realObservedProduct(std.testing.allocator, &context, .{
        .id = "truth-scene-doas",
        .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = doas_sample_count },
        .surface = .{ .albedo = 0.15 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.10, .layer_center_km = 3.0, .layer_width_km = 1.0 },
        .observation_model = .{ .instrument = .synthetic, .noise_model = .shot_noise, .wavelength_shift_nm = 0.011 },
    });
    defer doas_observed_product.deinit(std.testing.allocator);
    const doas_problem_bound = retrieval.common.contracts.RetrievalProblem{
        .scene = doas_problem.scene,
        .inverse_problem = doas_problem.inverse_problem,
        .derivative_mode = doas_problem.derivative_mode,
        .jacobians_requested = doas_problem.jacobians_requested,
        .observed_measurement = .{
            .source_name = "truth_radiance_doas",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = doas_sample_count,
            .product = .init(&doas_observed_product),
        },
    };
    var doas_observed_measurement = try retrieval.common.forward_model.observedMeasurement(std.testing.allocator, doas_problem_bound);
    defer doas_observed_measurement.deinit(std.testing.allocator);
    const doas_layout = try retrieval.common.state_access.resolveStateLayout(doas_problem_bound);
    const doas_seeded_state = try retrieval.common.state_access.seedStateWithLayout(std.testing.allocator, doas_problem_bound, doas_layout);
    defer std.testing.allocator.free(doas_seeded_state);
    const doas_initial_scene = try retrieval.common.state_access.sceneForStateWithLayout(doas_problem_bound, doas_seeded_state, doas_layout);
    var doas_initial_measurement = try retrieval.common.forward_model.evaluateMeasurement(
        std.testing.allocator,
        doas_problem_bound,
        evaluator,
        doas_initial_scene,
    );
    defer doas_initial_measurement.deinit(std.testing.allocator);
    const doas_initial_residual = try retrieval.common.spectral_fit.fitResidualCost(
        std.testing.allocator,
        .doas,
        doas_observed_measurement,
        doas_initial_measurement,
    );
    const doas_result = try retrieval.doas.solver.solveWithEvaluator(std.testing.allocator, doas_problem_bound, evaluator);
    defer {
        var owned = doas_result;
        owned.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(retrieval.common.contracts.Method.doas, doas_result.method);
    try std.testing.expect(doas_result.jacobians_used);
    try std.testing.expect(doas_result.jacobian != null);
    try std.testing.expect(doas_result.fit_diagnostics != null);
    try std.testing.expectEqual(retrieval.common.contracts.FitSpace.differential_optical_depth, doas_result.fit_diagnostics.?.fit_space);
    var doas_fitted_measurement = try retrieval.common.forward_model.evaluateMeasurement(
        std.testing.allocator,
        doas_problem_bound,
        evaluator,
        doas_result.fitted_scene.?,
    );
    defer doas_fitted_measurement.deinit(std.testing.allocator);
    try std.testing.expect(
        try retrieval.common.spectral_fit.fitResidualCost(
            std.testing.allocator,
            .doas,
            doas_observed_measurement,
            doas_fitted_measurement,
        ) < doas_initial_residual,
    );

    const dismas_problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = .{
            .id = "scene-retrieval-dismas",
            .observation_model = .{
                .instrument = .{ .custom = "compatibility-harness" },
                .regime = .limb,
                .sampling = .synthetic,
                .noise_model = .shot_noise,
            },
            .surface = .{ .albedo = 0.11 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.07, .layer_center_km = 4.0, .layer_width_km = 1.4 },
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = dismas_sample_count },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-dismas",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.12, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.09, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 2.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = -0.2, .max = 0.2 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = dismas_sample_count,
                .source = .{ .external_observation = .{ .name = "truth_radiance_dismas" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-5 },
            },
            .fit_controls = .{ .max_iterations = 4 },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
    };
    var dismas_observed_product = try realObservedProduct(std.testing.allocator, &context, .{
        .id = "truth-scene-dismas",
        .observation_model = .{
            .instrument = .{ .custom = "compatibility-harness" },
            .regime = .limb,
            .sampling = .synthetic,
            .noise_model = .shot_noise,
            .wavelength_shift_nm = 0.014,
        },
        .surface = .{ .albedo = 0.17 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.13, .layer_center_km = 4.0, .layer_width_km = 1.4 },
        .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = dismas_sample_count },
    });
    defer dismas_observed_product.deinit(std.testing.allocator);
    const dismas_problem_bound = retrieval.common.contracts.RetrievalProblem{
        .scene = dismas_problem.scene,
        .inverse_problem = dismas_problem.inverse_problem,
        .derivative_mode = dismas_problem.derivative_mode,
        .jacobians_requested = dismas_problem.jacobians_requested,
        .observed_measurement = .{
            .source_name = "truth_radiance_dismas",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = dismas_sample_count,
            .product = .init(&dismas_observed_product),
        },
    };
    var dismas_observed_measurement = try retrieval.common.forward_model.observedMeasurement(std.testing.allocator, dismas_problem_bound);
    defer dismas_observed_measurement.deinit(std.testing.allocator);
    const dismas_layout = try retrieval.common.state_access.resolveStateLayout(dismas_problem_bound);
    const dismas_seeded_state = try retrieval.common.state_access.seedStateWithLayout(std.testing.allocator, dismas_problem_bound, dismas_layout);
    defer std.testing.allocator.free(dismas_seeded_state);
    const dismas_initial_scene = try retrieval.common.state_access.sceneForStateWithLayout(dismas_problem_bound, dismas_seeded_state, dismas_layout);
    var dismas_initial_measurement = try retrieval.common.forward_model.evaluateMeasurement(
        std.testing.allocator,
        dismas_problem_bound,
        evaluator,
        dismas_initial_scene,
    );
    defer dismas_initial_measurement.deinit(std.testing.allocator);
    const dismas_initial_residual = try retrieval.common.spectral_fit.fitResidualCost(
        std.testing.allocator,
        .dismas,
        dismas_observed_measurement,
        dismas_initial_measurement,
    );
    const dismas_result = try retrieval.dismas.solver.solveWithEvaluator(std.testing.allocator, dismas_problem_bound, evaluator);
    defer {
        var owned = dismas_result;
        owned.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(retrieval.common.contracts.Method.dismas, dismas_result.method);
    try std.testing.expect(dismas_result.jacobians_used);
    try std.testing.expect(dismas_result.jacobian != null);
    try std.testing.expect(dismas_result.fit_diagnostics != null);
    try std.testing.expectEqual(retrieval.common.contracts.FitSpace.radiance, dismas_result.fit_diagnostics.?.fit_space);
    try std.testing.expect(dismas_result.fit_diagnostics.?.selected_rtm_sample_count <= 64);
    try std.testing.expect(dismas_result.fit_diagnostics.?.selected_rtm_sample_count < dismas_sample_count);
    try std.testing.expect(dismas_result.fit_diagnostics.?.selection_zero_crossing_count > 0);
    var dismas_fitted_measurement = try retrieval.common.forward_model.evaluateMeasurement(
        std.testing.allocator,
        dismas_problem_bound,
        evaluator,
        dismas_result.fitted_scene.?,
    );
    defer dismas_fitted_measurement.deinit(std.testing.allocator);
    try std.testing.expect(
        try retrieval.common.spectral_fit.fitResidualCost(
            std.testing.allocator,
            .dismas,
            dismas_observed_measurement,
            dismas_fitted_measurement,
        ) < dismas_initial_residual,
    );
}
