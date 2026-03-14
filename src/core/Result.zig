const Provenance = @import("provenance.zig").Provenance;

pub const Result = struct {
    pub const Status = enum {
        success,
        invalid_request,
        internal_error,
    };

    pub const Diagnostics = struct {
        summary: []const u8 = "",
    };

    status: Status = .success,
    plan_id: u64,
    workspace_label: []const u8,
    scene_id: []const u8,
    provenance: Provenance = .{},
    diagnostics: Diagnostics = .{},

    pub fn init(
        plan_id: u64,
        workspace_label: []const u8,
        scene_id: []const u8,
        model_family: []const u8,
        numerical_mode: []const u8,
    ) Result {
        return .{
            .plan_id = plan_id,
            .workspace_label = workspace_label,
            .scene_id = scene_id,
            .provenance = .{
                .model_family = model_family,
                .solver_route = "transport.dispatcher",
                .numerical_mode = numerical_mode,
                .plan_id = plan_id,
                .workspace_label = workspace_label,
                .scene_id = scene_id,
            },
            .diagnostics = .{
                .summary = "Scaffold execution path only; transport and retrieval kernels are not wired yet.",
            },
        };
    }
};
