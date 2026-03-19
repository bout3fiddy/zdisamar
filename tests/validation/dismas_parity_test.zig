const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const retrieval = @import("zdisamar_internal").retrieval;

const StateParameter = zdisamar.StateParameter;
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

fn evaluateSummary(
    context_ptr: *const anyopaque,
    scene: zdisamar.Scene,
) anyerror!internal.kernels.transport.measurement_space.MeasurementSpaceSummary {
    const context: *const RealEvaluatorContext = @ptrCast(@alignCast(context_ptr));
    var product = try evaluateProduct(context.allocator, context_ptr, scene);
    defer product.deinit(context.allocator);
    return product.summary;
}

fn evaluateProduct(
    allocator: std.mem.Allocator,
    context_ptr: *const anyopaque,
    scene: zdisamar.Scene,
) anyerror!internal.kernels.transport.measurement_space.MeasurementSpaceProduct {
    const context: *const RealEvaluatorContext = @ptrCast(@alignCast(context_ptr));
    var prepared_optics = try context.plan.providers.optics.prepareForScene(allocator, &scene);
    defer prepared_optics.deinit(allocator);
    return internal.kernels.transport.measurement_space.simulateProduct(
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

test "dismas validation performs a direct-intensity fit on real spectra" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{ .retrieval_algorithm = "builtin.dismas_solver" },
        .scene_blueprint = .{
            .observation_regime = .limb,
            .derivative_mode = .numerical,
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = dismas_sample_count },
            .measurement_count_hint = dismas_sample_count,
        },
    });
    defer plan.deinit();

    const context: RealEvaluatorContext = .{
        .allocator = std.testing.allocator,
        .plan = &plan,
    };
    const evaluator = realEvaluator(&context);

    const truth_scene: zdisamar.Scene = .{
        .id = "dismas-truth",
        .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = dismas_sample_count },
        .surface = .{ .albedo = 0.17 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.13, .layer_center_km = 4.0, .layer_width_km = 1.4 },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .limb,
            .noise_model = .shot_noise,
            .wavelength_shift_nm = 0.012,
        },
    };
    var observed_product = try evaluateProduct(std.testing.allocator, &context, truth_scene);
    defer observed_product.deinit(std.testing.allocator);

    const retrieval_scene: zdisamar.Scene = .{
        .id = "dismas-retrieval",
        .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = dismas_sample_count },
        .surface = .{ .albedo = 0.11 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.07, .layer_center_km = 4.0, .layer_width_km = 1.4 },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .limb,
            .noise_model = .shot_noise,
        },
    };
    const problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = retrieval_scene,
        .inverse_problem = .{
            .id = "dismas-validation",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.12, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.09, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 2.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = -0.2, .max = 0.2 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = dismas_sample_count,
                .source = .{ .external_observation = .{ .name = "truth_radiance" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-5 },
            },
            .fit_controls = .{ .max_iterations = 8 },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = dismas_sample_count,
            .product = .init(&observed_product),
        },
    };

    var observed_measurement = try retrieval.common.forward_model.observedMeasurement(std.testing.allocator, problem);
    defer observed_measurement.deinit(std.testing.allocator);
    const layout = try retrieval.common.state_access.resolveStateLayout(problem);
    const seeded_state = try retrieval.common.state_access.seedStateWithLayout(std.testing.allocator, problem, layout);
    defer std.testing.allocator.free(seeded_state);
    const initial_scene = try retrieval.common.state_access.sceneForStateWithLayout(problem, seeded_state, layout);
    var initial_measurement = try retrieval.common.forward_model.evaluateMeasurement(std.testing.allocator, problem, evaluator, initial_scene);
    defer initial_measurement.deinit(std.testing.allocator);
    const initial_residual = try retrieval.common.spectral_fit.fitResidualCost(
        std.testing.allocator,
        .dismas,
        observed_measurement,
        initial_measurement,
    );
    const result = try retrieval.dismas.solver.solveWithEvaluator(std.testing.allocator, problem, evaluator);
    defer {
        var owned = result;
        owned.deinit(std.testing.allocator);
    }
    var fitted_measurement = try retrieval.common.forward_model.evaluateMeasurement(
        std.testing.allocator,
        problem,
        evaluator,
        result.fitted_scene.?,
    );
    defer fitted_measurement.deinit(std.testing.allocator);

    try std.testing.expect(result.fit_diagnostics != null);
    try std.testing.expectEqual(retrieval.common.contracts.FitSpace.radiance, result.fit_diagnostics.?.fit_space);
    try std.testing.expect(result.fit_diagnostics.?.selected_rtm_sample_count <= 64);
    try std.testing.expect(result.fit_diagnostics.?.selected_rtm_sample_count < dismas_sample_count);
    try std.testing.expect(result.fit_diagnostics.?.selection_zero_crossing_count > 0);
    try std.testing.expect(result.fit_diagnostics.?.weighted_residual_rms > 0.0);
    const final_residual = try retrieval.common.spectral_fit.fitResidualCost(
        std.testing.allocator,
        .dismas,
        observed_measurement,
        fitted_measurement,
    );
    try std.testing.expect(final_residual < initial_residual);
    try std.testing.expect(result.state_estimate.values[2] >= -0.2 and result.state_estimate.values[2] <= 0.2);
}

