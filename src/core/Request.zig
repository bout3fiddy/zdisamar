const SceneModel = @import("../model/Scene.zig");

pub const DiagnosticsSpec = struct {
    provenance: bool = true,
    jacobians: bool = false,
    internal_fields: bool = false,
    materialize_cache_keys: bool = false,
};

pub const Request = struct {
    scene: SceneModel.Scene,
    requested_products: []const []const u8 = &[_][]const u8{},
    diagnostics: DiagnosticsSpec = .{},

    pub fn init(scene: SceneModel.Scene) Request {
        return .{ .scene = scene };
    }
};
