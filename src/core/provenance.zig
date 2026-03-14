const Plan = @import("Plan.zig").Plan;

pub const Provenance = struct {
    engine_version: []const u8 = "0.1.0-dev",
    model_family: []const u8 = "disamar_standard",
    solver_route: []const u8 = "transport.dispatcher",
    transport_family: []const u8 = "adding",
    derivative_mode: []const u8 = "none",
    numerical_mode: []const u8 = "scalar",
    plan_id: u64 = 0,
    plugin_inventory_generation: u64 = 0,
    workspace_label: []const u8 = "",
    scene_id: []const u8 = "",
    plugin_versions: []const []const u8 = &[_][]const u8{},
    dataset_hashes: []const []const u8 = &[_][]const u8{},

    pub fn fromPlan(
        plan: *const Plan,
        workspace_label: []const u8,
        scene_id: []const u8,
        numerical_mode: []const u8,
    ) Provenance {
        return .{
            .model_family = plan.template.model_family,
            .solver_route = plan.template.transport,
            .transport_family = @tagName(plan.transport_route.family),
            .derivative_mode = @tagName(plan.transport_route.derivative_mode),
            .numerical_mode = numerical_mode,
            .plan_id = plan.id,
            .plugin_inventory_generation = plan.plugin_snapshot.generation,
            .workspace_label = workspace_label,
            .scene_id = scene_id,
            .plugin_versions = plan.plugin_snapshot.pluginVersions(),
            .dataset_hashes = plan.plugin_snapshot.datasetHashes(),
        };
    }
};
