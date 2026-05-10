const std = @import("std");
const internal = @import("internal");

const reference_assets = internal.input_reference_data.ingest_reference_assets;
const loadBundleAsset = reference_assets.loadBundleAsset;

test "reference asset loader parses bundled vendor O2A line-list metadata" {
    var asset = try loadBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/reference_data/cross_sections/bundle_manifest.json",
        "o2a_hitran_07_hit08_tropomi",
    );
    defer asset.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 17), asset.columnCount());
    try std.testing.expect(asset.row_count > 585);
    try std.testing.expect(std.math.isNan(asset.value(2, 13)));
    try std.testing.expect(std.math.isNan(asset.value(2, 14)));
    try std.testing.expect(std.math.isNan(asset.value(2, 15)));
    try std.testing.expectEqual(@as(f64, 0.0), asset.value(2, 16));

    var lines = try asset.toSpectroscopyLineList(std.testing.allocator);
    defer lines.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u8, null), lines.lines[2].branch_ic1);
    try std.testing.expectEqual(@as(?u8, null), lines.lines[2].branch_ic2);
    try std.testing.expectEqual(@as(?u8, null), lines.lines[2].rotational_nf);
    try std.testing.expect(!lines.lines[2].vendor_filter_metadata_from_source);

    try std.testing.expectEqual(@as(?u8, 5), lines.lines[585].branch_ic1);
    try std.testing.expectEqual(@as(?u8, 1), lines.lines[585].branch_ic2);
    try std.testing.expectEqual(@as(?u8, 9), lines.lines[585].rotational_nf);
    try std.testing.expect(!lines.lines[585].vendor_filter_metadata_from_source);
}

test "reference asset loader parses vendor strong-line and relaxation sidecars" {
    var sdf_asset = try loadBundleAsset(
        std.testing.allocator,
        .spectroscopy_strong_line_set,
        "data/reference_data/cross_sections/bundle_manifest.json",
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
        "data/reference_data/cross_sections/bundle_manifest.json",
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
        "data/reference_data/cross_sections/bundle_manifest.json",
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
