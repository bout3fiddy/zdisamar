const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

const MeasurementSpace = internal.kernels.transport.measurement;
const TransportCommon = internal.kernels.transport.common;
const PreparedLayout = internal.runtime.cache.PreparedLayout;
const BatchJob = internal.runtime.scheduler.BatchJob;
const ThreadContext = internal.runtime.scheduler.ThreadContext;

fn measurementProviders(plan: *const zdisamar.PreparedPlan) MeasurementSpace.ProviderBindings {
    return .{
        .transport = plan.providers.transport,
        .surface = plan.providers.surface,
        .instrument = plan.providers.instrument,
        .noise = plan.providers.noise,
    };
}

test "preparePlan validates lifecycle prerequisites and plan templates" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{ .max_prepared_plans = 1 });
    defer engine.deinit();

    try std.testing.expectError(error.CatalogNotBootstrapped, engine.preparePlan(.{}));
    try engine.bootstrapBuiltinCatalog();
    try std.testing.expectError(error.UnsupportedModelFamily, engine.preparePlan(.{ .model_family = "unknown" }));
    try std.testing.expectError(error.UnsupportedCapability, engine.preparePlan(.{
        .providers = .{
            .transport_solver = "transport.custom",
        },
    }));

    var first_plan = try engine.preparePlan(.{});
    defer first_plan.deinit();

    var second_plan = try engine.preparePlan(.{});
    defer second_plan.deinit();
    try std.testing.expectEqual(@as(u64, first_plan.id + 1), second_plan.id);
    try std.testing.expectEqual(@as(usize, 1), engine.plan_cache.count());
}

test "preparePlan resolves typed transport routes from plan-time observation and derivative choices" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var scalar_plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .semi_analytical,
        },
    });
    defer scalar_plan.deinit();
    try std.testing.expectEqual(TransportCommon.TransportFamily.labos, scalar_plan.transport_route.family);
    try std.testing.expectEqual(TransportCommon.DerivativeMode.semi_analytical, scalar_plan.transport_route.derivative_mode);

    var polarized_plan = try engine.preparePlan(.{
        .solver_mode = .polarized,
        .scene_blueprint = .{
            .observation_regime = .limb,
            .derivative_mode = .semi_analytical,
        },
    });
    defer polarized_plan.deinit();
    try std.testing.expectEqual(TransportCommon.TransportFamily.labos, polarized_plan.transport_route.family);
    try std.testing.expectEqual(TransportCommon.ExecutionMode.polarized, polarized_plan.transport_route.execution_mode);
    try std.testing.expectEqual(TransportCommon.Regime.limb, polarized_plan.transport_route.regime);
}

test "execute enforces workspace plan binding and derivative-mode contracts" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var scalar_plan = try engine.preparePlan(.{ .scene_blueprint = .{ .derivative_mode = .none } });
    defer scalar_plan.deinit();
    var derivative_plan = try engine.preparePlan(.{ .scene_blueprint = .{ .derivative_mode = .semi_analytical } });
    defer derivative_plan.deinit();

    var workspace = engine.createWorkspace("unit");
    const scene: zdisamar.Scene = .{ .id = "scene", .spectral_grid = .{ .sample_count = 4 } };
    var request = zdisamar.Request.init(scene);
    var scalar_result = try engine.execute(&scalar_plan, &workspace, &request);
    defer scalar_result.deinit(std.testing.allocator);

    request.expected_derivative_mode = .semi_analytical;
    try std.testing.expectError(error.DerivativeModeMismatch, engine.execute(&scalar_plan, &workspace, &request));
    var workspace_mismatch_request = zdisamar.Request.init(scene);
    try std.testing.expectError(error.WorkspacePlanMismatch, engine.execute(&derivative_plan, &workspace, &workspace_mismatch_request));
}

