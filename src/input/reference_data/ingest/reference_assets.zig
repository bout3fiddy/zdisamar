const std = @import("std");
const formats = @import("reference_assets_formats.zig");
const loaded_asset = @import("reference_assets_loaded_asset.zig");
const types = @import("reference_assets_types.zig");

// reference_assets.zig --------------------------------------------------------------------------------------|
// Manifest-driven reference-data asset loader for bundled, embedded, and external numeric tables.            |
//                                                                                                            |
// used by                                                                                                    |
//   bundled/assets.zig loads retained O2 A climatology, spectroscopy, CIA, and LUT sidecars                  |
//   o2a_reference/run.zig loads external vendor assets from parsed reference cases                           |
//   ingest tests verify manifest lookup, hash checks, column schemas, and typed LoadedAsset conversion       |
//                                                                                                            |
// main paths                                                                                                 |
//   loadBundleAsset         : read JSON manifest -> select asset row -> read bytes -> hash -> parse table    |
//   loadEmbeddedBundleAsset : parse embedded manifest -> find embedded bytes -> same validation path         |
//   loadExternalAsset       : read caller-provided file -> choose schema from asset_format/kind -> parse     |
//   initLoadedAsset         : duplicate provenance strings and hand owned numeric rows to LoadedAsset        |
//                                                                                                            |
// boundary                                                                                                   |
//   File I/O, JSON parsing, CSV/HITRAN parsing, and hash validation live here in the input layer. Forward    |
//   model code receives typed ReferenceData rows and never calls this loader path directly.                  |
//                                                                                                            |
// memory                                                                                                     |
//   Bundle manifests borrow strings from a short-lived JSON arena. LoadedAsset owns duplicated metadata,     |
//   column-name strings, and numeric table storage; callers must deinit the returned LoadedAsset.            |
// -----------------------------------------------------------------------------------------------------------|

