const std = @import("std");

const Catalog = @import("Catalog.zig").Catalog;
const PlanModule = @import("Plan.zig");
const Plan = PlanModule.Plan;
const Request = @import("Request.zig").Request;
const Result = @import("Result.zig").Result;
const Workspace = @import("Workspace.zig").Workspace;
const Provenance = @import("provenance.zig").Provenance;
const Scene = @import("../model/Scene.zig").Scene;
const errors = @import("errors.zig");
const PluginManifest = @import("../plugins/loader/manifest.zig").PluginManifest;
const CapabilityRegistry = @import("../plugins/registry/CapabilityRegistry.zig").CapabilityRegistry;
const PluginRuntime = @import("../plugins/loader/runtime.zig");
const PluginProviders = @import("../plugins/providers/root.zig");
const DatasetCache = @import("../runtime/cache/DatasetCache.zig").DatasetCache;
const LUTCache = @import("../runtime/cache/LUTCache.zig").LUTCache;
const PlanCache = @import("../runtime/cache/PlanCache.zig").PlanCache;
const PreparedPlanCache = @import("../runtime/cache/PreparedPlanCache.zig").PreparedPlanCache;
const BatchRunnerModule = @import("../runtime/scheduler/BatchRunner.zig");
const BatchRunner = BatchRunnerModule.BatchRunner;
const BatchJob = BatchRunnerModule.BatchJob;
const ThreadContext = @import("../runtime/scheduler/ThreadContext.zig").ThreadContext;
const TransportCommon = @import("../kernels/transport/common.zig");
const MeasurementSpace = @import("../kernels/transport/measurement_space.zig");
const RetrievalContracts = @import("../retrieval/common/contracts.zig");
const RetrievalForwardModel = @import("../retrieval/common/forward_model.zig");
const Logging = @import("logging.zig");

