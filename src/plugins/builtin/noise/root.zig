const Manifest = @import("../../loader/manifest.zig");
const Slots = @import("../../slots.zig");

pub const scene_noise_manifest: Manifest.PluginManifest = .{
    .id = "builtin.scene_noise",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{ .slot = Slots.noise_model, .name = "builtin.scene_noise" },
    },
};

pub const none_noise_manifest: Manifest.PluginManifest = .{
    .id = "builtin.none_noise",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{ .slot = Slots.noise_model, .name = "builtin.none_noise" },
    },
};

pub const shot_noise_manifest: Manifest.PluginManifest = .{
    .id = "builtin.shot_noise",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{ .slot = Slots.noise_model, .name = "builtin.shot_noise" },
    },
};

pub const s5p_operational_noise_manifest: Manifest.PluginManifest = .{
    .id = "builtin.s5p_operational_noise",
    .package = "mission_s5p",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{ .slot = Slots.noise_model, .name = "builtin.s5p_operational_noise" },
    },
};
