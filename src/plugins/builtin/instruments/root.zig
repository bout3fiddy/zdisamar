const Manifest = @import("../../loader/manifest.zig");
const Slots = @import("../../slots.zig");

pub const generic_response_manifest: Manifest.PluginManifest = .{
    .id = "builtin.generic_response",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{
            .slot = Slots.instrument_response,
            .name = "builtin.generic_response",
        },
    },
};