pub const EngineOptions = struct {
    abi_version: u32 = 1,
    allow_native_plugins: bool = false,
    max_prepared_plans: usize = 64,
    log_policy: Logging.Policy = .{},
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    options: EngineOptions,
    catalog: Catalog = .{},
    registry: CapabilityRegistry = .{},
    dataset_cache: DatasetCache,
    lut_cache: LUTCache,
    plan_cache: PlanCache,
    next_plan_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator, options: EngineOptions) Engine {
        return .{
            .allocator = allocator,
            .options = options,
            .dataset_cache = DatasetCache.init(allocator),
            .lut_cache = LUTCache.init(allocator),
            .plan_cache = PlanCache.init(allocator, .{ .max_entries = options.max_prepared_plans }),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.plan_cache.deinit();
        self.lut_cache.deinit();
        self.dataset_cache.deinit();
        self.registry.deinit(self.allocator);
        self.catalog.deinit(self.allocator);
    }

    pub fn bootstrapBuiltinCatalog(self: *Engine) !void {
        try self.catalog.bootstrapBuiltin(self.allocator);
        try self.registry.bootstrapBuiltin(self.allocator, self.options.allow_native_plugins);
        try self.dataset_cache.upsert("builtin.cross_sections", "sha256:builtin-cross-sections-demo");
    }

    pub fn registerPluginManifest(self: *Engine, manifest: PluginManifest) !void {
        try self.registry.registerManifest(self.allocator, manifest, self.options.allow_native_plugins);
        for (manifest.provenance.dataset_hashes, 0..) |dataset_hash, index| {
            var key_buffer: [128]u8 = undefined;
            const cache_id = try std.fmt.bufPrint(&key_buffer, "{s}#{d}", .{ manifest.id, index });
            try self.dataset_cache.upsert(cache_id, dataset_hash);
        }
    }

    pub fn registerDatasetArtifact(self: *Engine, id: []const u8, dataset_hash: []const u8) !void {
        try self.dataset_cache.upsert(id, dataset_hash);
    }

    pub fn registerLUTArtifact(self: *Engine, dataset_id: []const u8, lut_id: []const u8, shape: LUTCache.Shape) !void {
        try self.lut_cache.upsert(dataset_id, lut_id, shape);
    }

    pub fn preparePlan(self: *Engine, template: PlanModule.Template) !Plan {
        if (!self.catalog.bootstrapped) {
            return errors.Error.CatalogNotBootstrapped;
        }

        try template.validate();

        if (!self.catalog.supportsModelFamily(template.model_family)) {
            return errors.Error.UnsupportedModelFamily;
        }

        if (self.next_plan_id > self.options.max_prepared_plans) {
            return errors.Error.PreparedPlanLimitExceeded;
        }

        const providers = PluginProviders.PreparedProviders.resolve(template.providers) catch {
            return errors.Error.UnsupportedCapability;
        };

        const transport_route = providers.transport.prepareRoute(.{
            .regime = template.scene_blueprint.observation_regime,
            .execution_mode = transportExecutionMode(template.solver_mode),
            .derivative_mode = template.scene_blueprint.derivative_mode,
        }) catch |err| switch (err) {
            error.UnsupportedDerivativeMode => return errors.Error.UnsupportedDerivativeMode,
        };

        var plugin_snapshot = self.registry.snapshotSelection(self.allocator, template.providers) catch {
            return errors.Error.UnsupportedCapability;
        };
        errdefer plugin_snapshot.deinit(self.allocator);

        var plugin_runtime = PluginRuntime.PreparedPluginRuntime.init();
        errdefer plugin_runtime.deinit(self.allocator);
        plugin_runtime.resolveSnapshot(self.allocator, &plugin_snapshot, self.options.allow_native_plugins) catch {
            return errors.Error.PluginPrepareFailed;
        };
        plugin_runtime.prepareForPlan(.{
            .plan_id = self.next_plan_id,
            .model_family = template.model_family,
            .transport_provider = template.providers.transport_solver,
            .solver_mode = @tagName(template.solver_mode),
        }) catch {
            return errors.Error.PluginPrepareFailed;
        };
        const dataset_hash_count = @max(
            plugin_snapshot.datasetHashes().len,
            self.dataset_cache.count(),
        );
        const prepared_cache = try PreparedPlanCache.initFromBlueprint(
            template.scene_blueprint,
            @intCast(dataset_hash_count),
        );
        const plan = Plan.init(
            self.allocator,
            self.next_plan_id,
            template,
            transport_route,
            prepared_cache,
            plugin_snapshot,
            plugin_runtime,
            providers,
        );
        try self.plan_cache.put(plan.id, prepared_cache);
        self.next_plan_id += 1;
        return plan;
    }

    pub fn createWorkspace(self: *Engine, label: []const u8) Workspace {
        _ = self;
        return Workspace.init(label);
    }

    pub fn createThreadContext(self: *Engine, label: []const u8) !ThreadContext {
        return ThreadContext.init(self.allocator, label);
    }

    pub fn createBatchRunner(self: *Engine) BatchRunner {
        return BatchRunner.init(self.allocator);
    }

    pub fn runBatch(
        self: *Engine,
        runner: *BatchRunner,
        thread: *ThreadContext,
        exec_ctx: ?*anyopaque,
        execute_fn: BatchRunnerModule.ExecuteFn,
    ) !void {
        try runner.run(thread, &self.plan_cache, exec_ctx, execute_fn);
    }

    pub fn execute(self: *Engine, plan: *const Plan, workspace: *Workspace, request: Request) !Result {
        try plan.assertReady();
        try request.validateForPlan(plan);

        plan.plugin_runtime.executeForRequest(.{
            .plan_id = plan.id,
            .scene_id = request.scene.id,
            .workspace_label = workspace.label,
            .requested_product_count = @intCast(request.requested_products.len),
        }) catch |err| switch (err) {
            error.PluginExecutionFailed,
            error.PluginEntryRejected,
            error.PluginEntryIncompatibleAbi,
            error.MissingExecuteHook,
            => return errors.Error.PluginExecutionFailed,
            else => return errors.Error.PluginExecutionFailed,
        };
        try workspace.beginExecution(plan.id);
        workspace.prepareScratch(&plan.prepared_cache);
        _ = self.plan_cache.markRun(plan.id);

        var provenance = Provenance.fromPlan(
            self.allocator,
            plan,
            workspace.label,
            request.scene.id,
            @tagName(plan.template.solver_mode),
        ) catch return errors.Error.PluginPrepareFailed;
        errdefer provenance.deinit(self.allocator);

        var prepared_optics = plan.providers.optics.prepareForScene(self.allocator, request.scene) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return errors.Error.InvalidRequest,
        };
        defer prepared_optics.deinit(self.allocator);

        var measurement_space_product = try MeasurementSpace.simulateProduct(
            self.allocator,
            request.scene,
            plan.transport_route,
            prepared_optics,
            measurementProviders(plan),
        );
        errdefer measurement_space_product.deinit(self.allocator);

        var result = Result.init(
            plan.id,
            workspace.label,
            request.scene.id,
            provenance,
        );
        result.attachMeasurementSpaceProduct(measurement_space_product);
        if (request.inverse_problem != null) {
            const retrieval_provider = plan.providers.retrieval orelse return errors.Error.UnsupportedCapability;
            const retrieval_problem = RetrievalContracts.RetrievalProblem.fromRequest(request) catch {
                return errors.Error.InvalidRequest;
            };
            const retrieval_context: RetrievalExecutionContext = .{
                .allocator = self.allocator,
                .plan = plan,
            };
            const retrieval_outcome = retrieval_provider.solve(retrieval_problem, .{
                .context = @ptrCast(&retrieval_context),
                .evaluate = evaluateRetrievalScene,
            }) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return errors.Error.InvalidRequest,
            };
            result.attachRetrievalOutcome(retrieval_outcome);
        }
        result.diagnostics = plan.providers.diagnostics.materialize(
            request.diagnostics,
            "Plugin-selected forward and retrieval providers executed with typed scene preparation and owned provenance.",
        );
        return result;
    }
};

