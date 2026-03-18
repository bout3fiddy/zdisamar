const SceneModel = @import("../model/Scene.zig");
const PluginRegistry = @import("../plugins/registry/CapabilityRegistry.zig");
const PluginRuntime = @import("../plugins/loader/runtime.zig");
const PluginProviders = @import("../plugins/providers/root.zig");
const PluginSelection = @import("../plugins/selection.zig");
const PreparedLayout = @import("../runtime/cache/PreparedLayout.zig").PreparedLayout;
const TransportRoute = @import("../kernels/transport/common.zig").Route;
const std = @import("std");
const errors = @import("errors.zig");

pub const SolverMode = enum {
    scalar,
    polarized,
    derivative_enabled,
};

pub const Template = struct {
    // TODO(WP-01): model_family should be an enum (e.g. ModelFamily { disamar_standard })
    // instead of []const u8, but it has >15 call sites across core, adapters, api, plugins,
    // and exporters. Typed replacement deferred to avoid shotgun surgery.
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

pub const PreparedPlan = struct {
    allocator: std.mem.Allocator,
    id: u64,
    template: Template,
    transport_route: TransportRoute,
    prepared_layout: PreparedLayout = .{},
    plugin_snapshot: PluginRegistry.PluginSnapshot = .{},
    plugin_runtime: PluginRuntime.PreparedPluginRuntime = PluginRuntime.PreparedPluginRuntime.init(),
    providers: PluginProviders.PreparedProviders = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        id: u64,
        template: Template,
        transport_route: TransportRoute,
        prepared_layout: PreparedLayout,
        plugin_snapshot: PluginRegistry.PluginSnapshot,
        plugin_runtime: PluginRuntime.PreparedPluginRuntime,
        providers: PluginProviders.PreparedProviders,
    ) PreparedPlan {
        return .{
            .allocator = allocator,
            .id = id,
            .template = template,
            .transport_route = transport_route,
            .prepared_layout = prepared_layout,
            .plugin_snapshot = plugin_snapshot,
            .plugin_runtime = plugin_runtime,
            .providers = providers,
        };
    }

    pub fn deinit(self: *PreparedPlan) void {
        self.plugin_runtime.deinit(self.allocator);
        self.plugin_snapshot.deinit(self.allocator);
        self.* = undefined;
    }
};

test "plan template validates existing provider selection" {
    try (Template{
        .providers = .{ .transport_solver = "builtin.dispatcher" },
    }).validate();
}
