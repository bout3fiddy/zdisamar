const Manifest = @import("../../loader/manifest.zig");
const Slots = @import("../../slots.zig");

pub const default_diagnostics_manifest: Manifest.PluginManifest = .{
    .id = "builtin.default_diagnostics",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{ .slot = Slots.diagnostics_metric, .name = "builtin.default_diagnostics" },
    },
};
