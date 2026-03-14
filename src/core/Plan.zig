const SceneModel = @import("../model/Scene.zig");
const PluginRegistry = @import("../plugins/registry/CapabilityRegistry.zig");
const PreparedPlanCache = @import("../runtime/cache/PreparedPlanCache.zig").PreparedPlanCache;
const TransportRoute = @import("../kernels/transport/common.zig").Route;
const errors = @import("errors.zig");

pub const SolverMode = enum {
    scalar,
    polarized,
    derivative_enabled,
};

pub const Template = struct {
    model_family: []const u8 = "disamar_standard",
    transport: []const u8 = "transport.dispatcher",
    retrieval: ?[]const u8 = null,
    solver_mode: SolverMode = .scalar,
    scene_blueprint: SceneModel.Blueprint = .{},

    pub fn validate(self: Template) errors.Error!void {
        if (self.model_family.len == 0) {
            return errors.Error.MissingModelFamily;
        }
        if (self.transport.len == 0) {
            return errors.Error.MissingTransportRoute;
        }
    }
};

pub const Plan = struct {
    id: u64,
    template: Template,
    transport_route: TransportRoute,
    prepared_cache: PreparedPlanCache = .{},
    plugin_snapshot: PluginRegistry.PluginSnapshot = .{},
    prepared: bool = true,

    pub fn init(
        id: u64,
        template: Template,
        transport_route: TransportRoute,
        prepared_cache: PreparedPlanCache,
        plugin_snapshot: PluginRegistry.PluginSnapshot,
    ) Plan {
        return .{
            .id = id,
            .template = template,
            .transport_route = transport_route,
            .prepared_cache = prepared_cache,
            .plugin_snapshot = plugin_snapshot,
        };
    }

    pub fn assertReady(self: *const Plan) errors.Error!void {
        if (!self.prepared) {
            return errors.Error.InvalidPlan;
        }
    }
};