test "execute leaves workspace untouched when request validation fails" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var first_plan = try engine.preparePlan(.{});
    defer first_plan.deinit();
    var second_plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .derivative_mode = .semi_analytical,
        },
    });
    defer second_plan.deinit();

    var workspace = engine.createWorkspace("validation-guard");

    var missing_scene_request = zdisamar.Request.init(.{
        .id = "",
        .spectral_grid = .{ .sample_count = 8 },
    });
    try std.testing.expectError(
        error.MissingScene,
        engine.execute(&first_plan, &workspace, &missing_scene_request),
    );
    try std.testing.expectEqual(@as(?u64, null), workspace.bound_plan_id);
    try std.testing.expectEqual(@as(u64, 0), workspace.execution_count);
    try std.testing.expectEqual(@as(u64, 0), workspace.scratch.reserve_count);

    var post_error_request = zdisamar.Request.init(.{
        .id = "scene-after-error",
        .spectral_grid = .{ .sample_count = 8 },
    });
    var result = try engine.execute(&second_plan, &workspace, &post_error_request);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(second_plan.id, result.plan_id);
    try std.testing.expectEqual(second_plan.id, workspace.bound_plan_id.?);
}

test "execute rejects retrieval stage-product requests without a bound measurement" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{
            .retrieval_algorithm = "builtin.oe_solver",
        },
        .scene_blueprint = .{
            .derivative_mode = .semi_analytical,
        },
    });
    defer plan.deinit();

    var workspace = engine.createWorkspace("request-validation-suite");
    var request = zdisamar.Request.init(.{
        .id = "scene-missing-binding",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 16,
        },
        .atmosphere = .{
            .layer_count = 18,
        },
        .observation_model = .{
            .instrument = .synthetic,
        },
    });
    request.expected_derivative_mode = .semi_analytical;
    request.inverse_problem = .{
        .id = "inverse-missing-binding",
        .state_vector = .{
            .parameters = &[_]zdisamar.StateParameter{
                .{ .name = "surface_albedo", .target = .surface_albedo },
            },
        },
        .measurements = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = 16,
            .source = .{ .stage_product = .{ .name = "forward-stage" } },
        },
    };

    try std.testing.expectError(error.InvalidRequest, engine.execute(&plan, &workspace, &request));
    try std.testing.expectEqual(@as(?u64, null), workspace.bound_plan_id);
}

test "prepared plans keep plugin snapshots when registry changes later" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{ .allow_native_plugins = true });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var first_plan = try engine.preparePlan(.{});
    defer first_plan.deinit();

    try engine.registerPluginManifest(.{
        .id = "example.extra_dataset",
        .package = "disamar_standard",
        .version = "0.2.0",
        .lane = .declarative,
        .capabilities = &[_]internal.plugin_internal.manifest.CapabilityDecl{
            .{ .slot = "data.pack", .name = "example.extra_dataset" },
        },
        .provenance = .{
            .dataset_hashes = &[_][]const u8{
                "sha256:example-extra-dataset",
            },
        },
    });

    var second_plan = try engine.preparePlan(.{});
    defer second_plan.deinit();

    try std.testing.expect(second_plan.plugin_snapshot.generation > first_plan.plugin_snapshot.generation);
    try std.testing.expect(second_plan.plugin_snapshot.pluginVersionCount() > first_plan.plugin_snapshot.pluginVersionCount());

    var workspace = engine.createWorkspace("snapshot-suite");
    const request = zdisamar.Request.init(.{
        .id = "scene-snapshot",
        .spectral_grid = .{ .sample_count = 8 },
    });
    var first_result = try engine.execute(&first_plan, &workspace, &request);
    defer first_result.deinit(std.testing.allocator);
    workspace.reset();
    var second_result = try engine.execute(&second_plan, &workspace, &request);
    defer second_result.deinit(std.testing.allocator);

    try std.testing.expect(second_result.provenance.pluginVersionCount() > first_result.provenance.pluginVersionCount());
    try std.testing.expect(second_result.provenance.dataset_hashes.len > first_result.provenance.dataset_hashes.len);
}

test "default builtin execution stays on typed providers when native plugins are disabled" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{});
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 0), plan.plugin_runtime.native_plugins.len);
    try std.testing.expectEqual(@as(usize, 0), plan.plugin_snapshot.nativeCapabilitySlots().len);

    var workspace = engine.createWorkspace("typed-provider-only");
    const request = zdisamar.Request.init(.{
        .id = "scene-typed-provider-only",
        .spectral_grid = .{ .sample_count = 8 },
    });
    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqual(@as(usize, 0), result.provenance.native_capability_slots.len);
    try std.testing.expectEqualStrings("builtin.dispatcher", result.provenance.solver_route);
    try std.testing.expect(result.measurement_space != null);
}

