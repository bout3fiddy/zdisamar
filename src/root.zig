const std = @import("std");

pub const Engine = @import("core/Engine.zig").Engine;
pub const EngineOptions = @import("core/Engine.zig").EngineOptions;
pub const Catalog = @import("core/Catalog.zig").Catalog;
pub const Plan = @import("core/Plan.zig").Plan;
pub const PlanTemplate = @import("core/Plan.zig").Template;
pub const SolverMode = @import("core/Plan.zig").SolverMode;
pub const Request = @import("core/Request.zig").Request;
pub const DiagnosticsSpec = @import("core/Request.zig").DiagnosticsSpec;
pub const Result = @import("core/Result.zig").Result;
pub const Workspace = @import("core/Workspace.zig").Workspace;
pub const Scene = @import("model/Scene.zig").Scene;
pub const SceneBlueprint = @import("model/Scene.zig").Blueprint;
pub const Provenance = @import("core/provenance.zig").Provenance;
pub const PluginManifest = @import("plugins/loader/manifest.zig").PluginManifest;
pub const c_api = @import("api/c/bridge.zig");

test "engine scaffold prepares a plan and returns provenance" {
    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();

    const plan = try engine.preparePlan(.{});
    var workspace = engine.createWorkspace("unit");
    const request = Request.init(.{ .id = "scene-unit" });
    const result = try engine.execute(&plan, &workspace, request);

    try std.testing.expectEqual(Result.Status.success, result.status);
    try std.testing.expectEqual(@as(u64, 1), result.plan_id);
    try std.testing.expectEqualStrings("scene-unit", result.scene_id);
}
