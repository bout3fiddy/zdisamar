const std = @import("std");
const SceneModel = @import("../../model/Scene.zig");
const layout = @import("../../model/layout/root.zig");

pub const PreparedLayout = struct {
    layout_requirements: SceneModel.LayoutRequirements = .{},
    spectral_axis: ?layout.Axes.SpectralAxis = null,
    layer_axis: ?layout.Axes.LayerAxis = null,
    state_axis: ?layout.Axes.StateAxis = null,
    measurement_capacity: u32 = 0,
    dataset_hash_count: u32 = 0,

    pub fn initFromBlueprint(
        blueprint: SceneModel.Blueprint,
        dataset_hash_count: u32,
    ) !PreparedLayout {
        const layout_requirements = blueprint.layoutRequirements();

        return .{
            .layout_requirements = layout_requirements,
            .spectral_axis = if (layout_requirements.spectral_sample_count >= 2)
                .{
                    .start_nm = layout_requirements.spectral_start_nm,
                    .end_nm = layout_requirements.spectral_end_nm,
                    .sample_count = layout_requirements.spectral_sample_count,
                }
            else
                null,
            .layer_axis = if (layout_requirements.layer_count > 0)
                .{ .layer_count = layout_requirements.layer_count }
            else
                null,
            .state_axis = if (layout_requirements.state_parameter_count > 0)
                .{ .parameter_count = layout_requirements.state_parameter_count }
            else
                null,
            .measurement_capacity = layout_requirements.measurement_count,
            .dataset_hash_count = dataset_hash_count,
        };
    }
};

test "prepared layout derives reusable layout hints from the scene blueprint" {
    const cache = try PreparedLayout.initFromBlueprint(.{
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
        .layer_count_hint = 48,
        .state_parameter_count_hint = 3,
        .measurement_count_hint = 121,
    }, 2);

    try std.testing.expectEqual(@as(u32, 48), cache.layout_requirements.layer_count);
    try std.testing.expectEqual(@as(u32, 3), cache.layout_requirements.state_parameter_count);
    try std.testing.expectEqual(@as(u32, 121), cache.measurement_capacity);
    try std.testing.expectEqual(@as(u32, 2), cache.dataset_hash_count);
    try std.testing.expect(cache.spectral_axis != null);
    try std.testing.expect(cache.layer_axis != null);
    try std.testing.expect(cache.state_axis != null);
}

test "runtime cache package includes layout and cache implementations" {
    _ = @import("DatasetCache.zig");
    _ = @import("LUTCache.zig");
    _ = @import("PlanCache.zig");
}
