const std = @import("std");
const zdisamar = @import("zdisamar");

test "spectral ascii ingest bridges vendor-style input into typed measurement and request summaries" {
    var loaded = try zdisamar.ingest.spectral_ascii.parseFile(
        std.testing.allocator,
        "data/examples/irr_rad_channels_demo.txt",
    );
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), loaded.channelCount(.irradiance));
    try std.testing.expectEqual(@as(usize, 1), loaded.channelCount(.radiance));
    try std.testing.expectEqual(@as(u32, 2), loaded.sampleCount(.radiance));

    const measurement = loaded.measurement("radiance");
    try std.testing.expectEqualStrings("radiance", measurement.product);
    try std.testing.expectEqual(@as(u32, 2), measurement.sample_count);

    const request = loaded.toRequest("demo-scene", &[_][]const u8{"radiance"});
    try std.testing.expectEqualStrings("demo-scene", request.scene.id);
    try std.testing.expectEqual(@as(u32, 2), request.scene.spectral_grid.sample_count);
}

test "reference asset ingest validates manifests and registers provenance into engine caches" {
    var cross_section = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .cross_section_table,
        "data/cross_sections/bundle_manifest.json",
        "no2_405_465_demo",
    );
    defer cross_section.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("disamar_standard", cross_section.owner_package);
    try std.testing.expectEqualStrings("disamar_standard.cross_sections.baseline:no2_405_465_demo", cross_section.dataset_id);
    try std.testing.expectEqual(@as(u32, 5), cross_section.row_count);
    try std.testing.expectEqual(@as(usize, 2), cross_section.columnCount());

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try cross_section.registerWithEngine(&engine);

    const dataset_entry = engine.dataset_cache.get(cross_section.dataset_id).?;
    try std.testing.expectEqualStrings(cross_section.dataset_hash, dataset_entry.dataset_hash);

    var spectroscopy = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "no2_demo_lines",
    );
    defer spectroscopy.deinit(std.testing.allocator);

    var lines = try spectroscopy.toSpectroscopyLineList(std.testing.allocator);
    defer lines.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 5), spectroscopy.row_count);
    try std.testing.expectEqual(@as(usize, 7), spectroscopy.columnCount());
    try std.testing.expect(lines.sigmaAt(434.6, 250.0, 800.0) > lines.sigmaAt(420.0, 250.0, 800.0));
    try std.testing.expect(@abs(lines.evaluateAt(434.6, 250.0, 800.0).line_mixing_sigma_cm2_per_molecule) > 0.0);

    var lut = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut.deinit(std.testing.allocator);
    try lut.registerWithEngine(&engine);

    const lut_entry = engine.lut_cache.get(lut.dataset_id, lut.asset_id).?;
    try std.testing.expectEqual(@as(u32, 5), lut_entry.shape.spectral_bins);
    try std.testing.expectEqual(@as(u32, 3), lut_entry.shape.coefficient_count);
}