const manifest = struct {
    // BundleManifest ----------------------------------------------------------------------------------------|
    // Parsed bundle manifest header and asset rows.                                                          |
    //                                                                                                        |
    // layout(64-bit)                                                                                         |
    // size: 120 B (0.117 KiB), align: 8 B                                                                    |
    //                                                                                                        |
    // memory                                                                                                 |
    // [  0.. 15] bundle_id       : []const u8                                                                |
    // [ 16.. 31] owner_package   : []const u8                                                                |
    // [ 32.. 47] description     : []const u8                                                                |
    // [ 48.. 95] upstream        : Upstream                                                                  |
    // [ 96..111] assets          : []const Asset                                                             |
    // [112..115] version         : u32                                                                       |
    // [116..119] trailing padding: 4 B                                                                       |
    //                                                                                                        |
    // referenced storage                                                                                     |
    //   String and asset slices borrow the parsed JSON arena; referenced storage is not included in this row.|
    //                                                                                                        |
    // unused bits: 32 padding + 0 bool-storage slack = 32 bits                                               |
    // cache span: 2 cache lines at 64 B per line                                                             |
    // footprint: per instance = 120 B (0.117 KiB); total also includes parsed JSON storage                   |
    pub const BundleManifest = struct {
        version: u32,
        bundle_id: []const u8,
        owner_package: []const u8,
        description: []const u8,
        upstream: Upstream,
        assets: []const Asset,

        // Upstream ------------------------------------------------------------------------------------------|
        // Source provenance block embedded in a bundle manifest.                                             |
        //                                                                                                    |
        // layout(64-bit)                                                                                     |
        // size: 48 B (0.047 KiB), align: 8 B                                                                 |
        //                                                                                                    |
        // memory                                                                                             |
        // [ 0..15] vendor_root       : []const u8                                                            |
        // [16..31] source_paths      : []const []const u8                                                    |
        // [32..47] reference_snapshot: []const u8                                                            |
        //                                                                                                    |
        // referenced storage                                                                                 |
        //   Slices borrow the parsed JSON arena; referenced storage is not included in this row.             |
        //                                                                                                    |
        // unused bits: 0 padding + 0 bool-storage slack = 0 bits                                             |
        // footprint: per instance = 48 B (0.047 KiB); total also includes parsed JSON storage                |
        pub const Upstream = struct {
            vendor_root: []const u8,
            source_paths: []const []const u8,
            reference_snapshot: []const u8,
        };

        // Asset ---------------------------------------------------------------------------------------------|
        // One asset row in a bundle manifest.                                                                |
        //                                                                                                    |
        // layout(64-bit)                                                                                     |
        // size: 80 B (0.078 KiB), align: 8 B                                                                 |
        //                                                                                                    |
        // memory                                                                                             |
        // [ 0..15] id     : []const u8                                                                       |
        // [16..31] path   : []const u8                                                                       |
        // [32..47] format : []const u8                                                                       |
        // [48..63] sha256 : []const u8                                                                       |
        // [64..79] columns: []const []const u8                                                               |
        //                                                                                                    |
        // referenced storage                                                                                 |
        //   Slices borrow the parsed JSON arena; referenced storage is not included in this row.             |
        //                                                                                                    |
        // unused bits: 0 padding + 0 bool-storage slack = 0 bits                                             |
        // cache span: 2 cache lines at 64 B per line                                                         |
        // footprint: per instance = 80 B (0.078 KiB); total also includes parsed JSON storage                |
        pub const Asset = struct {
            id: []const u8,
            path: []const u8,
            format: []const u8,
            sha256: []const u8,
            columns: []const []const u8,
        };
    };

    pub fn findAsset(
        assets: []const @This().BundleManifest.Asset,
        asset_id: []const u8,
    ) ?@This().BundleManifest.Asset {
        for (assets) |asset| {
            if (std.mem.eql(u8, asset.id, asset_id)) return asset;
        }
        return null;
    }

    pub fn findEmbeddedAssetBytes(
        embedded_assets: []const types.EmbeddedAsset,
        path: []const u8,
    ) ?[]const u8 {
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

const profile_csv_columns = [_][]const u8{
    "altitude_km",
    "pressure_hpa",
    "temperature_k",
    "air_number_density_cm3",
};

const bira_cia_columns = [_][]const u8{
    "wavelength_nm",
    "a0",
    "a1",
    "a2",
    "scale_factor_cm5_per_molecule2",
};

const lisa_sdf_columns = [_][]const u8{
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
};

const lisa_rmf_columns = [_][]const u8{
    "wt0",
    "temperature_exponent_bw",
};

const airmass_factor_columns = [_][]const u8{
    "solar_zenith_deg",
    "view_zenith_deg",
    "relative_azimuth_deg",
    "air_mass_factor",
};

const cross_section_columns = [_][]const u8{
    "wavelength_nm",
    "absorber_sigma_cm2_per_molecule",
};

pub fn loadBundleAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    asset_id: []const u8,
) !LoadedAsset {
    const manifest_bytes = try std.fs.cwd().readFileAlloc(allocator, bundle_manifest_path, 1024 * 1024);
    defer allocator.free(manifest_bytes);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const bundle = try std.json.parseFromSliceLeaky(BundleManifest, arena.allocator(), manifest_bytes, .{
        .ignore_unknown_fields = true,
    });

    const bundle_asset = manifest.findAsset(bundle.assets, asset_id) orelse return error.AssetNotFound;

    const asset_bytes = try std.fs.cwd().readFileAlloc(allocator, bundle_asset.path, 1024 * 1024);
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
    const asset_bytes = try std.fs.cwd().readFileAlloc(allocator, asset_path, 16 * 1024 * 1024);
    defer allocator.free(asset_bytes);

    const dataset_hash = try renderSha256(allocator, asset_bytes);
    errdefer allocator.free(dataset_hash);

    const parsed_table = try formats.parseAssetTable(allocator, externalAssetSpec(kind, asset_format), asset_bytes);
    errdefer {
        for (parsed_table.column_names) |column_name| allocator.free(column_name);
        allocator.free(parsed_table.column_names);
        allocator.free(parsed_table.values);
    }

    // External assets still carry manifest-style metadata so downstream conversion can treat them like
    // bundled assets after this input-layer boundary has parsed and owned the numeric rows.
    return .{
        .kind = kind,
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
    const asset_bytes =
        manifest.findEmbeddedAssetBytes(embedded_assets, bundle_asset.path) orelse return error.AssetNotFound;

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

    // Hash validation happens before numeric parsing so broken assets fail at the provenance boundary,
    // not after partially materializing typed rows.

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
            .columns = &profile_csv_columns,
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
            .columns = &bira_cia_columns,
        };
    }

    if (std.mem.eql(u8, asset_format, "lisa_sdf")) {
        return .{
            .format = "lisa_sdf",
            .columns = &lisa_sdf_columns,
        };
    }

    if (std.mem.eql(u8, asset_format, "lisa_rmf")) {
        return .{
            .format = "lisa_rmf",
            .columns = &lisa_rmf_columns,
        };
    }

    return switch (kind) {
        .climatology_profile => .{
            .format = "csv",
            .columns = &profile_csv_columns,
        },
        .cross_section_table => .{
            .format = "csv",
            .columns = &cross_section_columns,
        },
        .collision_induced_absorption_table => .{
            .format = "bira_cia_poly",
            .columns = &bira_cia_columns,
        },
        .spectroscopy_line_list => .{
            .format = "hitran_160",
            .columns = &hitran_extended_columns,
        },
        .spectroscopy_strong_line_set => .{
            .format = "lisa_sdf",
            .columns = &lisa_sdf_columns,
        },
        .spectroscopy_relaxation_matrix => .{
            .format = "lisa_rmf",
            .columns = &lisa_rmf_columns,
        },
        .lookup_table => .{
            .format = "csv",
            .columns = &airmass_factor_columns,
        },
    };
}
