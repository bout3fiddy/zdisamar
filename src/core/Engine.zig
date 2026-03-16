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
const MeasurementSpaceProduct = MeasurementSpace.MeasurementSpaceProduct;
const RetrievalContracts = @import("../retrieval/common/contracts.zig");
const RetrievalForwardModel = @import("../retrieval/common/forward_model.zig");
const RetrievalSurrogateForward = @import("../retrieval/common/synthetic_forward.zig");
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

    pub fn preparePlan(self: *Engine, template: PlanModule.Template) errors.PreparationError!Plan {
        if (!self.catalog.bootstrapped) {
            return errors.PreparationError.CatalogNotBootstrapped;
        }

        try template.validate();

        if (!self.catalog.supportsModelFamily(template.model_family)) {
            return errors.PreparationError.UnsupportedModelFamily;
        }

        if (self.next_plan_id > self.options.max_prepared_plans) {
            return errors.PreparationError.PreparedPlanLimitExceeded;
        }

        const providers = try resolvePlanProviders(template);
        const transport_route = try prepareTransportRoute(template, providers);
        var plugin_state = try preparePluginState(self, template);
        defer plugin_state.cleanupOnFailure(self.allocator);
        const dataset_hash_count = @max(
            plugin_state.snapshot.datasetHashes().len,
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
            plugin_state.snapshot,
            plugin_state.runtime,
            providers,
        );
        plugin_state = .{};
        self.plan_cache.put(plan.id, prepared_cache) catch |err| switch (err) {
            error.PlanCacheDisabled => return errors.PreparationError.PreparedPlanLimitExceeded,
            error.OutOfMemory => return errors.PreparationError.OutOfMemory,
        };
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

    pub fn execute(self: *Engine, plan: *const Plan, workspace: *Workspace, request: Request) errors.Error!Result {
        try request.validateForPlan(plan);

        plan.plugin_runtime.executeForRequest(.{
            .plan_id = plan.id,
            .scene_id = request.scene.id,
            .workspace_label = workspace.label,
            .requested_product_count = @intCast(request.requested_products.len),
        }) catch |err| return mapPluginExecutionError(err);
        try workspace.beginExecution(plan.id);
        workspace.prepareScratch(&plan.prepared_cache);
        _ = self.plan_cache.markRun(plan.id);

        var result = try initializeResult(self, plan, workspace, request);
        errdefer result.deinit(self.allocator);

        try executeForwardProducts(self, plan, request, &result);
        try executeRetrievalIfRequested(self, plan, request, &result);
        result.diagnostics = plan.providers.diagnostics.materialize(
            request.diagnostics,
            "Plugin-selected forward and retrieval providers executed with typed scene preparation and owned provenance.",
        );
        return result;
    }
};

const PluginPreparation = struct {
    snapshot: @import("../plugins/registry/CapabilityRegistry.zig").PluginSnapshot = .{},
    runtime: PluginRuntime.PreparedPluginRuntime = PluginRuntime.PreparedPluginRuntime.init(),

    fn cleanupOnFailure(self: *PluginPreparation, allocator: std.mem.Allocator) void {
        self.runtime.deinit(allocator);
        self.snapshot.deinit(allocator);
        self.* = .{};
    }
};

fn resolvePlanProviders(template: PlanModule.Template) errors.PreparationError!PluginProviders.PreparedProviders {
    return PluginProviders.PreparedProviders.resolve(template.providers) catch {
        return errors.PreparationError.UnsupportedCapability;
    };
}

fn prepareTransportRoute(
    template: PlanModule.Template,
    providers: PluginProviders.PreparedProviders,
) errors.PreparationError!TransportCommon.Route {
    return providers.transport.prepareRoute(.{
        .regime = template.scene_blueprint.observation_regime,
        .execution_mode = transportExecutionMode(template.solver_mode),
        .derivative_mode = template.scene_blueprint.derivative_mode,
    }) catch |err| switch (err) {
        error.UnsupportedDerivativeMode => return errors.PreparationError.UnsupportedDerivativeMode,
        error.UnsupportedExecutionMode => return errors.PreparationError.UnsupportedExecutionMode,
    };
}

