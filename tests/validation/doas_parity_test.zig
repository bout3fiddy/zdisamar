const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const retrieval = @import("zdisamar_internal").retrieval;

const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.preparation;
const StateParameter = zdisamar.StateParameter;
const AbsorberSpecies = @typeInfo(@TypeOf(@as(zdisamar.Absorber, .{}).resolved_species)).optional.child;

var no2_cross_section_points = [_]ReferenceData.CrossSectionPoint{
    .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 4.8e-19 },
    .{ .wavelength_nm = 420.0, .sigma_cm2_per_molecule = 3.4e-19 },
    .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 2.2e-19 },
    .{ .wavelength_nm = 450.0, .sigma_cm2_per_molecule = 1.7e-19 },
    .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 1.1e-19 },
};
const no2_cross_section_table = ReferenceData.CrossSectionTable{
    .points = no2_cross_section_points[0..],
};
const no2_bands = [_]zdisamar.SpectralBand{
    .{
        .id = "vis-no2",
        .start_nm = 405.0,
        .end_nm = 465.0,
        .step_nm = 1.25,
    },
};
const no2_profile_ppmv = [_][2]f64{
    .{ 1000.0, 0.09 },
    .{ 450.0, 0.03 },
};
const no2_strong_absorption_bands = [_]bool{true};
const no2_polynomial_degree_bands = [_]u32{6};

const No2SceneFixture = struct {
    absorbers: [1]zdisamar.Absorber,
    scene: zdisamar.Scene,
};

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
) anyerror!internal.kernels.transport.measurement.MeasurementSpaceSummary {
    const context: *const RealEvaluatorContext = @ptrCast(@alignCast(context_ptr));
    var product = try evaluateProduct(context.allocator, context_ptr, scene);
    defer product.deinit(context.allocator);
    return product.summary;
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

fn makeNo2CrossSectionScene(
    id: []const u8,
    albedo: f64,
    wavelength_shift_nm: f64,
) No2SceneFixture {
    const fixture = No2SceneFixture{
        .absorbers = .{
            zdisamar.Absorber{
                .id = "no2",
                .species = "no2",
                .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "no2").?,
                .profile_source = .atmosphere,
                .volume_mixing_ratio_profile_ppmv = no2_profile_ppmv[0..],
                .spectroscopy = .{
                    .mode = .cross_sections,
                    .resolved_cross_section_table = no2_cross_section_table,
                },
            },
        },
        .scene = .{
            .id = id,
            .geometry = .{
                .model = .plane_parallel,
                .solar_zenith_deg = 30.0,
                .viewing_zenith_deg = 12.0,
                .relative_azimuth_deg = 40.0,
            },
            .atmosphere = .{
                .layer_count = 8,
            },
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 24,
            },
            .bands = .{
                .items = no2_bands[0..],
            },
            .absorbers = .{},
            .surface = .{ .albedo = albedo },
            .observation_model = .{
                .instrument = .synthetic,
                .noise_model = .shot_noise,
                .wavelength_shift_nm = wavelength_shift_nm,
                .cross_section_fit = .{
                    .use_effective_cross_section_oe = true,
                    .use_polynomial_expansion = true,
                    .xsec_strong_absorption_bands = no2_strong_absorption_bands[0..],
                    .polynomial_degree_bands = no2_polynomial_degree_bands[0..],
                },
            },
        },
    };
    return fixture;
}