fn transportExecutionMode(solver_mode: PlanModule.SolverMode) TransportCommon.ExecutionMode {
    return switch (solver_mode) {
        .polarized => .polarized,
        .scalar, .derivative_enabled => .scalar,
    };
}

fn measurementProviders(plan: *const Plan) MeasurementSpace.ProviderBindings {
    return .{
        .transport = plan.providers.transport,
        .surface = plan.providers.surface,
        .instrument = plan.providers.instrument,
        .noise = plan.providers.noise,
    };
}

const RetrievalExecutionContext = struct {
    allocator: std.mem.Allocator,
    plan: *const Plan,
};

fn evaluateRetrievalScene(context: *const anyopaque, scene: Scene) anyerror!MeasurementSpace.MeasurementSpaceSummary {
    const typed_context: *const RetrievalExecutionContext = @ptrCast(@alignCast(context));

    var prepared_optics = try typed_context.plan.providers.optics.prepareForScene(typed_context.allocator, scene);
    defer prepared_optics.deinit(typed_context.allocator);

    return MeasurementSpace.simulateSummary(
        typed_context.allocator,
        scene,
        typed_context.plan.transport_route,
        prepared_optics,
        measurementProviders(typed_context.plan),
    );
}

test "preparePlan validates lifecycle prerequisites and plan templates" {
    var engine = Engine.init(std.testing.allocator, .{ .max_prepared_plans = 1 });
    defer engine.deinit();

    try std.testing.expectError(errors.Error.CatalogNotBootstrapped, engine.preparePlan(.{}));
    try engine.bootstrapBuiltinCatalog();
    try std.testing.expectError(errors.Error.UnsupportedModelFamily, engine.preparePlan(.{ .model_family = "unknown" }));
    try std.testing.expectError(errors.Error.UnsupportedCapability, engine.preparePlan(.{
        .providers = .{
            .transport_solver = "transport.custom",
        },
    }));

    var first_plan = try engine.preparePlan(.{});
    defer first_plan.deinit();
    try std.testing.expectError(errors.Error.PreparedPlanLimitExceeded, engine.preparePlan(.{}));
}

test "preparePlan resolves typed transport routes from plan-time observation and derivative choices" {
    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var scalar_plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .semi_analytical,
        },
    });
    defer scalar_plan.deinit();
    try std.testing.expectEqual(TransportCommon.TransportFamily.adding, scalar_plan.transport_route.family);
    try std.testing.expectEqual(TransportCommon.DerivativeMode.semi_analytical, scalar_plan.transport_route.derivative_mode);

    var polarized_plan = try engine.preparePlan(.{
        .solver_mode = .polarized,
        .scene_blueprint = .{
            .observation_regime = .limb,
            .derivative_mode = .analytical_plugin,
        },
    });
    defer polarized_plan.deinit();
    try std.testing.expectEqual(TransportCommon.TransportFamily.labos, polarized_plan.transport_route.family);
    try std.testing.expectEqual(TransportCommon.ExecutionMode.polarized, polarized_plan.transport_route.execution_mode);
    try std.testing.expectEqual(TransportCommon.Regime.limb, polarized_plan.transport_route.regime);
}

