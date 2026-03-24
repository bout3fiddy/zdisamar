const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

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
    try std.testing.expectEqualStrings("radiance", measurement.resolvedProductName());
    try std.testing.expectEqual(zdisamar.MeasurementQuantity.radiance, measurement.observable);
    try std.testing.expectEqual(@as(u32, 2), measurement.sample_count);

    var request = try loaded.toRequest(std.testing.allocator, "demo-scene", &[_]zdisamar.RequestedProduct{
        .fromName("radiance"),
    });
    defer request.deinitOwned(std.testing.allocator);
    try std.testing.expectEqualStrings("demo-scene", request.scene.id);
    try std.testing.expectEqual(@as(u32, 2), request.scene.spectral_grid.sample_count);
    try std.testing.expectEqual(zdisamar.Instrument.SamplingMode.measured_channels, request.scene.observation_model.sampling);
    try std.testing.expectEqual(zdisamar.Instrument.NoiseModelKind.snr_from_input, request.scene.observation_model.noise_model);
    try std.testing.expectEqual(@as(usize, 2), request.scene.observation_model.measured_wavelengths_nm.len);
    try std.testing.expectApproxEqAbs(@as(f64, 405.0), request.scene.observation_model.measured_wavelengths_nm[0], 1.0e-12);
    try std.testing.expectEqual(@as(usize, 2), request.scene.observation_model.reference_radiance.len);
    try std.testing.expectApproxEqRel(@as(f64, 1.116153e13), request.scene.observation_model.reference_radiance[0], 1.0e-12);
    try std.testing.expectEqual(@as(usize, 2), request.scene.observation_model.ingested_noise_sigma.len);
    try std.testing.expectApproxEqRel(@as(f64, 1.116153e13 / 1485.0), request.scene.observation_model.ingested_noise_sigma[0], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.096153e13 / 1445.0), request.scene.observation_model.ingested_noise_sigma[1], 1.0e-12);
    try std.testing.expect(request.scene.observation_model.operational_solar_spectrum.enabled());
    try std.testing.expectApproxEqAbs(@as(f64, 3.402296e14), request.scene.observation_model.operational_solar_spectrum.irradiance[0], 1.0e8);

    var copied_sigma: [2]f64 = undefined;
    try internal.kernels.spectra.noise.copyInputSigma(request.scene.observation_model.ingested_noise_sigma, &copied_sigma);
    try std.testing.expectApproxEqRel(request.scene.observation_model.ingested_noise_sigma[0], copied_sigma[0], 1.0e-12);
    try std.testing.expectApproxEqRel(request.scene.observation_model.ingested_noise_sigma[1], copied_sigma[1], 1.0e-12);
}

test "spectral ascii ingest preserves explicit high-resolution grid and isrf table metadata" {
    var loaded = try zdisamar.ingest.spectral_ascii.parseFile(
        std.testing.allocator,
        "data/examples/irr_rad_channels_operational_isrf_table_demo.txt",
    );
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?f64, 0.08), loaded.metadata.high_resolution_step_nm);
    try std.testing.expectEqual(@as(?f64, 0.32), loaded.metadata.high_resolution_half_span_nm);
    try std.testing.expect(loaded.metadata.hasInstrumentLineShape());
    try std.testing.expectEqual(@as(u8, 5), loaded.metadata.instrument_line_shape.sample_count);
    try std.testing.expectApproxEqAbs(@as(f64, -0.32), loaded.metadata.instrument_line_shape.offsets_nm[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.36), loaded.metadata.instrument_line_shape.weights[2], 1e-12);
    try std.testing.expect(loaded.metadata.hasInstrumentLineShapeTable());
    try std.testing.expectEqual(@as(u16, 3), loaded.metadata.instrument_line_shape_table.nominal_count);
    try std.testing.expectApproxEqAbs(@as(f64, 406.0), loaded.metadata.instrument_line_shape_table.nominal_wavelengths_nm[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.30), loaded.metadata.instrument_line_shape_table.weightAt(1, 1), 1e-12);
}

