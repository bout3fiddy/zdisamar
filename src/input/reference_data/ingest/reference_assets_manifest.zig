const std = @import("std");

pub const BundleManifest = struct {
    version: u32,
    bundle_id: []const u8,
    owner_package: []const u8,
    description: []const u8,
    upstream: Upstream,
    assets: []const Asset,

    pub const Upstream = struct {
        vendor_root: []const u8,
        source_paths: []const []const u8,
        reference_snapshot: []const u8,
    };

    pub const Asset = struct {
        id: []const u8,
        path: []const u8,
        format: []const u8,
        sha256: []const u8,
        columns: []const []const u8,
    };
};

pub fn findAsset(assets: []const BundleManifest.Asset, asset_id: []const u8) ?BundleManifest.Asset {
    for (assets) |asset| {
        if (std.mem.eql(u8, asset.id, asset_id)) return asset;
    }
    return null;
}

pub fn findEmbeddedAssetBytes(embedded_assets: []const @import("reference_assets_types.zig").EmbeddedAsset, path: []const u8) ?[]const u8 {
    for (embedded_assets) |asset| {
        if (std.mem.eql(u8, asset.path, path)) return asset.contents;
    }
    return null;
}