test "dismas validation exercises engine provider dispatch on real spectra" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{ .retrieval_algorithm = "builtin.dismas_solver" },
        .scene_blueprint = .{
            .observation_regime = .limb,
            .derivative_mode = .numerical,
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = dismas_sample_count },
            .measurement_count_hint = dismas_sample_count,
        },
    });
    defer plan.deinit();

    const context: RealEvaluatorContext = .{
        .allocator = std.testing.allocator,
        .plan = &plan,
    };
    var workspace = engine.createWorkspace("dismas-provider-validation");

    var request = zdisamar.Request.init(.{
        .id = "dismas-provider-request",
        .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = dismas_sample_count },
        .surface = .{ .albedo = 0.11 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.07, .layer_center_km = 4.0, .layer_width_km = 1.4 },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .limb,
            .noise_model = .shot_noise,
        },
    });
    request.expected_derivative_mode = .numerical;
    request.diagnostics = .{ .jacobians = true };
    request.inverse_problem = .{
        .id = "dismas-provider-validation",
        .state_vector = .{
            .parameters = &[_]StateParameter{
                .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.12, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.09, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 2.0 } },
                .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = -0.2, .max = 0.2 } },
            },
        },
        .measurements = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = dismas_sample_count,
            .source = .{ .external_observation = .{ .name = "truth_radiance" } },
            .error_model = .{ .from_source_noise = true, .floor = 1.0e-5 },
        },
        .fit_controls = .{ .max_iterations = 8 },
    };

    var truth_scene = request.scene;
    truth_scene.id = "dismas-provider-truth";
    truth_scene.surface.albedo = 0.17;
    truth_scene.aerosol = .{ .enabled = true, .optical_depth = 0.13, .layer_center_km = 4.0, .layer_width_km = 1.4 };
    truth_scene.observation_model.wavelength_shift_nm = 0.012;

    var observed_product = try evaluateProduct(std.testing.allocator, &context, truth_scene);
    defer observed_product.deinit(std.testing.allocator);
    request.measurement_binding = .{
        .source = .{ .external_observation = .{ .name = "truth_radiance" } },
        .borrowed_product = .init(&observed_product),
    };

    const bound_problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(&request);
    var observed_measurement = try retrieval.common.forward_model.observedMeasurement(std.testing.allocator, bound_problem);
    defer observed_measurement.deinit(std.testing.allocator);
    const layout = try retrieval.common.state_access.resolveStateLayout(bound_problem);
    const seeded_state = try retrieval.common.state_access.seedStateWithLayout(std.testing.allocator, bound_problem, layout);
    defer std.testing.allocator.free(seeded_state);
    const initial_scene = try retrieval.common.state_access.sceneForStateWithLayout(bound_problem, seeded_state, layout);
    var initial_measurement = try retrieval.common.forward_model.evaluateMeasurement(
        std.testing.allocator,
        bound_problem,
        realEvaluator(&context),
        initial_scene,
    );
    defer initial_measurement.deinit(std.testing.allocator);
    const initial_residual = try retrieval.common.spectral_fit.fitResidualCost(
        std.testing.allocator,
        .dismas,
        observed_measurement,
        initial_measurement,
    );
    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.retrieval != null);
    try std.testing.expect(result.retrieval_products.fitted_measurement != null);
    try std.testing.expect(result.retrieval_products.jacobian != null);
    try std.testing.expect(result.retrieval.?.fit_diagnostics != null);
    try std.testing.expectEqual(
        retrieval.common.contracts.FitSpace.radiance,
        result.retrieval.?.fit_diagnostics.?.fit_space,
    );
    try std.testing.expect(result.retrieval.?.fit_diagnostics.?.selected_rtm_sample_count <= 64);
    try std.testing.expect(result.retrieval.?.fit_diagnostics.?.selected_rtm_sample_count < dismas_sample_count);
    try std.testing.expect(result.retrieval.?.fit_diagnostics.?.selection_zero_crossing_count > 0);
    var fitted_measurement = try retrieval.common.forward_model.measurementFromProduct(
        std.testing.allocator,
        bound_problem,
        &result.retrieval_products.fitted_measurement.?,
    );
    defer fitted_measurement.deinit(std.testing.allocator);
    const final_residual = try retrieval.common.spectral_fit.fitResidualCost(
        std.testing.allocator,
        .dismas,
        observed_measurement,
        fitted_measurement,
    );
    try std.testing.expect(final_residual < initial_residual);
}