fn preparePluginState(
    self: *Engine,
    template: PlanModule.Template,
) errors.PreparationError!PluginPreparation {
    var snapshot = self.registry.snapshotSelection(self.allocator, template.providers) catch {
        return errors.PreparationError.UnsupportedCapability;
    };
    errdefer snapshot.deinit(self.allocator);

    var runtime = PluginRuntime.PreparedPluginRuntime.init();
    errdefer runtime.deinit(self.allocator);

    runtime.resolveSnapshot(self.allocator, &snapshot, self.options.allow_native_plugins) catch {
        return errors.PreparationError.PluginPrepareFailed;
    };
    runtime.prepareForPlan(.{
        .plan_id = self.next_plan_id,
        .model_family = template.model_family,
        .transport_provider = template.providers.transport_solver,
        .solver_mode = @tagName(template.solver_mode),
    }) catch {
        return errors.PreparationError.PluginPrepareFailed;
    };

    return .{
        .snapshot = snapshot,
        .runtime = runtime,
    };
}

fn mapPluginExecutionError(_: PluginRuntime.Error) errors.ExecutionError {
    return errors.ExecutionError.PluginExecutionFailed;
}

fn initializeResult(
    self: *Engine,
    plan: *const Plan,
    workspace: *Workspace,
    request: Request,
) errors.ExecutionError!Result {
    var provenance = Provenance.fromPlan(
        self.allocator,
        plan,
        workspace.label,
        request.scene.id,
        @tagName(plan.template.solver_mode),
    ) catch |err| return err;
    errdefer provenance.deinit(self.allocator);

    return Result.init(
        plan.id,
        workspace.label,
        request.scene.id,
        provenance,
    );
}

fn executeForwardProducts(
    self: *Engine,
    plan: *const Plan,
    request: Request,
    result: *Result,
) errors.ExecutionError!void {
    var prepared_optics = plan.providers.optics.prepareForScene(self.allocator, request.scene) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return errors.ExecutionError.InvalidRequest,
    };
    defer prepared_optics.deinit(self.allocator);

    const measurement_space_product = MeasurementSpace.simulateProduct(
        self.allocator,
        request.scene,
        plan.transport_route,
        prepared_optics,
        measurementProviders(plan),
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return errors.ExecutionError.InvalidRequest,
    };
    result.attachMeasurementSpaceProduct(measurement_space_product);
}

fn executeRetrievalIfRequested(
    self: *Engine,
    plan: *const Plan,
    request: Request,
    result: *Result,
) errors.ExecutionError!void {
    if (request.inverse_problem == null) return;

    const retrieval_provider = plan.providers.retrieval orelse return errors.ExecutionError.InvalidRequest;
    var summary_workspace: MeasurementSpace.SummaryWorkspace = .{};
    defer summary_workspace.deinit(self.allocator);
    var retrieval_request = request;
    if (retrieval_request.measurement_binding == null and retrieval_request.inverse_problem != null) {
        const source = retrieval_request.inverse_problem.?.measurements.source;
        if (source.kind == .external_observation) {
            retrieval_request.measurement_binding = .{
                .source_name = if (source.name.len != 0) source.name else retrieval_request.inverse_problem.?.measurements.product,
                .observable = retrieval_request.inverse_problem.?.measurements.observable,
                .product = &result.measurement_space_product.?,
            };
        }
    }

    const retrieval_problem = RetrievalContracts.RetrievalProblem.fromRequest(retrieval_request) catch {
        return errors.ExecutionError.InvalidRequest;
    };
    const retrieval_context: RetrievalExecutionContext = .{
        .allocator = self.allocator,
        .plan = plan,
        .summary_workspace = &summary_workspace,
    };
    const retrieval_outcome = retrieval_provider.solve(self.allocator, retrieval_problem, .{
        .context = @ptrCast(&retrieval_context),
        .evaluate = evaluateRetrievalScene,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return errors.ExecutionError.InvalidRequest,
    };
    const retrieval_products = materializeRetrievalProducts(
        self.allocator,
        plan,
        retrieval_problem,
        retrieval_outcome,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return errors.ExecutionError.InvalidRequest,
    };
    result.attachRetrievalOutcome(retrieval_outcome);
    result.attachRetrievalProducts(retrieval_products);
}

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
    summary_workspace: *MeasurementSpace.SummaryWorkspace,
};

