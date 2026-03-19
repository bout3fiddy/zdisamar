const std = @import("std");

const Catalog = @import("Catalog.zig").Catalog;
const PlanModule = @import("Plan.zig");
const PreparedPlan = PlanModule.PreparedPlan;
const Request = @import("Request.zig").Request;
const Result = @import("Result.zig").Result;
const Workspace = @import("Workspace.zig").Workspace;
const Provenance = @import("provenance.zig").Provenance;
const Scene = @import("../model/Scene.zig").Scene;
const MeasurementQuantity = @import("../model/Measurement.zig").Quantity;
const errors = @import("errors.zig");
const PluginManifest = @import("../plugins/loader/manifest.zig").PluginManifest;
const CapabilityRegistry = @import("../plugins/registry/CapabilityRegistry.zig").CapabilityRegistry;
const PluginRuntime = @import("../plugins/loader/runtime.zig");
const PluginProviders = @import("../plugins/providers/root.zig");
const DatasetCache = @import("../runtime/cache/DatasetCache.zig").DatasetCache;
const LUTCache = @import("../runtime/cache/LUTCache.zig").LUTCache;
const PlanCache = @import("../runtime/cache/PlanCache.zig").PlanCache;
const PreparedLayout = @import("../runtime/cache/PreparedLayout.zig").PreparedLayout;
const BatchRunnerModule = @import("../runtime/scheduler/BatchRunner.zig");
const BatchRunner = BatchRunnerModule.BatchRunner;
const BatchJob = BatchRunnerModule.BatchJob;
const ThreadContext = @import("../runtime/scheduler/ThreadContext.zig").ThreadContext;
const TransportCommon = @import("../kernels/transport/common.zig");
const MeasurementSpace = @import("../kernels/transport/measurement_space.zig");
const MeasurementSpaceProduct = MeasurementSpace.MeasurementSpaceProduct;
const RetrievalContracts = @import("../retrieval/common/contracts.zig");
const RetrievalForwardModel = @import("../retrieval/common/forward_model.zig");
const RetrievalStateAccess = @import("../retrieval/common/state_access.zig");
const Logging = @import("logging.zig");

