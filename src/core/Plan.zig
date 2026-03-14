const SceneModel = @import("../model/Scene.zig");

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
};

pub const Plan = struct {
    id: u64,
    template: Template,

    pub fn init(id: u64, template: Template) Plan {
        return .{
            .id = id,
            .template = template,
        };
    }
};
