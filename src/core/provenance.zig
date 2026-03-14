pub const Provenance = struct {
    engine_version: []const u8 = "0.1.0-dev",
    model_family: []const u8 = "disamar_standard",
    solver_route: []const u8 = "transport.dispatcher",
    numerical_mode: []const u8 = "scalar",
    plan_id: u64 = 0,
    workspace_label: []const u8 = "",
    scene_id: []const u8 = "",
    plugin_versions: []const []const u8 = &[_][]const u8{},
    dataset_hashes: []const []const u8 = &[_][]const u8{},
};
