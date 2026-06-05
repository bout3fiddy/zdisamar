const std = @import("std");
const runtime_io = @import("../../../common/runtime_io.zig");
const formats = @import("reference_assets_formats.zig");
const loaded_asset = @import("reference_assets_loaded_asset.zig");
const types = @import("reference_assets_types.zig");

const manifest = struct {
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

    pub fn findAsset(assets: []const @This().BundleManifest.Asset, asset_id: []const u8) ?@This().BundleManifest.Asset {
        for (assets) |asset| {
            if (std.mem.eql(u8, asset.id, asset_id)) return asset;
        }
        return null;
    }

    pub fn findEmbeddedAssetBytes(embedded_assets: []const types.EmbeddedAsset, path: []const u8) ?[]const u8 {
        for (embedded_assets) |asset| {
            if (std.mem.eql(u8, asset.path, path)) return asset.contents;
        }
        return null;
    }
};

pub const AssetKind = types.AssetKind;
pub const EmbeddedAsset = types.EmbeddedAsset;
pub const LoadedAsset = loaded_asset.LoadedAsset;
pub const BundleManifest = manifest.BundleManifest;

const hitran_extended_columns = [_][]const u8{
    "gas_index",
    "isotope_number",
    "abundance_fraction",
    "center_wavelength_nm",
    "center_wavenumber_cm1",
    "line_strength_cm2_per_molecule",
    "air_half_width_nm",
    "air_half_width_cm1",
    "temperature_exponent",
    "lower_state_energy_cm1",
    "pressure_shift_nm",
    "pressure_shift_cm1",
    "line_mixing_coefficient",
};

const hitran_vendor_o2a_columns = [_][]const u8{
    "gas_index",
    "isotope_number",
    "abundance_fraction",
    "center_wavelength_nm",
    "center_wavenumber_cm1",
    "line_strength_cm2_per_molecule",
    "air_half_width_nm",
    "air_half_width_cm1",
    "temperature_exponent",
    "lower_state_energy_cm1",
    "pressure_shift_nm",
    "pressure_shift_cm1",
    "line_mixing_coefficient",
    "branch_ic1",
    "branch_ic2",
    "rotational_nf",
    "vendor_filter_metadata_from_source",
};

pub fn loadBundleAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    asset_id: []const u8,
) !LoadedAsset {
    var runtime = runtime_io.RuntimeIo.init(std.heap.smp_allocator);
    defer runtime.deinit();
    const io = runtime.io();
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        bundle_manifest_path,
        allocator,
        .limited(1024 * 1024),
    );
    defer allocator.free(manifest_bytes);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const bundle = try std.json.parseFromSliceLeaky(BundleManifest, arena.allocator(), manifest_bytes, .{
        .ignore_unknown_fields = true,
    });

    const bundle_asset = manifest.findAsset(bundle.assets, asset_id) orelse return error.AssetNotFound;

    const asset_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        bundle_asset.path,
        allocator,
        .limited(1024 * 1024),
    );
    defer allocator.free(asset_bytes);

    return initLoadedAsset(allocator, kind, bundle_manifest_path, bundle, bundle_asset, asset_bytes);
}

pub fn loadCsvBundleAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    asset_id: []const u8,
) !LoadedAsset {
    return loadBundleAsset(allocator, kind, bundle_manifest_path, asset_id);
}

pub fn loadExternalAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    asset_id: []const u8,
    asset_path: []const u8,
    asset_format: []const u8,
) !LoadedAsset {
    var runtime = runtime_io.RuntimeIo.init(std.heap.smp_allocator);
    defer runtime.deinit();
    const asset_bytes = try std.Io.Dir.cwd().readFileAlloc(
        runtime.io(),
        asset_path,
        allocator,
        .limited(16 * 1024 * 1024),
    );
    defer allocator.free(asset_bytes);

    const dataset_hash = try renderSha256(allocator, asset_bytes);
    errdefer allocator.free(dataset_hash);

    const parsed_table = try formats.parseAssetTable(allocator, externalAssetSpec(kind, asset_format), asset_bytes);
    errdefer {
        for (parsed_table.column_names) |column_name| allocator.free(column_name);
        allocator.free(parsed_table.column_names);
        allocator.free(parsed_table.values);
    }

    return .{
        .kind = kind,
        // DECISION:
        //   External assets still carry manifest-style metadata so the forward model can treat them like
        //   other hydrated reference assets.
        .bundle_manifest_path = try allocator.dupe(u8, asset_path),
        .bundle_id = try allocator.dupe(u8, "external_asset"),
        .owner_package = try allocator.dupe(u8, "external_asset"),
        .asset_id = try allocator.dupe(u8, asset_id),
        .asset_path = try allocator.dupe(u8, asset_path),
        .dataset_id = try allocator.dupe(u8, asset_id),
        .dataset_hash = dataset_hash,
        .column_names = parsed_table.column_names,
        .values = parsed_table.values,
        .row_count = parsed_table.row_count,
    };
}

