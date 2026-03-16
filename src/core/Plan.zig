const SceneModel = @import("../model/Scene.zig");
const PluginRegistry = @import("../plugins/registry/CapabilityRegistry.zig");
const PluginRuntime = @import("../plugins/loader/runtime.zig");
const PluginProviders = @import("../plugins/providers/root.zig");
const PluginSelection = @import("../plugins/selection.zig");
const PreparedPlanCache = @import("../runtime/cache/PreparedPlanCache.zig").PreparedPlanCache;
const TransportRoute = @import("../kernels/transport/common.zig").Route;
const std = @import("std");
const errors = @import("errors.zig");

pub const SolverMode = enum {
    scalar,
    polarized,
    derivative_enabled,
};

pub const Template = struct {
    model_family: []const u8 = "disamar_standard",
    providers: PluginSelection.ProviderSelection = .{},
    solver_mode: SolverMode = .scalar,
    scene_blueprint: SceneModel.Blueprint = .{},

    pub fn validate(self: Template) errors.TemplateError!void {
        if (self.model_family.len == 0) {
            return errors.TemplateError.MissingModelFamily;
        }
        if (self.providers.transport_solver.len == 0) {
            return errors.TemplateError.MissingTransportRoute;
        }
    }
};

pub const Plan = struct {
    allocator: std.mem.Allocator,
    id: u64,
    template: Template,
    transport_route: TransportRoute,
    prepared_cache: PreparedPlanCache = .{},
    plugin_snapshot: PluginRegistry.PluginSnapshot = .{},
    plugin_runtime: PluginRuntime.PreparedPluginRuntime = PluginRuntime.PreparedPluginRuntime.init(),
    providers: PluginProviders.PreparedProviders = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        id: u64,
        template: Template,
        transport_route: TransportRoute,
        prepared_cache: PreparedPlanCache,
        plugin_snapshot: PluginRegistry.PluginSnapshot,
        plugin_runtime: PluginRuntime.PreparedPluginRuntime,
        providers: PluginProviders.PreparedProviders,
    ) Plan {
        return .{
            .allocator = allocator,
            .id = id,
            .template = template,
            .transport_route = transport_route,
            .prepared_cache = prepared_cache,
            .plugin_snapshot = plugin_snapshot,
            .plugin_runtime = plugin_runtime,
            .providers = providers,
        };
    }

    pub fn deinit(self: *Plan) void {
        self.plugin_runtime.deinit(self.allocator);
        self.plugin_snapshot.deinit(self.allocator);
        self.* = undefined;
    }
};

// Keep the public lifecycle name explicit even though the concrete type stays `Plan`.
pub const PreparedPlan = Plan;

test "plan template validates existing provider selection" {
    try (Template{
        .providers = .{ .transport_solver = "builtin.dispatcher" },
    }).validate();
}