test "preparePlan releases resources when plan cache insertion fails" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();
    engine.plan_cache.options.max_entries = 0;

    try std.testing.expectError(error.PreparedPlanLimitExceeded, engine.preparePlan(.{}));
}

test "prepared plans own reusable cache hints and workspaces own reusable scratch" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 121,
            },
            .layer_count_hint = 48,
            .state_parameter_count_hint = 3,
            .measurement_count_hint = 121,
        },
    });
    defer plan.deinit();

    var workspace = engine.createWorkspace("cache-suite");
    const request = zdisamar.Request.init(.{
        .id = "scene-cache",
        .atmosphere = .{ .layer_count = 48 },
        .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 121 },
    });
    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 121), workspace.scratch.spectral_capacity);
    try std.testing.expectEqual(@as(usize, 48), workspace.scratch.layer_capacity);
    try std.testing.expectEqual(@as(usize, 3), workspace.scratch.state_capacity);
    try std.testing.expectEqual(@as(usize, 121), workspace.scratch.measurement_capacity);

    workspace.reset();
    try std.testing.expectEqual(@as(u64, 1), workspace.scratch.reset_count);
}

test "engine retrieval execution preserves solver-owned oe products" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{
            .retrieval_algorithm = "builtin.oe_solver",
        },
        .scene_blueprint = .{
            .derivative_mode = .semi_analytical,
            .measurement_count_hint = 24,
        },
    });
    defer plan.deinit();

    var workspace = engine.createWorkspace("retrieval-summary-suite");
    var request = zdisamar.Request.init(.{
        .id = "scene-retrieval-summary-suite",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 24,
        },
        .atmosphere = .{
            .layer_count = 18,
        },
        .surface = .{
            .albedo = 0.10,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
    });
    request.expected_derivative_mode = .semi_analytical;
    request.diagnostics = .{
        .provenance = true,
        .jacobians = true,
    };
    request.inverse_problem = .{
        .id = "inverse-summary-suite",
        .state_vector = .{
            .parameters = &[_]zdisamar.StateParameter{
                .{ .name = "surface_albedo", .target = .surface_albedo, .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.02 } },
                .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .prior = .{ .enabled = true, .mean = 0.05, .sigma = 0.03 } },
            },
        },
        .measurements = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = 24,
            .source = .{ .external_observation = .{ .name = "truth-radiance" } },
            .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
        },
    };

    var truth_scene = request.scene;
    truth_scene.surface.albedo = 0.14;
    truth_scene.aerosol = .{
        .enabled = true,
        .optical_depth = 0.08,
        .layer_center_km = 3.0,
        .layer_width_km = 1.0,
    };
    var prepared_optics = try plan.providers.optics.prepareForScene(std.testing.allocator, &truth_scene);
    defer prepared_optics.deinit(std.testing.allocator);
    var observed_product = try MeasurementSpace.simulateProduct(
        std.testing.allocator,
        &truth_scene,
        plan.transport_route,
        &prepared_optics,
        measurementProviders(&plan),
    );
    defer observed_product.deinit(std.testing.allocator);
    request.measurement_binding = .{
        .source = .{ .external_observation = .{ .name = "truth-radiance" } },
        .borrowed_product = .init(&observed_product),
    };

    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.measurement_space != null);
    try std.testing.expect(result.measurement_space_product != null);
    try std.testing.expect(result.retrieval != null);
    try std.testing.expect(result.retrieval.?.fitted_measurement != null);
    try std.testing.expect(result.retrieval_products.fitted_measurement != null);
    try std.testing.expect(result.retrieval_products.state_vector != null);
    try std.testing.expect(result.retrieval_products.jacobian != null);
    try std.testing.expect(result.retrieval_products.averaging_kernel != null);
    try std.testing.expect(result.retrieval_products.posterior_covariance != null);
    try std.testing.expect(result.retrieval.?.jacobian != null);
    try std.testing.expect(result.retrieval.?.averaging_kernel != null);
    try std.testing.expect(result.retrieval.?.posterior_covariance != null);
    try std.testing.expectEqual(
        result.retrieval.?.fitted_measurement.?.sample_count,
        @as(u32, @intCast(result.retrieval_products.fitted_measurement.?.wavelengths.len)),
    );
    try std.testing.expectEqual(
        result.retrieval.?.jacobian.?.row_count,
        result.retrieval_products.jacobian.?.row_count,
    );
    try std.testing.expectEqual(
        result.retrieval.?.posterior_covariance.?.row_count,
        result.retrieval_products.posterior_covariance.?.row_count,
    );
}