fn evaluateRetrievalScene(context: *const anyopaque, scene: Scene) anyerror!MeasurementSpace.MeasurementSpaceSummary {
    const typed_context: *const RetrievalExecutionContext = @ptrCast(@alignCast(context));

    var prepared_optics = try typed_context.plan.providers.optics.prepareForScene(typed_context.allocator, scene);
    defer prepared_optics.deinit(typed_context.allocator);

    return MeasurementSpace.simulateSummaryWithWorkspace(
        typed_context.allocator,
        typed_context.summary_workspace,
        scene,
        typed_context.plan.transport_route,
        prepared_optics,
        measurementProviders(typed_context.plan),
    );
}

fn materializeRetrievalProducts(
    allocator: std.mem.Allocator,
    plan: *const Plan,
    problem: RetrievalContracts.RetrievalProblem,
    outcome: RetrievalContracts.SolverOutcome,
) !Result.RetrievalProducts {
    const fitted_scene = outcome.fitted_scene orelse return error.InvalidRequest;

    var prepared_optics = try plan.providers.optics.prepareForScene(allocator, fitted_scene);
    defer prepared_optics.deinit(allocator);

    var fitted_measurement = try MeasurementSpace.simulateProduct(
        allocator,
        fitted_scene,
        plan.transport_route,
        prepared_optics,
        measurementProviders(plan),
    );
    errdefer fitted_measurement.deinit(allocator);

    const state_vector = try materializeStateVectorProduct(allocator, problem, outcome);
    errdefer {
        var owned = state_vector;
        owned.deinit(allocator);
    }

    const jacobian = try materializeJacobianProduct(
        allocator,
        plan,
        problem,
        outcome,
        fitted_measurement,
    );
    errdefer {
        var owned = jacobian;
        owned.deinit(allocator);
    }

    const averaging_kernel = try materializeAveragingKernelProduct(
        allocator,
        problem,
        outcome,
        jacobian,
    );
    errdefer {
        var owned = averaging_kernel;
        owned.deinit(allocator);
    }

    return .{
        .state_vector = state_vector,
        .fitted_measurement = fitted_measurement,
        .averaging_kernel = averaging_kernel,
        .jacobian = jacobian,
    };
}

fn materializeStateVectorProduct(
    allocator: std.mem.Allocator,
    problem: RetrievalContracts.RetrievalProblem,
    outcome: RetrievalContracts.SolverOutcome,
) !Result.RetrievalStateVectorProduct {
    const parameter_names = try duplicateParameterNames(allocator, problem);
    errdefer freeStringSlice(allocator, parameter_names);

    const values = try allocator.dupe(f64, outcome.state_estimate.values);
    errdefer allocator.free(values);

    return .{
        .parameter_names = parameter_names,
        .values = values,
    };
}

fn materializeJacobianProduct(
    allocator: std.mem.Allocator,
    plan: *const Plan,
    problem: RetrievalContracts.RetrievalProblem,
    outcome: RetrievalContracts.SolverOutcome,
    fitted_measurement: MeasurementSpaceProduct,
) !Result.RetrievalMatrixProduct {
    const parameter_names = try duplicateParameterNames(allocator, problem);
    errdefer freeStringSlice(allocator, parameter_names);

    const sample_count = fitted_measurement.wavelengths.len;
    const state_count = outcome.state_estimate.values.len;
    const values = try allocator.alloc(f64, sample_count * state_count);
    errdefer allocator.free(values);

    const observable = measurementObservable(problem);
    for (0..state_count) |state_index| {
        const perturbed_values = try allocator.dupe(f64, outcome.state_estimate.values);
        defer allocator.free(perturbed_values);

        const delta = jacobianStep(perturbed_values[state_index]);
        perturbed_values[state_index] += delta;

        const perturbed_scene = try RetrievalSurrogateForward.sceneForState(problem, perturbed_values);
        var prepared_optics = try plan.providers.optics.prepareForScene(allocator, perturbed_scene);
        defer prepared_optics.deinit(allocator);

        var perturbed_product = try MeasurementSpace.simulateProduct(
            allocator,
            perturbed_scene,
            plan.transport_route,
            prepared_optics,
            measurementProviders(plan),
        );
        defer perturbed_product.deinit(allocator);

        for (0..sample_count) |sample_index| {
            const base_value = measurementValue(fitted_measurement, observable, sample_index);
            const perturbed_value = measurementValue(perturbed_product, observable, sample_index);
            values[sample_index * state_count + state_index] = (perturbed_value - base_value) / delta;
        }
    }

    return .{
        .row_count = @intCast(sample_count),
        .column_count = @intCast(state_count),
        .parameter_names = parameter_names,
        .values = values,
    };
}