test "spectral ascii ingest preserves operational refspec weights and external solar metadata" {
    var loaded = try zdisamar.ingest.spectral_ascii.parseFile(
        std.testing.allocator,
        "data/examples/irr_rad_channels_operational_refspec_demo.txt",
    );
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expect(loaded.metadata.operational_refspec_grid.enabled());
    try std.testing.expectEqual(@as(usize, 3), loaded.metadata.operational_refspec_grid.wavelengths_nm.len);
    try std.testing.expectApproxEqAbs(@as(f64, 761.0), loaded.metadata.operational_refspec_grid.wavelengths_nm[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.70), loaded.metadata.operational_refspec_grid.weights[1], 1e-12);

    try std.testing.expect(loaded.metadata.operational_solar_spectrum.enabled());
    try std.testing.expectEqual(@as(usize, 5), loaded.metadata.operational_solar_spectrum.wavelengths_nm.len);
    try std.testing.expectApproxEqAbs(@as(f64, 760.6), loaded.metadata.operational_solar_spectrum.wavelengths_nm[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.8e14), loaded.metadata.operational_solar_spectrum.interpolateIrradiance(761.0), 1.0e9);
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
    try std.testing.expectEqual(@as(usize, 10), spectroscopy.columnCount());
    try std.testing.expectEqual(@as(u16, 10), lines.lines[0].gas_index);
    try std.testing.expectEqual(@as(u8, 1), lines.lines[0].isotope_number);
    try std.testing.expect(lines.lines[0].abundance_fraction > 0.9);
    try std.testing.expect(lines.sigmaAt(434.6, 250.0, 800.0) > lines.sigmaAt(420.0, 250.0, 800.0));
    try std.testing.expectEqual(@as(f64, 0.0), lines.evaluateAt(434.6, 250.0, 800.0).line_mixing_sigma_cm2_per_molecule);

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

test "reference asset ingest assembles vendor-shaped spectroscopy sidecars into typed evaluation lanes" {
    var line_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "o2a_hitran_subset_07_hit08_tropomi",
    );
    defer line_asset.deinit(std.testing.allocator);

    var sdf_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_strong_line_set,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_sdf_subset",
    );
    defer sdf_asset.deinit(std.testing.allocator);

    var rmf_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_relaxation_matrix,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_rmf_subset",
    );
    defer rmf_asset.deinit(std.testing.allocator);

    var line_list = try line_asset.toSpectroscopyLineList(std.testing.allocator);
    defer line_list.deinit(std.testing.allocator);
    var strong_lines = try sdf_asset.toSpectroscopyStrongLineSet(std.testing.allocator);
    defer strong_lines.deinit(std.testing.allocator);
    var relaxation_matrix = try rmf_asset.toSpectroscopyRelaxationMatrix(std.testing.allocator);
    defer relaxation_matrix.deinit(std.testing.allocator);

    try line_list.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);
    try line_list.applyRuntimeControls(std.testing.allocator, 7, &.{}, null, null, 1.0);

    const evaluation = line_list.evaluateAt(771.3, 255.0, 820.0);
    try std.testing.expect(evaluation.weak_line_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(evaluation.strong_line_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(@abs(evaluation.line_mixing_sigma_cm2_per_molecule) > 0.0);
    try std.testing.expectApproxEqAbs(
        evaluation.weak_line_sigma_cm2_per_molecule + evaluation.strong_line_sigma_cm2_per_molecule,
        evaluation.line_sigma_cm2_per_molecule,
        1e-30,
    );
    try std.testing.expect(evaluation.total_sigma_cm2_per_molecule > 0.0);
}

test "reference asset ingest loads bounded Mie phase tables from vendor-derived subsets" {
    var mie_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .mie_phase_table,
        "data/luts/bundle_manifest.json",
        "mie_dust_phase_subset",
    );
    defer mie_asset.deinit(std.testing.allocator);

    var mie_table = try mie_asset.toMiePhaseTable(std.testing.allocator);
    defer mie_table.deinit(std.testing.allocator);

    const interpolated = mie_table.interpolate(435.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.975225977), interpolated.extinction_scale, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.878231386), interpolated.single_scatter_albedo, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 2.3337024), interpolated.phase_coefficients[1], 1e-6);
    try std.testing.expectEqual(@as(f64, 1.0), interpolated.phase_coefficients[0]);
}

test "reference asset ingest accepts generic cross-section sigma column names" {
    const path = "zig-cache/test-o3-cross-section.csv";
    defer std.fs.cwd().deleteFile(path) catch {};
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data =
            \\wavelength_nm,o3_sigma_cm2_per_molecule
            \\320.0,1.1e-19
            \\325.0,1.4e-19
            \\330.0,1.2e-19
            \\
        ,
    });

    var loaded = try zdisamar.ingest.reference_assets.loadExternalAsset(
        std.testing.allocator,
        .cross_section_table,
        "o3_demo",
        path,
        "csv",
    );
    defer loaded.deinit(std.testing.allocator);

    var cross_sections = try loaded.toCrossSectionTable(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), cross_sections.points.len);
    try std.testing.expectApproxEqAbs(@as(f64, 1.4e-19), cross_sections.points[1].sigma_cm2_per_molecule, 1.0e-30);
}
