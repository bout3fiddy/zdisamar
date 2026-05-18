const std = @import("std");

// layout(64-bit):
//   size: 120 B, align: 8 B
//   field storage: 116 B across 6 fields; largest: upstream=48 B, bundle_id=16 B, owner_package=16 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   out-of-line: bundle_id, owner_package, description, assets carry references/descriptors; referenced storage is not included in size
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 120 B (0.117 KiB); total also includes referenced storage above
pub const BundleManifest = struct {
    version: u32,
    bundle_id: []const u8,
    owner_package: []const u8,
    description: []const u8,
    upstream: Upstream,
    assets: []const Asset,

    // layout(64-bit):
    //   size: 48 B, align: 8 B
    //   field storage: vendor_root=16 B, source_paths=16 B, reference_snapshot=16 B; padding: 0 B (0 bits)
    //   unused bits: 0 padding + 0 bool-storage slack = 0 bits
    //   out-of-line: vendor_root, source_paths, reference_snapshot carry references/descriptors; referenced storage is not included in size
    //   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
    //   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
    pub const Upstream = struct {
        vendor_root: []const u8,
        source_paths: []const []const u8,
        reference_snapshot: []const u8,
    };

    // layout(64-bit):
    //   size: 80 B, align: 8 B
    //   field storage: 80 B across 5 fields; largest: id=16 B, path=16 B, format=16 B; padding: 0 B (0 bits)
    //   unused bits: 0 padding + 0 bool-storage slack = 0 bits
    //   out-of-line: id, path, format, sha256, columns carry references/descriptors; referenced storage is not included in size
    //   cache span: 2 cache line(s) at 64 B per line
    //   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
    //   footprint: per instance = 80 B (0.078 KiB); total also includes referenced storage above
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
