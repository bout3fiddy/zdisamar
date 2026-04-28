const std = @import("std");
const formats = @import("reference_assets_formats.zig");
const loaded_asset = @import("reference_assets_loaded_asset.zig");
const manifest = @import("reference_assets_manifest.zig");

pub fn initLoadedAsset(
    allocator: std.mem.Allocator,
    kind: @import("reference_assets_types.zig").AssetKind,
    bundle_manifest_path: []const u8,
    bundle: manifest.BundleManifest,
    bundle_asset: manifest.BundleManifest.Asset,
    asset_bytes: []const u8,
) !loaded_asset.LoadedAsset {
    const dataset_hash = try renderSha256(allocator, asset_bytes);
    errdefer allocator.free(dataset_hash);
    if (!std.mem.eql(u8, dataset_hash, bundle_asset.sha256)) return error.HashMismatch;
    // DECISION:
    //   Hash validation happens before numeric parsing so broken assets fail
    //   fast at the provenance boundary, not after partially materializing
    //   typed rows.

    const parsed_table = try formats.parseAssetTable(allocator, .{
        .format = bundle_asset.format,
        .columns = bundle_asset.columns,
    }, asset_bytes);
    errdefer {
        for (parsed_table.column_names) |column_name| allocator.free(column_name);
        allocator.free(parsed_table.column_names);
        allocator.free(parsed_table.values);
    }

    if (parsed_table.column_names.len != bundle_asset.columns.len) return error.ColumnMismatch;
    for (parsed_table.column_names, bundle_asset.columns) |actual, expected| {
        if (!std.mem.eql(u8, actual, expected)) return error.ColumnMismatch;
    }

    const owned_bundle_manifest_path = try allocator.dupe(u8, bundle_manifest_path);
    errdefer allocator.free(owned_bundle_manifest_path);
    const owned_bundle_id = try allocator.dupe(u8, bundle.bundle_id);
    errdefer allocator.free(owned_bundle_id);
    const owned_owner_package = try allocator.dupe(u8, bundle.owner_package);
    errdefer allocator.free(owned_owner_package);
    const owned_asset_id = try allocator.dupe(u8, bundle_asset.id);
    errdefer allocator.free(owned_asset_id);
    const owned_asset_path = try allocator.dupe(u8, bundle_asset.path);
    errdefer allocator.free(owned_asset_path);
    const owned_dataset_id = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ bundle.bundle_id, bundle_asset.id });
    errdefer allocator.free(owned_dataset_id);

    return .{
        .kind = kind,
        .bundle_manifest_path = owned_bundle_manifest_path,
        .bundle_id = owned_bundle_id,
        .owner_package = owned_owner_package,
        .asset_id = owned_asset_id,
        .asset_path = owned_asset_path,
        .dataset_id = owned_dataset_id,
        .dataset_hash = dataset_hash,
        .column_names = parsed_table.column_names,
        .values = parsed_table.values,
        .row_count = parsed_table.row_count,
    };
}

pub fn renderSha256(allocator: std.mem.Allocator, contents: []const u8) ![]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(contents, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    return std.fmt.allocPrint(allocator, "sha256:{s}", .{digest_hex[0..]});
}