fn materializeAveragingKernelProduct(
    allocator: std.mem.Allocator,
    problem: RetrievalContracts.RetrievalProblem,
    outcome: RetrievalContracts.SolverOutcome,
    jacobian: Result.RetrievalMatrixProduct,
) !Result.RetrievalMatrixProduct {
    const parameter_names = try duplicateParameterNames(allocator, problem);
    errdefer freeStringSlice(allocator, parameter_names);

    const state_count = outcome.state_estimate.values.len;
    const values = try allocator.alloc(f64, state_count * state_count);
    errdefer allocator.free(values);
    @memset(values, 0.0);

    if (state_count != 0) {
        const dfs_per_state = outcome.dfs / @as(f64, @floatFromInt(state_count));
        for (0..state_count) |diag_index| {
            var column_energy: f64 = 0.0;
            for (0..jacobian.row_count) |row_index| {
                const derivative = jacobian.values[row_index * state_count + diag_index];
                column_energy += derivative * derivative;
            }
            values[diag_index * state_count + diag_index] = std.math.clamp(
                dfs_per_state + 0.02 * std.math.sqrt(column_energy),
                0.0,
                1.0,
            );
        }

        for (problem.inverse_problem.covariance_blocks) |block| {
            for (block.member_names, 0..) |lhs_name, lhs_index| {
                const lhs = parameterIndex(problem, lhs_name) orelse continue;
                for (block.member_names[lhs_index + 1 ..]) |rhs_name| {
                    const rhs = parameterIndex(problem, rhs_name) orelse continue;
                    const coupled = 0.1 * block.correlation;
                    values[lhs * state_count + rhs] = coupled;
                    values[rhs * state_count + lhs] = coupled;
                }
            }
        }
    }

    return .{
        .row_count = @intCast(state_count),
        .column_count = @intCast(state_count),
        .parameter_names = parameter_names,
        .values = values,
    };
}

fn duplicateParameterNames(
    allocator: std.mem.Allocator,
    problem: RetrievalContracts.RetrievalProblem,
) ![]const []const u8 {
    const state_vector = problem.inverse_problem.state_vector;
    if (state_vector.parameter_names.len != 0) {
        return duplicateStringSlice(allocator, state_vector.parameter_names);
    }
    if (state_vector.parameters.len == 0) return &[_][]const u8{};

    const names = try allocator.alloc([]const u8, state_vector.parameters.len);
    errdefer allocator.free(names);

    var copied: usize = 0;
    errdefer {
        for (names[0..copied]) |value| allocator.free(value);
    }
    for (state_vector.parameters, 0..) |parameter, index| {
        names[index] = try allocator.dupe(u8, parameter.name);
        copied = index + 1;
    }
    return names;
}

fn duplicateStringSlice(allocator: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
    const owned = try allocator.alloc([]const u8, values.len);
    errdefer allocator.free(owned);

    var copied: usize = 0;
    errdefer {
        for (owned[0..copied]) |value| allocator.free(value);
    }
    for (values, 0..) |value, index| {
        owned[index] = try allocator.dupe(u8, value);
        copied = index + 1;
    }
    return owned;
}