test "doas validation recovers an O2A differential fit on real spectra" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{ .retrieval_algorithm = "builtin.doas_solver" },
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .numerical,
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 24 },
            .measurement_count_hint = 24,
        },
    });
    defer plan.deinit();

    const context: RealEvaluatorContext = .{
        .allocator = std.testing.allocator,
        .plan = &plan,
    };
    const evaluator = realEvaluator(&context);

    const truth_scene: zdisamar.Scene = .{
        .id = "doas-truth",
        .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 24 },
        .surface = .{ .albedo = 0.15 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.10, .layer_center_km = 3.2, .layer_width_km = 1.0 },
        .observation_model = .{ .instrument = .synthetic, .noise_model = .shot_noise, .wavelength_shift_nm = 0.01 },
    };
    var observed_product = try evaluateProduct(std.testing.allocator, &context, truth_scene);
    defer observed_product.deinit(std.testing.allocator);

    const retrieval_scene: zdisamar.Scene = .{
        .id = "doas-retrieval",
        .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 24 },
        .surface = .{ .albedo = 0.09 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.06, .layer_center_km = 3.2, .layer_width_km = 1.0 },
        .observation_model = .{ .instrument = .synthetic, .noise_model = .shot_noise },
    };
    var initial_product = try evaluateProduct(std.testing.allocator, &context, retrieval_scene);
    defer initial_product.deinit(std.testing.allocator);

    const problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = retrieval_scene,
        .inverse_problem = .{
            .id = "doas-validation",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 1.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = -0.1, .max = 0.1 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 24,
                .source = .{ .external_observation = .{ .name = "truth_radiance" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-5 },
            },
            .fit_controls = .{ .max_iterations = 4 },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = 24,
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
        .doas,
        problem.scene,
        observed_measurement,
        initial_measurement,
    );
    const result = try retrieval.doas.solver.solveWithEvaluator(std.testing.allocator, problem, evaluator);
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

    try std.testing.expect(result.converged or result.iterations == 4);
    try std.testing.expect(result.fit_diagnostics != null);
    try std.testing.expectEqual(retrieval.common.contracts.FitSpace.differential_optical_depth, result.fit_diagnostics.?.fit_space);
    try std.testing.expect(result.fit_diagnostics.?.effective_cross_section_rms != null);
    try std.testing.expect(result.fit_diagnostics.?.weighted_residual_rms > 0.0);
    try std.testing.expect(
        try retrieval.common.spectral_fit.fitResidualCost(
            std.testing.allocator,
            .doas,
            problem.scene,
            observed_measurement,
            fitted_measurement,
        ) < initial_residual,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), result.state_estimate.values[2], 0.03);
}

test "doas validation exercises engine provider dispatch on real spectra" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{ .retrieval_algorithm = "builtin.doas_solver" },
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .numerical,
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 24 },
            .measurement_count_hint = 24,
        },
    });
    defer plan.deinit();

    const context: RealEvaluatorContext = .{
        .allocator = std.testing.allocator,
        .plan = &plan,
    };
    var workspace = engine.createWorkspace("doas-provider-validation");

    var request = zdisamar.Request.init(.{
        .id = "doas-provider-request",
        .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 24 },
        .surface = .{ .albedo = 0.09 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.06, .layer_center_km = 3.2, .layer_width_km = 1.0 },
        .observation_model = .{ .instrument = .synthetic, .noise_model = .shot_noise },
    });
    request.expected_derivative_mode = .numerical;
    request.diagnostics = .{ .jacobians = true };
    request.inverse_problem = .{
        .id = "doas-provider-validation",
        .state_vector = .{
            .parameters = &[_]StateParameter{
                .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 1.0 } },
                .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = -0.1, .max = 0.1 } },
            },
        },
        .measurements = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = 24,
            .source = .{ .external_observation = .{ .name = "truth_radiance" } },
            .error_model = .{ .from_source_noise = true, .floor = 1.0e-5 },
        },
        .fit_controls = .{ .max_iterations = 4 },
    };

    var truth_scene = request.scene;
    truth_scene.id = "doas-provider-truth";
    truth_scene.surface.albedo = 0.15;
    truth_scene.aerosol = .{ .enabled = true, .optical_depth = 0.10, .layer_center_km = 3.2, .layer_width_km = 1.0 };
    truth_scene.observation_model.wavelength_shift_nm = 0.01;

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
        .doas,
        bound_problem.scene,
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
        retrieval.common.contracts.FitSpace.differential_optical_depth,
        result.retrieval.?.fit_diagnostics.?.fit_space,
    );
    var fitted_measurement = try retrieval.common.forward_model.measurementFromProduct(
        std.testing.allocator,
        bound_problem,
        &result.retrieval_products.fitted_measurement.?,
    );
    defer fitted_measurement.deinit(std.testing.allocator);
    try std.testing.expect(
        try retrieval.common.spectral_fit.fitResidualCost(
            std.testing.allocator,
            .doas,
            bound_problem.scene,
            observed_measurement,
            fitted_measurement,
        ) < initial_residual,
    );
}

