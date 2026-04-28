const std = @import("std");
const formats = @import("reference_assets_formats.zig");
const loader = @import("reference_assets_loader.zig");
const loaded_asset = @import("reference_assets_loaded_asset.zig");
const manifest = @import("reference_assets_manifest.zig");
const types = @import("reference_assets_types.zig");

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

const hitran_legacy_columns = [_][]const u8{
    "center_wavelength_nm",
    "line_strength_cm2_per_molecule",
    "air_half_width_nm",
    "temperature_exponent",
    "lower_state_energy_cm1",
    "pressure_shift_nm",
    "line_mixing_coefficient",
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

    return loader.initLoadedAsset(allocator, kind, bundle_manifest_path, bundle, bundle_asset, asset_bytes);
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

    const dataset_hash = try loader.renderSha256(allocator, asset_bytes);
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
        .owner_package = try allocator.dupe(u8, "canonical_config"),
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

    return loader.initLoadedAsset(allocator, kind, bundle_manifest_path, bundle, bundle_asset, asset_bytes);
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
            .columns = &.{ "wavelength_nm", "no2_sigma_cm2_per_molecule" },
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
        .mie_phase_table => .{
            .format = "csv",
            .columns = &.{
                "wavelength_nm",
                "single_scatter_albedo",
                "extinction_scale",
                "phase0",
                "phase1",
                "phase2",
                "phase3",
            },
        },
    };
}