fn freeStringSlice(allocator: std.mem.Allocator, values: []const []const u8) void {
    if (values.len == 0) return;
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn parameterIndex(problem: RetrievalContracts.RetrievalProblem, name: []const u8) ?usize {
    const state_vector = problem.inverse_problem.state_vector;
    if (state_vector.parameter_names.len != 0) {
        for (state_vector.parameter_names, 0..) |parameter_name, index| {
            if (std.mem.eql(u8, parameter_name, name)) return index;
        }
    }
    for (state_vector.parameters, 0..) |parameter, index| {
        if (std.mem.eql(u8, parameter.name, name)) return index;
    }
    return null;
}

fn measurementObservable(problem: RetrievalContracts.RetrievalProblem) []const u8 {
    const observable = problem.inverse_problem.measurements.observable;
    if (observable.len != 0) return observable;
    return problem.inverse_problem.measurements.product;
}

fn measurementValue(product: MeasurementSpaceProduct, observable: []const u8, index: usize) f64 {
    if (std.mem.eql(u8, observable, "reflectance")) return product.reflectance[index];
    if (std.mem.eql(u8, observable, "irradiance")) return product.irradiance[index];
    return product.radiance[index];
}

fn jacobianStep(value: f64) f64 {
    return if (@abs(value) > 1.0e-6) 1.0e-3 * @abs(value) else 1.0e-3;
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

test "execute rejects retrieval stage-product requests without a bound measurement" {
    var engine = Engine.init(std.testing.allocator, .{});
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
    var request = Request.init(.{
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
            .instrument = "synthetic",
        },
    });
    request.expected_derivative_mode = .semi_analytical;
    request.inverse_problem = .{
        .id = "inverse-missing-binding",
        .state_vector = .{
            .parameters = &[_]@import("../model/Scene.zig").StateParameter{
                .{ .name = "surface_albedo", .target = "scene.surface.albedo" },
            },
        },
        .measurements = .{
            .product = "radiance",
            .observable = "radiance",
            .sample_count = 16,
            .source = .{ .kind = .stage_product, .name = "forward-stage" },
        },
    };

    try std.testing.expectError(errors.Error.InvalidRequest, engine.execute(&plan, &workspace, request));
    try std.testing.expectEqual(@as(?u64, null), workspace.bound_plan_id);
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

test "default builtin execution stays on typed providers when native plugins are disabled" {
    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{});
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 0), plan.plugin_runtime.native_plugins.len);
    try std.testing.expectEqual(@as(usize, 0), plan.plugin_snapshot.nativeCapabilitySlots().len);

    var workspace = engine.createWorkspace("typed-provider-only");
    const request = Request.init(.{
        .id = "scene-typed-provider-only",
        .spectral_grid = .{ .sample_count = 8 },
    });
    var result = try engine.execute(&plan, &workspace, request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(Result.Status.success, result.status);
    try std.testing.expectEqual(@as(usize, 0), result.provenance.native_capability_slots.len);
    try std.testing.expectEqualStrings("builtin.dispatcher", result.provenance.solver_route);
    try std.testing.expect(result.measurement_space != null);
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

test "engine retrieval execution uses summary evaluation and still materializes retrieval products separately" {
    var engine = Engine.init(std.testing.allocator, .{});
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
    var request = Request.init(.{
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
            .instrument = "synthetic",
            .regime = .nadir,
            .sampling = "operational",
            .noise_model = "shot_noise",
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
            .parameters = &[_]@import("../model/Scene.zig").StateParameter{
                .{ .name = "surface_albedo", .target = "scene.surface.albedo", .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.02 } },
                .{ .name = "aerosol_tau", .target = "scene.aerosols.plume.optical_depth_550_nm", .prior = .{ .enabled = true, .mean = 0.05, .sigma = 0.03 } },
            },
        },
        .measurements = .{
            .product = "radiance",
            .observable = "radiance",
            .sample_count = 24,
            .source = .{ .kind = .external_observation, .name = "forward-measurement" },
        },
    };

    var result = try engine.execute(&plan, &workspace, request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.measurement_space != null);
    try std.testing.expect(result.measurement_space_product != null);
    try std.testing.expect(result.retrieval != null);
    try std.testing.expect(result.retrieval.?.fitted_measurement != null);
    try std.testing.expect(result.retrieval_products.fitted_measurement != null);
    try std.testing.expect(result.retrieval_products.state_vector != null);
    try std.testing.expect(result.retrieval_products.jacobian != null);
    try std.testing.expectEqual(
        result.retrieval.?.fitted_measurement.?.sample_count,
        @as(u32, @intCast(result.retrieval_products.fitted_measurement.?.wavelengths.len)),
    );
}

test "engine translates retrieval-local invalid state targets into invalid requests" {
    var engine = Engine.init(std.testing.allocator, .{});
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
    var request = Request.init(.{
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
            .instrument = "synthetic",
            .regime = .nadir,
            .sampling = "operational",
            .noise_model = "shot_noise",
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
            .parameters = &[_]@import("../model/Scene.zig").StateParameter{
                .{ .name = "bad_target", .target = "scene.unknown.target" },
            },
        },
        .measurements = .{
            .product = "radiance",
            .observable = "radiance",
            .sample_count = 24,
            .source = .{ .kind = .external_observation, .name = "forward-measurement" },
        },
    };

    try std.testing.expectError(errors.Error.InvalidRequest, engine.execute(&plan, &workspace, request));
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
