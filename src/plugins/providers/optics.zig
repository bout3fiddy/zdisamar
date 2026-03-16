const std = @import("std");
const Allocator = std.mem.Allocator;
const Scene = @import("../../model/Scene.zig").Scene;
const PreparedOpticalState = @import("../../kernels/optics/prepare.zig").PreparedOpticalState;
const BundledOptics = @import("../../runtime/reference/BundledOptics.zig");

pub const Provider = struct {
    id: []const u8,
    prepareForScene: *const fn (allocator: Allocator, scene: Scene) anyerror!PreparedOpticalState,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.cross_sections")) {
        return .{
            .id = provider_id,
            .prepareForScene = BundledOptics.prepareForScene,
        };
    }
    return null;
}