test "execute enforces workspace plan binding and derivative-mode contracts" {
    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var scalar_plan = try engine.preparePlan(.{ .scene_blueprint = .{ .derivative_mode = .none } });
    defer scalar_plan.deinit();
    var derivative_plan = try engine.preparePlan(.{ .scene_blueprint = .{ .derivative_mode = .semi_analytical } });
    defer derivative_plan.deinit();

    var workspace = engine.createWorkspace("unit");
    const scene: Scene = .{ .id = "scene", .spectral_grid = .{ .sample_count = 4 } };
    var request = Request.init(scene);
    var scalar_result = try engine.execute(&scalar_plan, &workspace, request);
    defer scalar_result.deinit(std.testing.allocator);

    request.expected_derivative_mode = .semi_analytical;
    try std.testing.expectError(errors.Error.DerivativeModeMismatch, engine.execute(&scalar_plan, &workspace, request));
    try std.testing.expectError(errors.Error.WorkspacePlanMismatch, engine.execute(&derivative_plan, &workspace, Request.init(scene)));
}

test "execute leaves workspace untouched when request validation fails" {
    var engine = Engine.init(std.testing.allocator, .{});
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

    try std.testing.expectError(
        errors.Error.MissingScene,
        engine.execute(&first_plan, &workspace, Request.init(.{
            .id = "",
            .spectral_grid = .{ .sample_count = 8 },
        })),
    );
    try std.testing.expectEqual(@as(?u64, null), workspace.bound_plan_id);
    try std.testing.expectEqual(@as(u64, 0), workspace.execution_count);
    try std.testing.expectEqual(@as(u64, 0), workspace.scratch.reserve_count);

    var result = try engine.execute(&second_plan, &workspace, Request.init(.{
        .id = "scene-after-error",
        .spectral_grid = .{ .sample_count = 8 },
    }));
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(second_plan.id, result.plan_id);
    try std.testing.expectEqual(second_plan.id, workspace.bound_plan_id.?);
}

test "prepared plans keep plugin snapshots when registry changes later" {
    var engine = Engine.init(std.testing.allocator, .{ .allow_native_plugins = true });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var first_plan = try engine.preparePlan(.{});
    defer first_plan.deinit();

    try engine.registerPluginManifest(.{
        .id = "example.extra_dataset",
        .package = "disamar_standard",
        .version = "0.2.0",
        .lane = .declarative,
        .capabilities = &[_]@import("../plugins/loader/manifest.zig").CapabilityDecl{
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
    const request = Request.init(.{
        .id = "scene-snapshot",
        .spectral_grid = .{ .sample_count = 8 },
    });
    var first_result = try engine.execute(&first_plan, &workspace, request);
    defer first_result.deinit(std.testing.allocator);
    workspace.reset();
    var second_result = try engine.execute(&second_plan, &workspace, request);
    defer second_result.deinit(std.testing.allocator);

    try std.testing.expect(second_result.provenance.pluginVersionCount() > first_result.provenance.pluginVersionCount());
    try std.testing.expect(second_result.provenance.dataset_hashes.len > first_result.provenance.dataset_hashes.len);
}

test "prepared plans own reusable cache hints and workspaces own reusable scratch" {
    var engine = Engine.init(std.testing.allocator, .{});
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
    const request = Request.init(.{
        .id = "scene-cache",
        .atmosphere = .{ .layer_count = 48 },
        .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 121 },
    });
    var result = try engine.execute(&plan, &workspace, request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 121), workspace.scratch.spectral_capacity);
    try std.testing.expectEqual(@as(usize, 48), workspace.scratch.layer_capacity);
    try std.testing.expectEqual(@as(usize, 3), workspace.scratch.state_capacity);
    try std.testing.expectEqual(@as(usize, 121), workspace.scratch.measurement_capacity);

    workspace.reset();
    try std.testing.expectEqual(@as(u64, 1), workspace.scratch.reset_count);
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
            prepared: *const PreparedPlanCache,
        ) !void {
            _ = thread;
            _ = job;
            _ = prepared;
            const ctx: *Ctx = @ptrCast(@alignCast(ctx_ptr.?));
            ctx.executed += 1;
        }
    };

    var engine = Engine.init(std.testing.allocator, .{});
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

    var thread = try engine.createThreadContext("batch-thread");
    defer thread.deinit();
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
