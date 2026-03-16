const Manifest = @import("../../loader/manifest.zig");
const Slots = @import("../../slots.zig");

pub const netcdf_cf_manifest: Manifest.PluginManifest = .{
    .id = "builtin.netcdf_cf",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{ .slot = Slots.exporter, .name = "builtin.netcdf_cf" },
    },
};

pub const zarr_manifest: Manifest.PluginManifest = .{
    .id = "builtin.zarr",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{ .slot = Slots.exporter, .name = "builtin.zarr" },
    },
};
