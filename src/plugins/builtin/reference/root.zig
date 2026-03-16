const Manifest = @import("../../loader/manifest.zig");
const Slots = @import("../../slots.zig");

pub const cross_sections_manifest: Manifest.PluginManifest = .{
    .id = "builtin.cross_sections",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{ .slot = Slots.absorber_provider, .name = "builtin.cross_sections" },
    },
    .provenance = .{
        .description = "Built-in spectroscopy data pack",
        .dataset_hashes = &[_][]const u8{
            "sha256:builtin-cross-sections-demo",
        },
    },
};