pub const EngineOptions = struct {
    abi_version: u32 = 1,
    allow_native_plugins: bool = false,
    // Cache capacity for prepared-plan reuse. This is not a lifetime-total cap.
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

    pub fn preparePlan(self: *Engine, template: PlanModule.Template) errors.PreparationError!PreparedPlan {
        if (!self.catalog.bootstrapped) {
            return errors.PreparationError.CatalogNotBootstrapped;
        }

        try template.validate();

        if (!self.catalog.supportsModelFamily(template.model_family)) {
            return errors.PreparationError.UnsupportedModelFamily;
        }

        const providers = try resolvePlanProviders(template);
        const transport_route = try prepareTransportRoute(template, providers);
        var plugin_state = try preparePluginState(self, template);
        defer plugin_state.cleanupOnFailure(self.allocator);
        const dataset_hash_count = @max(
            plugin_state.snapshot.datasetHashes().len,
            self.dataset_cache.count(),
        );
        const prepared_layout = try PreparedLayout.initFromBlueprint(
            template.scene_blueprint,
            @intCast(dataset_hash_count),
        );
        var plan = PreparedPlan.init(
            self.allocator,
            self.next_plan_id,
            template,
            transport_route,
            prepared_layout,
            plugin_state.snapshot,
            plugin_state.runtime,
            providers,
        );
        errdefer plan.deinit();
        plugin_state = .{};
        self.plan_cache.put(plan.id, prepared_layout) catch |err| switch (err) {
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

    pub fn createThreadContext(self: *Engine, label: []const u8) ThreadContext {
        _ = self;
        return ThreadContext.init(label);
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

    pub fn execute(self: *Engine, plan: *const PreparedPlan, workspace: *Workspace, request: *const Request) errors.Error!Result {
        try request.validateForPlan(plan);

        plan.plugin_runtime.executeForRequest(.{
            .plan_id = plan.id,
            .scene_id = request.scene.id,
            .workspace_label = workspace.label,
            .requested_product_count = @intCast(request.requested_products.len),
        }) catch |err| return mapPluginExecutionError(err);
        try workspace.beginExecution(plan.id);
        workspace.prepareScratch(&plan.prepared_layout);
        _ = self.plan_cache.markRun(plan.id);

        var result: Result = undefined;
        try initializeResult(self, plan, workspace, request, &result);
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
    if (template.solver_mode == .derivative_enabled) {
        return errors.PreparationError.UnsupportedExecutionMode;
    }
    return providers.transport.prepareRoute(.{
        .regime = template.scene_blueprint.observation_regime,
        .execution_mode = transportExecutionMode(template.solver_mode),
        .derivative_mode = template.scene_blueprint.derivative_mode,
        .rtm_controls = template.rtm_controls,
    }) catch |err| switch (err) {
        error.UnsupportedDerivativeMode => return errors.PreparationError.UnsupportedDerivativeMode,
        error.UnsupportedExecutionMode => return errors.PreparationError.UnsupportedExecutionMode,
        error.UnsupportedRtmControls => return errors.PreparationError.UnsupportedRtmControls,
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

    runtime.resolveSnapshot(self.allocator, &snapshot, self.options.allow_native_plugins) catch |err| switch (err) {
        error.MissingNativeSource => return errors.PreparationError.MissingNativeSource,
        error.PluginEntryIncompatibleAbi => return errors.PreparationError.PluginEntryIncompatibleAbi,
        else => return errors.PreparationError.PluginPrepareFailed,
    };
    runtime.prepareForPlan(.{
        .plan_id = self.next_plan_id,
        .model_family = template.model_family,
        .transport_provider = template.providers.transport_solver,
        .solver_mode = @tagName(template.solver_mode),
    }) catch |err| switch (err) {
        error.MissingPrepareHook => return errors.PreparationError.MissingPrepareHook,
        error.PluginEntryIncompatibleAbi => return errors.PreparationError.PluginEntryIncompatibleAbi,
        error.PluginPrepareRejected => return errors.PreparationError.PluginPrepareRejected,
        else => return errors.PreparationError.PluginPrepareFailed,
    };

    return .{
        .snapshot = snapshot,
        .runtime = runtime,
    };
}

fn mapPluginExecutionError(err: PluginRuntime.Error) errors.ExecutionError {
    return switch (err) {
        error.MissingExecuteHook => errors.ExecutionError.MissingExecuteHook,
        error.PluginEntryIncompatibleAbi => errors.ExecutionError.PluginEntryIncompatibleAbi,
        else => errors.ExecutionError.PluginExecutionFailed,
    };
}

fn initializeResult(
    self: *Engine,
    plan: *const PreparedPlan,
    workspace: *Workspace,
    request: *const Request,
    result: *Result,
) errors.ExecutionError!void {
    var provenance: Provenance = undefined;
    Provenance.fromPlanOwned(
        &provenance,
        self.allocator,
        plan,
        workspace.label,
        request.scene.id,
        @tagName(plan.template.solver_mode),
    ) catch |err| return err;
    errdefer provenance.deinit(self.allocator);

    try result.initOwned(
        self.allocator,
        plan.id,
        workspace.label,
        request.scene.id,
        provenance,
    );
}

fn executeForwardProducts(
    self: *Engine,
    plan: *const PreparedPlan,
    request: *const Request,
    result: *Result,
) errors.ExecutionError!void {
    var prepared_optics = plan.providers.optics.prepareForScene(self.allocator, &request.scene) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return errors.ExecutionError.InvalidRequest,
    };
    defer prepared_optics.deinit(self.allocator);

    const measurement_space_product = MeasurementSpace.simulateProduct(
        self.allocator,
        &request.scene,
        plan.transport_route,
        &prepared_optics,
        measurementProviders(plan),
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return errors.ExecutionError.InvalidRequest,
    };
    result.attachMeasurementSpaceProduct(measurement_space_product);
}

fn executeRetrievalIfRequested(
    self: *Engine,
    plan: *const PreparedPlan,
    request: *const Request,
    result: *Result,
) errors.ExecutionError!void {
    if (request.inverse_problem == null) return;

    const retrieval_provider = plan.providers.retrieval orelse return errors.ExecutionError.InvalidRequest;
    var summary_workspace: MeasurementSpace.SummaryWorkspace = .{};
    defer summary_workspace.deinit(self.allocator);
    const retrieval_problem = RetrievalContracts.RetrievalProblem.fromRequest(request) catch {
        return errors.ExecutionError.InvalidRequest;
    };
    const retrieval_context: RetrievalExecutionContext = .{
        .allocator = self.allocator,
        .plan = plan,
        .summary_workspace = &summary_workspace,
    };
    var retrieval_outcome = retrieval_provider.solve(self.allocator, retrieval_problem, .{
        .context = @ptrCast(&retrieval_context),
        .evaluateSummary = evaluateRetrievalSceneSummary,
        .evaluateProduct = evaluateRetrievalSceneProduct,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return errors.ExecutionError.InvalidRequest,
    };
    errdefer retrieval_outcome.deinit(self.allocator);
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
        .scalar => .scalar,
        .derivative_enabled => unreachable,
    };
}

fn measurementProviders(plan: *const PreparedPlan) MeasurementSpace.ProviderBindings {
    return .{
        .transport = plan.providers.transport,
        .surface = plan.providers.surface,
        .instrument = plan.providers.instrument,
        .noise = plan.providers.noise,
    };
}

const RetrievalExecutionContext = struct {
    allocator: std.mem.Allocator,
    plan: *const PreparedPlan,
    summary_workspace: *MeasurementSpace.SummaryWorkspace,
};

fn evaluateRetrievalSceneSummary(context: *const anyopaque, scene: Scene) anyerror!MeasurementSpace.MeasurementSpaceSummary {
    const typed_context: *const RetrievalExecutionContext = @ptrCast(@alignCast(context));

    var prepared_optics = try typed_context.plan.providers.optics.prepareForScene(typed_context.allocator, &scene);
    defer prepared_optics.deinit(typed_context.allocator);

    return MeasurementSpace.simulateSummaryWithWorkspace(
        typed_context.allocator,
        typed_context.summary_workspace,
        &scene,
        typed_context.plan.transport_route,
        &prepared_optics,
        measurementProviders(typed_context.plan),
    );
}

fn evaluateRetrievalSceneProduct(
    allocator: std.mem.Allocator,
    context: *const anyopaque,
    scene: Scene,
) anyerror!MeasurementSpaceProduct {
    const typed_context: *const RetrievalExecutionContext = @ptrCast(@alignCast(context));

    var prepared_optics = try typed_context.plan.providers.optics.prepareForScene(allocator, &scene);
    defer prepared_optics.deinit(allocator);

    return MeasurementSpace.simulateProduct(
        allocator,
        &scene,
        typed_context.plan.transport_route,
        &prepared_optics,
        measurementProviders(typed_context.plan),
    );
}

fn materializeRetrievalProducts(
    allocator: std.mem.Allocator,
    plan: *const PreparedPlan,
    problem: RetrievalContracts.RetrievalProblem,
    outcome: RetrievalContracts.SolverOutcome,
) !Result.RetrievalProducts {
    const fitted_scene = outcome.fitted_scene orelse return error.InvalidRequest;

    var prepared_optics = try plan.providers.optics.prepareForScene(allocator, &fitted_scene);
    defer prepared_optics.deinit(allocator);

    var fitted_measurement = try MeasurementSpace.simulateProduct(
        allocator,
        &fitted_scene,
        plan.transport_route,
        &prepared_optics,
        measurementProviders(plan),
    );
    errdefer fitted_measurement.deinit(allocator);

    const state_vector = try materializeStateVectorProduct(allocator, problem, outcome);
    errdefer {
        var owned = state_vector;
        owned.deinit(allocator);
    }

    const jacobian = if (outcome.jacobian) |matrix|
        try materializeMatrixProduct(allocator, problem, matrix)
    else if (outcome.method.classification() == .surrogate and outcome.jacobians_used)
        try materializeSurrogateJacobianProduct(
            allocator,
            plan,
            problem,
            outcome,
            fitted_measurement,
        )
    else
        null;
    errdefer if (jacobian) |product| {
        var owned = product;
        owned.deinit(allocator);
    };

    const averaging_kernel = if (outcome.averaging_kernel) |matrix|
        try materializeMatrixProduct(allocator, problem, matrix)
    else
        null;
    errdefer if (averaging_kernel) |kernel| {
        var owned = kernel;
        owned.deinit(allocator);
    };

    const posterior_covariance = if (outcome.posterior_covariance) |matrix|
        try materializeMatrixProduct(allocator, problem, matrix)
    else
        null;
    errdefer if (posterior_covariance) |matrix| {
        var owned = matrix;
        owned.deinit(allocator);
    };

    if (outcome.method == .oe and
        (jacobian == null or averaging_kernel == null or posterior_covariance == null))
    {
        return error.InvalidRequest;
    }

    return .{
        .state_vector = state_vector,
        .fitted_measurement = fitted_measurement,
        .averaging_kernel = averaging_kernel,
        .jacobian = jacobian,
        .posterior_covariance = posterior_covariance,
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

fn materializeMatrixProduct(
    allocator: std.mem.Allocator,
    problem: RetrievalContracts.RetrievalProblem,
    matrix: RetrievalContracts.SolverOutcome.Matrix,
) !Result.RetrievalMatrixProduct {
    const parameter_names = try duplicateParameterNames(allocator, problem);
    errdefer freeStringSlice(allocator, parameter_names);

    const values = try allocator.dupe(f64, matrix.values);
    errdefer allocator.free(values);

    return .{
        .row_count = matrix.row_count,
        .column_count = matrix.column_count,
        .parameter_names = parameter_names,
        .values = values,
    };
}

fn materializeSurrogateJacobianProduct(
    allocator: std.mem.Allocator,
    plan: *const PreparedPlan,
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

        const perturbed_scene = try RetrievalStateAccess.sceneForState(problem, perturbed_values);
        var prepared_optics = try plan.providers.optics.prepareForScene(allocator, &perturbed_scene);
        defer prepared_optics.deinit(allocator);

        var perturbed_product = try MeasurementSpace.simulateProduct(
            allocator,
            &perturbed_scene,
            plan.transport_route,
            &prepared_optics,
            measurementProviders(plan),
        );
        defer perturbed_product.deinit(allocator);

        for (0..sample_count) |sample_index| {
            const base_value = try measurementValue(fitted_measurement, observable, sample_index);
            const perturbed_value = try measurementValue(perturbed_product, observable, sample_index);
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

fn duplicateParameterNames(
    allocator: std.mem.Allocator,
    problem: RetrievalContracts.RetrievalProblem,
) ![]const []const u8 {
    const state_vector = problem.inverse_problem.state_vector;
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

fn measurementObservable(problem: RetrievalContracts.RetrievalProblem) MeasurementQuantity {
    return problem.inverse_problem.measurements.observable;
}

fn measurementValue(product: MeasurementSpaceProduct, observable: MeasurementQuantity, index: usize) errors.Error!f64 {
    return switch (observable) {
        .radiance => product.radiance[index],
        .irradiance => product.irradiance[index],
        .reflectance => product.reflectance[index],
        .slant_column => errors.Error.InvalidRequest,
    };
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

    var second_plan = try engine.preparePlan(.{});
    defer second_plan.deinit();
    try std.testing.expectEqual(@as(u64, first_plan.id + 1), second_plan.id);
    try std.testing.expectEqual(@as(usize, 1), engine.plan_cache.count());
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
    var scalar_result = try engine.execute(&scalar_plan, &workspace, &request);
    defer scalar_result.deinit(std.testing.allocator);

    request.expected_derivative_mode = .semi_analytical;
    try std.testing.expectError(errors.Error.DerivativeModeMismatch, engine.execute(&scalar_plan, &workspace, &request));
    var workspace_mismatch_request = Request.init(scene);
    try std.testing.expectError(errors.Error.WorkspacePlanMismatch, engine.execute(&derivative_plan, &workspace, &workspace_mismatch_request));
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

    var missing_scene_request = Request.init(.{
        .id = "",
        .spectral_grid = .{ .sample_count = 8 },
    });
    try std.testing.expectError(
        errors.Error.MissingScene,
        engine.execute(&first_plan, &workspace, &missing_scene_request),
    );
    try std.testing.expectEqual(@as(?u64, null), workspace.bound_plan_id);
    try std.testing.expectEqual(@as(u64, 0), workspace.execution_count);
    try std.testing.expectEqual(@as(u64, 0), workspace.scratch.reserve_count);

    var post_error_request = Request.init(.{
        .id = "scene-after-error",
        .spectral_grid = .{ .sample_count = 8 },
    });
    var result = try engine.execute(&second_plan, &workspace, &post_error_request);
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
            .instrument = .synthetic,
        },
    });
    request.expected_derivative_mode = .semi_analytical;
    request.inverse_problem = .{
        .id = "inverse-missing-binding",
        .state_vector = .{
            .parameters = &[_]@import("../model/Scene.zig").StateParameter{
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

    try std.testing.expectError(errors.Error.InvalidRequest, engine.execute(&plan, &workspace, &request));
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
    var first_result = try engine.execute(&first_plan, &workspace, &request);
    defer first_result.deinit(std.testing.allocator);
    workspace.reset();
    var second_result = try engine.execute(&second_plan, &workspace, &request);
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
    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(Result.Status.success, result.status);
    try std.testing.expectEqual(@as(usize, 0), result.provenance.native_capability_slots.len);
    try std.testing.expectEqualStrings("builtin.dispatcher", result.provenance.solver_route);
    try std.testing.expect(result.measurement_space != null);
}

test "preparePlan releases resources when plan cache insertion fails" {
    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();
    engine.plan_cache.options.max_entries = 0;

    try std.testing.expectError(errors.PreparationError.PreparedPlanLimitExceeded, engine.preparePlan(.{}));
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
            .parameters = &[_]@import("../model/Scene.zig").StateParameter{
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
            .parameters = &[_]@import("../model/Scene.zig").StateParameter{
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

    try std.testing.expectError(errors.Error.InvalidRequest, engine.execute(&plan, &workspace, &request));
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