test "doas validation routes a NO2 cross-section scene through explicit effective-xsec optics" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{ .retrieval_algorithm = "builtin.doas_solver" },
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .numerical,
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 24 },
            .layer_count_hint = 8,
            .measurement_count_hint = 24,
        },
    });
    defer plan.deinit();

    const context: RealEvaluatorContext = .{
        .allocator = std.testing.allocator,
        .plan = &plan,
    };
    const evaluator = realEvaluator(&context);

    var truth_fixture = makeNo2CrossSectionScene("doas-no2-truth", 0.14, 0.012);
    truth_fixture.scene.absorbers.items = truth_fixture.absorbers[0..];
    const truth_scene = truth_fixture.scene;
    var retrieval_fixture = makeNo2CrossSectionScene("doas-no2-retrieval", 0.08, 0.0);
    retrieval_fixture.scene.absorbers.items = retrieval_fixture.absorbers[0..];
    const retrieval_scene = retrieval_fixture.scene;

    var prepared = try plan.providers.optics.prepareForScene(std.testing.allocator, &retrieval_scene);
    defer prepared.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), prepared.cross_section_absorbers.len);
    try std.testing.expectEqual(@as(usize, 0), prepared.line_absorbers.len);
    try std.testing.expectEqual(OpticsPrepare.state.CrossSectionRepresentationKind.effective_table, prepared.cross_section_absorbers[0].representation_kind);
    try std.testing.expectEqual(@as(u32, 6), prepared.cross_section_absorbers[0].polynomial_order);
    try std.testing.expect(prepared.collision_induced_absorption == null);
    try std.testing.expect(prepared.gas_optical_depth > 0.0);

    var observed_product = try evaluateProduct(std.testing.allocator, &context, truth_scene);
    defer observed_product.deinit(std.testing.allocator);
    var initial_product = try evaluateProduct(std.testing.allocator, &context, retrieval_scene);
    defer initial_product.deinit(std.testing.allocator);

    const problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = retrieval_scene,
        .inverse_problem = .{
            .id = "doas-no2-cross-section",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = -0.1, .max = 0.1 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 24,
                .source = .{ .external_observation = .{ .name = "truth_radiance" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-5 },
            },
            .fit_controls = .{ .max_iterations = 4 },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = 24,
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
        .doas,
        problem.scene,
        observed_measurement,
        initial_measurement,
    );
    const initial_product_residual = l2ResidualNorm(observed_product.radiance, initial_product.radiance);

    const result = try retrieval.doas.solver.solveWithEvaluator(std.testing.allocator, problem, evaluator);
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
    var fitted_product = try evaluateProduct(std.testing.allocator, &context, result.fitted_scene.?);
    defer fitted_product.deinit(std.testing.allocator);

    try std.testing.expect(result.fit_diagnostics != null);
    try std.testing.expectEqual(retrieval.common.contracts.FitSpace.differential_optical_depth, result.fit_diagnostics.?.fit_space);
    try std.testing.expectEqual(@as(u32, 6), result.fit_diagnostics.?.polynomial_order);
    try std.testing.expect(result.fit_diagnostics.?.effective_cross_section_rms != null);
    try std.testing.expect(result.fit_diagnostics.?.weighted_residual_rms > 0.0);
    try std.testing.expect(
        try retrieval.common.spectral_fit.fitResidualCost(
            std.testing.allocator,
            .doas,
            problem.scene,
            observed_measurement,
            fitted_measurement,
        ) < initial_residual,
    );
    try std.testing.expect(l2ResidualNorm(observed_product.radiance, fitted_product.radiance) < initial_product_residual);
    try std.testing.expectApproxEqAbs(@as(f64, 0.012), result.state_estimate.values[1], 0.04);
}
