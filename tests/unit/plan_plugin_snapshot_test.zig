const std = @import("std");
const zdisamar = @import("zdisamar");

test "result provenance carries frozen plugin versions and dataset hashes from the plan" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{ .allow_native_plugins = true });
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();
    const plan_before = try engine.preparePlan(.{});

    try engine.registerPluginManifest(.{
        .id = "example.dataset_patch",
        .package = "disamar_standard",
        .version = "0.2.1",
        .lane = .declarative,
        .capabilities = &[_]zdisamar.PluginCapabilityDecl{
            .{ .slot = "data.pack", .name = "example.dataset_patch" },
        },
        .provenance = .{
            .dataset_hashes = &[_][]const u8{
                "sha256:example-dataset-patch",
            },
        },
    });

    const plan_after = try engine.preparePlan(.{});

    var workspace = engine.createWorkspace("unit-provenance");
    const request = zdisamar.Request.init(.{
        .id = "scene-provenance",
        .spectral_grid = .{ .sample_count = 8 },
    });

    var before_result = try engine.execute(&plan_before, &workspace, request);
    defer before_result.deinit(std.testing.allocator);
    workspace.reset();
    var after_result = try engine.execute(&plan_after, &workspace, request);
    defer after_result.deinit(std.testing.allocator);

    try std.testing.expect(after_result.provenance.plugin_inventory_generation > before_result.provenance.plugin_inventory_generation);
    try std.testing.expect(after_result.provenance.pluginVersionCount() > before_result.provenance.pluginVersionCount());
    try std.testing.expect(after_result.provenance.dataset_hashes.len > before_result.provenance.dataset_hashes.len);
    try std.testing.expectEqualStrings(
        "builtin.cross_sections@0.1.0",
        before_result.provenance.pluginVersionAt(0),
    );
}