test "engine rejects retrieval requests with unset typed state targets" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{
            .retrieval_algorithm = "builtin.oe_solver",
        },
        .scene_blueprint = .{
            .derivative_mode = .semi_analytical,
        },
    });
    defer plan.deinit();

    var workspace = engine.createWorkspace("retrieval-invalid-target-suite");
    var request = zdisamar.Request.init(.{
        .id = "scene-retrieval-invalid-target-suite",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 24,
        },
        .atmosphere = .{
            .layer_count = 18,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
    });
    request.expected_derivative_mode = .semi_analytical;
    request.diagnostics = .{
        .provenance = true,
        .jacobians = true,
    };
    request.inverse_problem = .{
        .id = "inverse-invalid-target-suite",
        .state_vector = .{
            .parameters = &[_]zdisamar.StateParameter{
                .{ .name = "bad_target", .target = .unset },
            },
        },
        .measurements = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = 24,
            .source = .{ .external_observation = .{ .name = "forward-measurement" } },
            .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
        },
    };
    var prepared_optics = try plan.providers.optics.prepareForScene(std.testing.allocator, &request.scene);
    defer prepared_optics.deinit(std.testing.allocator);
    var observed_product = try MeasurementSpace.simulateProduct(
        std.testing.allocator,
        &request.scene,
        plan.transport_route,
        &prepared_optics,
        measurementProviders(&plan),
    );
    defer observed_product.deinit(std.testing.allocator);
    request.measurement_binding = .{
        .source = .{ .external_observation = .{ .name = "forward-measurement" } },
        .borrowed_product = .init(&observed_product),
    };

    try std.testing.expectError(error.InvalidRequest, engine.execute(&plan, &workspace, &request));
}

test "engine owns runtime caches and batch scheduling helpers explicitly" {
    const Ctx = struct {
        executed: usize = 0,
    };

    const Callbacks = struct {
        fn execute(
            ctx_ptr: ?*anyopaque,
            thread: *ThreadContext,
            job: BatchJob,
            prepared_layout: *const PreparedLayout,
        ) !void {
            _ = thread;
            _ = job;
            _ = prepared_layout;
            const ctx: *Ctx = @ptrCast(@alignCast(ctx_ptr.?));
            ctx.executed += 1;
        }
    };

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    try engine.registerDatasetArtifact("climatology.base", "sha256:climatology-base");
    try engine.registerLUTArtifact("climatology.base", "temperature_273", .{
        .spectral_bins = 32,
        .layer_count = 12,
        .coefficient_count = 4,
    });

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .measurement_count_hint = 24,
        },
    });
    defer plan.deinit();
    try std.testing.expect(engine.plan_cache.get(plan.id) != null);
    try std.testing.expectEqual(@as(usize, 2), engine.dataset_cache.count());
    try std.testing.expectEqual(@as(usize, 1), engine.lut_cache.count());

    var thread = engine.createThreadContext("batch-thread");
    var runner = engine.createBatchRunner();
    defer runner.deinit();
    try runner.enqueue(.{ .plan_id = plan.id, .scene_id = "scene-batch-a" });
    try runner.enqueue(.{ .plan_id = plan.id, .scene_id = "scene-batch-b" });

    var ctx: Ctx = .{};
    try engine.runBatch(&runner, &thread, &ctx, Callbacks.execute);

    try std.testing.expectEqual(@as(usize, 2), ctx.executed);
    try std.testing.expectEqual(@as(u64, 2), runner.completed_jobs);
    try std.testing.expectEqual(@as(u64, 2), engine.plan_cache.get(plan.id).?.run_count);
}
