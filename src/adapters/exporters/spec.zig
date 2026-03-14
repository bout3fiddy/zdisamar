const std = @import("std");
const ExportFormat = @import("format.zig").ExportFormat;

pub const Compression = struct {
    codec: Codec = .none,
    level: ?u8 = null,

    pub const Codec = enum {
        none,
        zstd,
        gzip,
    };
};

pub const Chunking = struct {
    spectra: u32,
    layers: u32,
};

pub const ExportRequest = struct {
    format: ExportFormat,
    destination_uri: []const u8,
    dataset_name: []const u8 = "result",
    include_provenance: bool = true,
    compression: Compression = .{},
    chunking: ?Chunking = null,
};

pub const ExportArtifact = struct {
    format: ExportFormat,
    destination_uri: []const u8,
    dataset_name: []const u8,
    plugin_id: []const u8,
    media_type: []const u8,
    extension: []const u8,
    includes_provenance: bool,
};

pub fn buildArtifact(request: ExportRequest) ExportArtifact {
    return .{
        .format = request.format,
        .destination_uri = request.destination_uri,
        .dataset_name = request.dataset_name,
        .plugin_id = request.format.defaultPluginId(),
        .media_type = request.format.mediaType(),
        .extension = request.format.extension(),
        .includes_provenance = request.include_provenance,
    };
}

test "adapter maps export request to stable artifact metadata" {
    const netcdf = buildArtifact(.{
        .format = .netcdf_cf,
        .destination_uri = "file://out/scene.nc",
    });
    try std.testing.expectEqualStrings("builtin.netcdf_cf", netcdf.plugin_id);
    try std.testing.expectEqualStrings("application/x-netcdf", netcdf.media_type);
    try std.testing.expectEqualStrings(".nc", netcdf.extension);

    const zarr = buildArtifact(.{
        .format = .zarr,
        .destination_uri = "file://out/scene.zarr",
        .dataset_name = "slant_column",
        .include_provenance = false,
        .compression = .{ .codec = .zstd, .level = 3 },
        .chunking = .{ .spectra = 256, .layers = 64 },
    });
    try std.testing.expectEqualStrings("builtin.zarr", zarr.plugin_id);
    try std.testing.expectEqualStrings("application/vnd+zarr", zarr.media_type);
    try std.testing.expectEqualStrings(".zarr", zarr.extension);
    try std.testing.expectEqual(false, zarr.includes_provenance);
}