pub fn loadEmbeddedBundleAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    manifest_bytes: []const u8,
    asset_id: []const u8,
    embedded_assets: []const EmbeddedAsset,
) !LoadedAsset {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const bundle = try std.json.parseFromSliceLeaky(BundleManifest, arena.allocator(), manifest_bytes, .{
        .ignore_unknown_fields = true,
    });

    const bundle_asset = manifest.findAsset(bundle.assets, asset_id) orelse return error.AssetNotFound;
    const asset_bytes = manifest.findEmbeddedAssetBytes(embedded_assets, bundle_asset.path) orelse return error.AssetNotFound;

    return initLoadedAsset(allocator, kind, bundle_manifest_path, bundle, bundle_asset, asset_bytes);
}

fn initLoadedAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    bundle: BundleManifest,
    bundle_asset: BundleManifest.Asset,
    asset_bytes: []const u8,
) !LoadedAsset {
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

fn renderSha256(allocator: std.mem.Allocator, contents: []const u8) ![]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(contents, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    return std.fmt.allocPrint(allocator, "sha256:{s}", .{digest_hex[0..]});
}

fn externalAssetSpec(kind: AssetKind, asset_format: []const u8) formats.AssetSpec {
    if (std.mem.eql(u8, asset_format, "profile_csv")) {
        return .{
            .format = "csv",
            .columns = &.{ "altitude_km", "pressure_hpa", "temperature_k", "air_number_density_cm3" },
        };
    }
    if (std.mem.eql(u8, asset_format, "hitran_par")) {
        return .{
            .format = "hitran_160",
            .columns = &hitran_extended_columns,
        };
    }
    if (std.mem.eql(u8, asset_format, "hitran_par_o2a")) {
        return .{
            .format = "hitran_160",
            .columns = &hitran_vendor_o2a_columns,
        };
    }
    if (std.mem.eql(u8, asset_format, "bira_cia")) {
        return .{
            .format = "bira_cia_poly",
            .columns = &.{
                "wavelength_nm",
                "a0",
                "a1",
                "a2",
                "scale_factor_cm5_per_molecule2",
            },
        };
    }
    if (std.mem.eql(u8, asset_format, "lisa_sdf")) {
        return .{
            .format = "lisa_sdf",
            .columns = &.{
                "center_wavenumber_cm1",
                "center_wavelength_nm",
                "population_t0",
                "dipole_ratio",
                "dipole_t0",
                "lower_state_energy_cm1",
                "air_half_width_cm1",
                "air_half_width_nm",
                "temperature_exponent",
                "pressure_shift_cm1",
                "pressure_shift_nm",
                "rotational_index_m1",
            },
        };
    }
    if (std.mem.eql(u8, asset_format, "lisa_rmf")) {
        return .{
            .format = "lisa_rmf",
            .columns = &.{ "wt0", "temperature_exponent_bw" },
        };
    }

    return switch (kind) {
        .climatology_profile => .{
            .format = "csv",
            .columns = &.{ "altitude_km", "pressure_hpa", "temperature_k", "air_number_density_cm3" },
        },
        .cross_section_table => .{
            .format = "csv",
            .columns = &.{ "wavelength_nm", "absorber_sigma_cm2_per_molecule" },
        },
        .collision_induced_absorption_table => .{
            .format = "bira_cia_poly",
            .columns = &.{
                "wavelength_nm",
                "a0",
                "a1",
                "a2",
                "scale_factor_cm5_per_molecule2",
            },
        },
        .spectroscopy_line_list => .{
            .format = "hitran_160",
            .columns = &hitran_extended_columns,
        },
        .spectroscopy_strong_line_set => .{
            .format = "lisa_sdf",
            .columns = &.{
                "center_wavenumber_cm1",
                "center_wavelength_nm",
                "population_t0",
                "dipole_ratio",
                "dipole_t0",
                "lower_state_energy_cm1",
                "air_half_width_cm1",
                "air_half_width_nm",
                "temperature_exponent",
                "pressure_shift_cm1",
                "pressure_shift_nm",
                "rotational_index_m1",
            },
        },
        .spectroscopy_relaxation_matrix => .{
            .format = "lisa_rmf",
            .columns = &.{ "wt0", "temperature_exponent_bw" },
        },
        .lookup_table => .{
            .format = "csv",
            .columns = &.{ "solar_zenith_deg", "view_zenith_deg", "relative_azimuth_deg", "air_mass_factor" },
        },
    };
}
