//! Purpose:
//!   Load reference assets from bundled manifests or explicit external files.
//!
//! Physics:
//!   Hydrate climatology, spectroscopy, CIA, LUT, and Mie tables into typed
//!   inputs that preserve the original scientific provenance and units.
//!
//! Vendor:
//!   `reference asset ingest`
//!
//! Design:
//!   Keep manifest resolution, format contracts, and table materialization in
//!   this adapter layer so the core and kernels only see typed data.
//!
//! Invariants:
//!   Bundle-derived assets validate their hashes and column layouts before
//!   reaching the engine.
//!
//! Validation:
//!   Reference-asset loader tests and the bundled optics validation helpers.

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
    "line_strength_cm2_per_molecule",
    "air_half_width_nm",
    "temperature_exponent",
    "lower_state_energy_cm1",
    "pressure_shift_nm",
    "line_mixing_coefficient",
};

const hitran_vendor_o2a_columns = [_][]const u8{
    "gas_index",
    "isotope_number",
    "abundance_fraction",
    "center_wavelength_nm",
    "line_strength_cm2_per_molecule",
    "air_half_width_nm",
    "temperature_exponent",
    "lower_state_energy_cm1",
    "pressure_shift_nm",
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

/// Purpose:
///   Load a bundle asset by manifest path and asset id.
///
/// Physics:
///   Verify the manifest and asset bytes before converting the payload into typed rows.
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

/// Purpose:
///   Load a CSV-backed bundle asset.
pub fn loadCsvBundleAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    asset_id: []const u8,
) !LoadedAsset {
    return loadBundleAsset(allocator, kind, bundle_manifest_path, asset_id);
}

/// Purpose:
///   Load and parse an externally supplied asset file.
///
/// Physics:
///   Use the explicit file path and declared format instead of a bundle manifest.
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
        //   External assets still carry manifest-style metadata so the engine can treat them like
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

/// Purpose:
///   Load a bundle asset from embedded manifest and asset bytes.
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

/// Purpose:
///   Resolve the format-specific column contract for one asset kind.
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

test "reference asset loader validates hashes and parses numeric tables" {
    var asset = try loadBundleAsset(
        std.testing.allocator,
        .cross_section_table,
        "data/cross_sections/bundle_manifest.json",
        "no2_405_465_demo",
    );
    defer asset.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("disamar_standard", asset.owner_package);
    try std.testing.expectEqual(@as(u32, 5), asset.row_count);
    try std.testing.expectEqual(@as(usize, 2), asset.columnCount());
    try std.testing.expectApproxEqAbs(@as(f64, 405.0), asset.value(0, 0), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 4.17e-19), asset.value(4, 1), 1e-25);

    var cross_sections = try asset.toCrossSectionTable(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f64, 5.02e-19), cross_sections.interpolateSigma(440.0), 1e-25);
}

test "reference asset loader parses HITRAN-style line lists into spectroscopy rows" {
    var asset = try loadBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "no2_demo_lines",
    );
    defer asset.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 5), asset.row_count);
    try std.testing.expectEqual(@as(usize, 10), asset.columnCount());

    var lines = try asset.toSpectroscopyLineList(std.testing.allocator);
    defer lines.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 10), lines.lines[0].gas_index);
    try std.testing.expectEqual(@as(u8, 1), lines.lines[0].isotope_number);
    try std.testing.expect(lines.lines[0].abundance_fraction > 0.9);
    const near_line = lines.evaluateAt(434.6, 250.0, 800.0);
    const off_line = lines.evaluateAt(420.0, 250.0, 800.0);
    try std.testing.expect(near_line.total_sigma_cm2_per_molecule > off_line.total_sigma_cm2_per_molecule);
    try std.testing.expectEqual(@as(f64, 0.0), near_line.line_mixing_sigma_cm2_per_molecule);
}

test "reference asset loader preserves vendor O2A filter metadata for bundled JPL line lists" {
    var asset = try loadBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "o2a_hitran_07_hit08_tropomi",
    );
    defer asset.deinit(std.testing.allocator);

    try std.testing.expect(asset.row_count > 1000);
    try std.testing.expectEqual(@as(usize, 14), asset.columnCount());

    var lines = try asset.toSpectroscopyLineList(std.testing.allocator);
    defer lines.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 7), lines.lines[0].gas_index);
    try std.testing.expectEqual(@as(u8, 1), lines.lines[0].isotope_number);
    try std.testing.expectEqual(@as(u8, 5), lines.lines[2].branch_ic1.?);
    try std.testing.expectEqual(@as(u8, 1), lines.lines[2].branch_ic2.?);
    try std.testing.expect(lines.lines[2].rotational_nf.? <= 35);
    try std.testing.expect(lines.lines[2].vendor_filter_metadata_from_source);
}

test "reference asset loader parses vendor strong-line and relaxation sidecars" {
    var sdf_asset = try loadBundleAsset(
        std.testing.allocator,
        .spectroscopy_strong_line_set,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_sdf_subset",
    );
    defer sdf_asset.deinit(std.testing.allocator);

    var strong_lines = try sdf_asset.toSpectroscopyStrongLineSet(std.testing.allocator);
    defer strong_lines.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 8), sdf_asset.row_count);
    try std.testing.expectEqual(@as(usize, 12), sdf_asset.columnCount());
    try std.testing.expect(strong_lines.lines[0].center_wavenumber_cm1 > 12000.0);
    try std.testing.expect(strong_lines.lines[0].rotational_index_m1 < 0);
    try std.testing.expect(strong_lines.lines[0].air_half_width_nm > 0.0);

    var rmf_asset = try loadBundleAsset(
        std.testing.allocator,
        .spectroscopy_relaxation_matrix,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_rmf_subset",
    );
    defer rmf_asset.deinit(std.testing.allocator);

    var relaxation = try rmf_asset.toSpectroscopyRelaxationMatrix(std.testing.allocator);
    defer relaxation.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 64), rmf_asset.row_count);
    try std.testing.expectEqual(@as(usize, 8), relaxation.line_count);
    try std.testing.expect(relaxation.weightAt(0, 0) > 0.0);
    try std.testing.expect(relaxation.temperatureExponentAt(0, 1) != 0.0);
}

test "reference asset loader parses bounded O2-O2 CIA tables without collapsing units" {
    var asset = try loadBundleAsset(
        std.testing.allocator,
        .collision_induced_absorption_table,
        "data/cross_sections/bundle_manifest.json",
        "o2o2_bira_o2a_subset",
    );
    defer asset.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), asset.columnCount());
    try std.testing.expectEqual(@as(u32, 378), asset.row_count);

    var table = try asset.toCollisionInducedAbsorptionTable(std.testing.allocator);
    defer table.deinit(std.testing.allocator);

    const sigma_761 = table.sigmaAt(761.0, 294.0);
    const sigma_770 = table.sigmaAt(770.0, 294.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0e-46), table.scale_factor_cm5_per_molecule2, 1e-60);
    try std.testing.expect(sigma_761 > 0.0);
    try std.testing.expect(sigma_761 > sigma_770);
    try std.testing.expectEqual(@as(f64, 0.0), table.dSigmaDTemperatureAt(761.0, 294.0));
}
