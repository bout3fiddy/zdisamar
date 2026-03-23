const std = @import("std");

const Catalog = @import("../Catalog.zig").Catalog;
const PlanModule = @import("../Plan.zig");
const PreparedPlan = PlanModule.PreparedPlan;
const errors = @import("../errors.zig");
const CapabilityRegistry = @import("../../plugins/registry/CapabilityRegistry.zig").CapabilityRegistry;
const PluginRuntime = @import("../../plugins/loader/runtime.zig");
const PluginProviders = @import("../../plugins/providers/root.zig");
const DatasetCache = @import("../../runtime/cache/DatasetCache.zig").DatasetCache;
const PlanCache = @import("../../runtime/cache/PlanCache.zig").PlanCache;
const PreparedLayout = @import("../../runtime/cache/PreparedLayout.zig").PreparedLayout;
const TransportCommon = @import("../../kernels/transport/common.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    allow_native_plugins: bool,
    catalog: *Catalog,
    registry: *CapabilityRegistry,
    dataset_cache: *DatasetCache,
    plan_cache: *PlanCache,
    next_plan_id: *u64,
};

pub fn preparePlan(
    ctx: *Context,
    template: PlanModule.Template,
) errors.PreparationError!PreparedPlan {
    if (!ctx.catalog.bootstrapped) {
        return errors.PreparationError.CatalogNotBootstrapped;
    }

    try template.validate();

    if (!ctx.catalog.supportsModelFamily(template.model_family)) {
        return errors.PreparationError.UnsupportedModelFamily;
    }

    const providers = try resolvePlanProviders(template);
    const transport_route = try prepareTransportRoute(template, providers);
    var plugin_state = try preparePluginState(ctx, template);
    defer plugin_state.cleanupOnFailure(ctx.allocator);

    const dataset_hash_count = @max(
        plugin_state.snapshot.datasetHashes().len,
        ctx.dataset_cache.count(),
    );
    const prepared_layout = try PreparedLayout.initFromBlueprint(
        template.scene_blueprint,
        @intCast(dataset_hash_count),
    );
    var plan = PreparedPlan.init(
        ctx.allocator,
        ctx.next_plan_id.*,
        template,
        transport_route,
        prepared_layout,
        plugin_state.snapshot,
        plugin_state.runtime,
        providers,
    );
    errdefer plan.deinit();
    plugin_state = .{};
    ctx.plan_cache.put(plan.id, prepared_layout) catch |err| switch (err) {
        error.PlanCacheDisabled => return errors.PreparationError.PreparedPlanLimitExceeded,
        error.OutOfMemory => return errors.PreparationError.OutOfMemory,
    };
    ctx.next_plan_id.* += 1;
    return plan;
}

const PluginPreparation = struct {
    snapshot: @import("../../plugins/registry/CapabilityRegistry.zig").PluginSnapshot = .{},
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
    ctx: *Context,
    template: PlanModule.Template,
) errors.PreparationError!PluginPreparation {
    var snapshot = ctx.registry.snapshotSelection(ctx.allocator, template.providers) catch |err| switch (err) {
        error.OutOfMemory => return errors.PreparationError.OutOfMemory,
        else => return errors.PreparationError.UnsupportedCapability,
    };
    errdefer snapshot.deinit(ctx.allocator);

    var runtime = PluginRuntime.PreparedPluginRuntime.init();
    errdefer runtime.deinit(ctx.allocator);

    runtime.resolveSnapshot(ctx.allocator, &snapshot, ctx.allow_native_plugins) catch |err| switch (err) {
        error.MissingNativeSource => return errors.PreparationError.MissingNativeSource,
        error.PluginEntryIncompatibleAbi => return errors.PreparationError.PluginEntryIncompatibleAbi,
        else => return errors.PreparationError.PluginPrepareFailed,
    };
    runtime.prepareForPlan(.{
        .plan_id = ctx.next_plan_id.*,
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

fn transportExecutionMode(solver_mode: PlanModule.SolverMode) TransportCommon.ExecutionMode {
    return switch (solver_mode) {
        .polarized => .polarized,
        .scalar => .scalar,
        .derivative_enabled => unreachable,
    };
}
