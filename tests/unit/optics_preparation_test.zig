const std = @import("std");
const zdisamar = @import("zdisamar");

test "optical preparation bridges tracked assets into transport-ready state" {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(std.testing.allocator);

    var cross_section_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .cross_section_table,
        "data/cross_sections/bundle_manifest.json",
        "no2_405_465_demo",
    );
    defer cross_section_asset.deinit(std.testing.allocator);
    var spectroscopy_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "no2_demo_lines",
    );
    defer spectroscopy_asset.deinit(std.testing.allocator);

    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(std.testing.allocator);

    var profile = try climatology_asset.toClimatologyProfile(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = try cross_section_asset.toCrossSectionTable(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    var spectroscopy = try spectroscopy_asset.toSpectroscopyLineList(std.testing.allocator);
    defer spectroscopy.deinit(std.testing.allocator);
    var lut = try lut_asset.toAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const scene: zdisamar.Scene = .{
        .id = "optics-from-assets",
        .atmosphere = .{
            .layer_count = 5,
            .has_clouds = true,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.18,
            .single_scatter_albedo = 0.95,
            .asymmetry_factor = 0.68,
            .angstrom_exponent = 1.35,
            .reference_wavelength_nm = 550.0,
            .layer_center_km = 2.0,
            .layer_width_km = 2.5,
        },
        .cloud = .{
            .enabled = true,
            .optical_thickness = 0.22,
            .single_scatter_albedo = 0.999,
            .asymmetry_factor = 0.85,
            .angstrom_exponent = 0.25,
            .reference_wavelength_nm = 550.0,
            .top_altitude_km = 3.5,
            .thickness_km = 1.5,
        },
        .geometry = .{
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 20.0,
            .relative_azimuth_deg = 60.0,
        },
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
    };

    var prepared = try zdisamar.optics.prepare.prepareWithSpectroscopy(
        std.testing.allocator,
        scene,
        profile,
        cross_sections,
        spectroscopy,
        lut,
    );
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), prepared.layers.len);
    try std.testing.expectEqual(@as(usize, 15), prepared.sublayers.?.len);
    try std.testing.expect(prepared.mean_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expect(prepared.line_mean_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expectEqual(@as(f64, 0.0), prepared.line_mixing_mean_cross_section_cm2_per_molecule);
    try std.testing.expect(prepared.total_optical_depth > 0.0);
    try std.testing.expect(prepared.gas_optical_depth > 0.0);
    try std.testing.expect(prepared.aerosol_optical_depth > 0.0);
    try std.testing.expect(prepared.d_optical_depth_d_temperature != 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.756), prepared.effective_air_mass_factor, 1e-9);
    try std.testing.expect(prepared.totalCrossSectionAtWavelength(434.6) > prepared.totalCrossSectionAtWavelength(465.0));
    try std.testing.expect(prepared.aerosolOpticalDepthAtWavelength(405.0) > prepared.aerosolOpticalDepthAtWavelength(465.0));
    try std.testing.expect(prepared.totalOpticalDepthAtWavelength(405.0) > prepared.totalOpticalDepthAtWavelength(465.0));
    try std.testing.expect(prepared.sublayers.?[0].gas_extinction_optical_depth > 0.0);
    try std.testing.expect(prepared.sublayers.?[0].d_gas_optical_depth_d_temperature != 0.0);
    try std.testing.expect(prepared.sublayers.?[0].combined_phase_coefficients[0] == 1.0);
    try std.testing.expect(prepared.sublayers.?[0].aerosol_single_scatter_albedo > 0.0);
    try std.testing.expect(prepared.sublayers.?[0].cloud_single_scatter_albedo > 0.0);

    const route = try zdisamar.transport.dispatcher.prepare(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    const result = try zdisamar.transport.dispatcher.executePrepared(
        route,
        prepared.toForwardInput(scene),
    );

    try std.testing.expect(result.toa_radiance > 0.0);
    try std.testing.expect(result.jacobian_column != null);
}

test "optical preparation consumes vendor-shaped strong-line sidecars for bounded O2A mixing" {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(std.testing.allocator);

    var line_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "o2a_hitran_subset_07_hit08_tropomi",
    );
    defer line_asset.deinit(std.testing.allocator);
    var strong_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_strong_line_set,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_sdf_subset",
    );
    defer strong_asset.deinit(std.testing.allocator);
    var rmf_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_relaxation_matrix,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_rmf_subset",
    );
    defer rmf_asset.deinit(std.testing.allocator);
    var cia_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .collision_induced_absorption_table,
        "data/cross_sections/bundle_manifest.json",
        "o2o2_bira_o2a_subset",
    );
    defer cia_asset.deinit(std.testing.allocator);

    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(std.testing.allocator);

    var profile = try climatology_asset.toClimatologyProfile(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = zdisamar.reference_data.CrossSectionTable{
        .points = try std.testing.allocator.dupe(zdisamar.reference_data.CrossSectionPoint, &.{
            .{ .wavelength_nm = 760.8, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 766.15, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 771.5, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);
    var line_list = try line_asset.toSpectroscopyLineList(std.testing.allocator);
    defer line_list.deinit(std.testing.allocator);
    var strong_lines = try strong_asset.toSpectroscopyStrongLineSet(std.testing.allocator);
    defer strong_lines.deinit(std.testing.allocator);
    var relaxation_matrix = try rmf_asset.toSpectroscopyRelaxationMatrix(std.testing.allocator);
    defer relaxation_matrix.deinit(std.testing.allocator);
    var cia_table = try cia_asset.toCollisionInducedAbsorptionTable(std.testing.allocator);
    defer cia_table.deinit(std.testing.allocator);
    try line_list.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);
    var lut = try lut_asset.toAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const scene: zdisamar.Scene = .{
        .id = "o2a-vendor-subset",
        .atmosphere = .{
            .layer_count = 6,
            .has_clouds = true,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.14,
            .single_scatter_albedo = 0.94,
            .asymmetry_factor = 0.70,
            .angstrom_exponent = 1.10,
            .reference_wavelength_nm = 760.0,
            .layer_center_km = 2.0,
            .layer_width_km = 2.5,
        },
        .cloud = .{
            .enabled = true,
            .optical_thickness = 0.18,
            .single_scatter_albedo = 0.998,
            .asymmetry_factor = 0.83,
            .angstrom_exponent = 0.20,
            .reference_wavelength_nm = 760.0,
            .top_altitude_km = 3.5,
            .thickness_km = 1.5,
        },
        .geometry = .{
            .solar_zenith_deg = 55.0,
            .viewing_zenith_deg = 20.0,
            .relative_azimuth_deg = 60.0,
        },
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 771.5,
            .sample_count = 161,
        },
    };

    var prepared = try zdisamar.optics.prepare.prepareWithSpectroscopyAndCollisionInducedAbsorption(
        std.testing.allocator,
        scene,
        profile,
        cross_sections,
        cia_table,
        line_list,
        lut,
    );
    defer prepared.deinit(std.testing.allocator);

    const band_center = prepared.totalCrossSectionAtWavelength(771.3);
    const off_band = prepared.totalCrossSectionAtWavelength(766.0);
    try std.testing.expect(prepared.line_mean_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expect(@abs(prepared.line_mixing_mean_cross_section_cm2_per_molecule) > 0.0);
    try std.testing.expect(prepared.collision_induced_absorption != null);
    try std.testing.expect(prepared.cia_optical_depth > 0.0);
    try std.testing.expect(prepared.collisionInducedOpticalDepthAtWavelength(761.0) > 0.0);
    try std.testing.expect(prepared.collisionInducedOpticalDepthAtWavelength(761.0) > prepared.collisionInducedOpticalDepthAtWavelength(771.3));
    try std.testing.expect(band_center > off_band);
    try std.testing.expect(@abs(prepared.spectroscopy_lines.?.evaluateAt(771.3, prepared.effective_temperature_k, prepared.effective_pressure_hpa).line_mixing_sigma_cm2_per_molecule) > 0.0);
    try std.testing.expect(prepared.sublayers.?[prepared.sublayers.?.len - 1].combined_phase_coefficients[1] >= 0.0);
}

test "optical preparation applies operational O2 and O2-O2 LUT replacements for O2A scenes" {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(std.testing.allocator);
    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(std.testing.allocator);

    var profile = try climatology_asset.toClimatologyProfile(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var lut = try lut_asset.toAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);
    var cross_sections = zdisamar.reference_data.CrossSectionTable{
        .points = try std.testing.allocator.dupe(zdisamar.reference_data.CrossSectionPoint, &.{
            .{ .wavelength_nm = 760.8, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 761.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 761.2, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);

    const o2_lut: zdisamar.OperationalCrossSectionLut = .{
        .wavelengths_nm = &[_]f64{ 760.8, 761.0, 761.2 },
        .coefficients = &[_]f64{
            2.0e-24, 0.30e-24, 0.20e-24, 0.05e-24,
            2.6e-24, 0.35e-24, 0.25e-24, 0.06e-24,
            2.2e-24, 0.32e-24, 0.22e-24, 0.05e-24,
        },
        .temperature_coefficient_count = 2,
        .pressure_coefficient_count = 2,
        .min_temperature_k = 220.0,
        .max_temperature_k = 320.0,
        .min_pressure_hpa = 150.0,
        .max_pressure_hpa = 1000.0,
    };
    const o2o2_lut: zdisamar.OperationalCrossSectionLut = .{
        .wavelengths_nm = &[_]f64{ 760.8, 761.0, 761.2 },
        .coefficients = &[_]f64{
            1.2e-46, 0.20e-46, 0.10e-46, 0.03e-46,
            1.5e-46, 0.20e-46, 0.10e-46, 0.03e-46,
            1.1e-46, 0.18e-46, 0.08e-46, 0.02e-46,
        },
        .temperature_coefficient_count = 2,
        .pressure_coefficient_count = 2,
        .min_temperature_k = 220.0,
        .max_temperature_k = 320.0,
        .min_pressure_hpa = 150.0,
        .max_pressure_hpa = 1000.0,
    };

    const scene: zdisamar.Scene = .{
        .id = "o2a-operational-lut",
        .atmosphere = .{
            .layer_count = 6,
            .sublayer_divisions = 4,
            .has_clouds = true,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.14,
            .single_scatter_albedo = 0.94,
            .asymmetry_factor = 0.70,
            .angstrom_exponent = 1.10,
            .reference_wavelength_nm = 760.0,
            .layer_center_km = 2.0,
            .layer_width_km = 2.5,
        },
        .cloud = .{
            .enabled = true,
            .optical_thickness = 0.18,
            .single_scatter_albedo = 0.998,
            .asymmetry_factor = 0.83,
            .angstrom_exponent = 0.20,
            .reference_wavelength_nm = 760.0,
            .top_altitude_km = 3.5,
            .thickness_km = 1.5,
        },
        .geometry = .{
            .solar_zenith_deg = 55.0,
            .viewing_zenith_deg = 20.0,
            .relative_azimuth_deg = 60.0,
        },
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 9,
        },
        .observation_model = .{
            .instrument = "tropomi",
            .sampling = "operational",
            .noise_model = "s5p_operational",
            .operational_refspec_grid = .{
                .wavelengths_nm = &[_]f64{ 760.8, 761.0, 761.2 },
                .weights = &[_]f64{ 0.15, 0.70, 0.15 },
            },
            .o2_operational_lut = o2_lut,
            .o2o2_operational_lut = o2o2_lut,
        },
    };

    var prepared = try zdisamar.optics.prepare.prepareWithSpectroscopyAndCollisionInducedAbsorption(
        std.testing.allocator,
        scene,
        profile,
        cross_sections,
        null,
        null,
        lut,
    );
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.operational_o2_lut.enabled());
    try std.testing.expect(prepared.operational_o2o2_lut.enabled());
    try std.testing.expect(prepared.line_mean_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expect(prepared.cia_mean_cross_section_cm5_per_molecule2 > 0.0);
    try std.testing.expect(prepared.cia_optical_depth > 0.0);
    try std.testing.expect(prepared.totalCrossSectionAtWavelength(761.0) > prepared.totalCrossSectionAtWavelength(760.8));
    try std.testing.expect(prepared.collisionInducedOpticalDepthAtWavelength(761.0) > prepared.collisionInducedOpticalDepthAtWavelength(760.8));
    try std.testing.expect(prepared.sublayers.?[0].line_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expect(prepared.sublayers.?[0].cia_sigma_cm5_per_molecule2 > 0.0);

    const weighted_expected_o2 =
        0.15 * o2_lut.sigmaAt(760.8, prepared.effective_temperature_k, prepared.effective_pressure_hpa) +
        0.70 * o2_lut.sigmaAt(761.0, prepared.effective_temperature_k, prepared.effective_pressure_hpa) +
        0.15 * o2_lut.sigmaAt(761.2, prepared.effective_temperature_k, prepared.effective_pressure_hpa);
    const weighted_expected_o2o2 =
        0.15 * o2o2_lut.sigmaAt(760.8, prepared.effective_temperature_k, prepared.effective_pressure_hpa) +
        0.70 * o2o2_lut.sigmaAt(761.0, prepared.effective_temperature_k, prepared.effective_pressure_hpa) +
        0.15 * o2o2_lut.sigmaAt(761.2, prepared.effective_temperature_k, prepared.effective_pressure_hpa);
    const uniform_mean_o2 =
        (o2_lut.sigmaAt(760.8, prepared.effective_temperature_k, prepared.effective_pressure_hpa) +
            o2_lut.sigmaAt(761.0, prepared.effective_temperature_k, prepared.effective_pressure_hpa) +
            o2_lut.sigmaAt(761.2, prepared.effective_temperature_k, prepared.effective_pressure_hpa)) / 3.0;

    try std.testing.expectApproxEqAbs(weighted_expected_o2, prepared.line_mean_cross_section_cm2_per_molecule, 1.0e-28);
    try std.testing.expectApproxEqAbs(weighted_expected_o2o2, prepared.cia_mean_cross_section_cm5_per_molecule2, 1.0e-50);
    try std.testing.expect(@abs(prepared.line_mean_cross_section_cm2_per_molecule - uniform_mean_o2) > 1.0e-26);
}

test "optical preparation materializes RTM-style gas sublayers with stable parent aggregation" {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(std.testing.allocator);

    var cross_section_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .cross_section_table,
        "data/cross_sections/bundle_manifest.json",
        "no2_405_465_demo",
    );
    defer cross_section_asset.deinit(std.testing.allocator);
    var spectroscopy_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "no2_demo_lines",
    );
    defer spectroscopy_asset.deinit(std.testing.allocator);
    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(std.testing.allocator);

    var profile = try climatology_asset.toClimatologyProfile(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = try cross_section_asset.toCrossSectionTable(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    var spectroscopy = try spectroscopy_asset.toSpectroscopyLineList(std.testing.allocator);
    defer spectroscopy.deinit(std.testing.allocator);
    var lut = try lut_asset.toAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const scene: zdisamar.Scene = .{
        .id = "sublayer-grid",
        .atmosphere = .{
            .layer_count = 4,
            .sublayer_divisions = 4,
            .has_clouds = false,
            .has_aerosols = false,
        },
        .geometry = .{
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 10.0,
            .relative_azimuth_deg = 30.0,
        },
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
    };

    var prepared = try zdisamar.optics.prepare.prepareWithSpectroscopy(
        std.testing.allocator,
        scene,
        profile,
        cross_sections,
        spectroscopy,
        lut,
    );
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 16), prepared.sublayers.?.len);

    for (prepared.layers) |layer| {
        try std.testing.expectEqual(@as(u32, 4), layer.sublayer_count);
        var summed_gas_optical_depth: f64 = 0.0;
        var summed_temperature_derivative: f64 = 0.0;
        const start = layer.sublayer_start_index;
        const stop = start + layer.sublayer_count;
        for (prepared.sublayers.?[start..stop]) |sublayer| {
            try std.testing.expectEqual(layer.layer_index, sublayer.parent_layer_index);
            summed_gas_optical_depth += sublayer.gas_extinction_optical_depth;
            summed_temperature_derivative += sublayer.d_gas_optical_depth_d_temperature;
        }

        try std.testing.expectApproxEqAbs(layer.gas_optical_depth, summed_gas_optical_depth, 1e-12);
        try std.testing.expect(summed_temperature_derivative != 0.0);
    }
}

test "optical preparation distributes aerosol and cloud optical depth across HG-style sublayers" {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(std.testing.allocator);
    var cross_section_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .cross_section_table,
        "data/cross_sections/bundle_manifest.json",
        "no2_405_465_demo",
    );
    defer cross_section_asset.deinit(std.testing.allocator);
    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(std.testing.allocator);

    var profile = try climatology_asset.toClimatologyProfile(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = try cross_section_asset.toCrossSectionTable(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    var lut = try lut_asset.toAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const scene: zdisamar.Scene = .{
        .id = "hg-sublayers",
        .atmosphere = .{
            .layer_count = 5,
            .sublayer_divisions = 3,
            .has_clouds = true,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.21,
            .single_scatter_albedo = 0.94,
            .asymmetry_factor = 0.72,
            .angstrom_exponent = 1.2,
            .reference_wavelength_nm = 550.0,
            .layer_center_km = 2.0,
            .layer_width_km = 2.0,
        },
        .cloud = .{
            .enabled = true,
            .optical_thickness = 0.25,
            .single_scatter_albedo = 0.998,
            .asymmetry_factor = 0.84,
            .angstrom_exponent = 0.25,
            .reference_wavelength_nm = 550.0,
            .top_altitude_km = 4.0,
            .thickness_km = 1.5,
        },
        .geometry = .{
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 10.0,
            .relative_azimuth_deg = 30.0,
        },
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
    };

    var prepared = try zdisamar.optics.prepare.prepare(
        std.testing.allocator,
        scene,
        profile,
        cross_sections,
        lut,
    );
    defer prepared.deinit(std.testing.allocator);

    var aerosol_sum: f64 = 0.0;
    var cloud_sum: f64 = 0.0;
    var aerosol_peak = prepared.sublayers.?[0].aerosol_optical_depth;
    var cloud_peak = prepared.sublayers.?[0].cloud_optical_depth;
    for (prepared.sublayers.?) |sublayer| {
        aerosol_sum += sublayer.aerosol_optical_depth;
        cloud_sum += sublayer.cloud_optical_depth;
        aerosol_peak = @max(aerosol_peak, sublayer.aerosol_optical_depth);
        cloud_peak = @max(cloud_peak, sublayer.cloud_optical_depth);
        try std.testing.expectEqual(@as(f64, 1.0), sublayer.combined_phase_coefficients[0]);
    }

    try std.testing.expectApproxEqAbs(scene.aerosol.optical_depth, aerosol_sum, 1e-12);
    try std.testing.expectApproxEqAbs(scene.cloud.optical_thickness, cloud_sum, 1e-12);
    try std.testing.expect(aerosol_peak > 0.0);
    try std.testing.expect(cloud_peak > 0.0);
}

test "optical preparation interpolates bounded Mie coefficient subsets when provided" {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(std.testing.allocator);
    var cross_section_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .cross_section_table,
        "data/cross_sections/bundle_manifest.json",
        "no2_405_465_demo",
    );
    defer cross_section_asset.deinit(std.testing.allocator);
    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(std.testing.allocator);
    var mie_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .mie_phase_table,
        "data/luts/bundle_manifest.json",
        "mie_dust_phase_subset",
    );
    defer mie_asset.deinit(std.testing.allocator);

    var profile = try climatology_asset.toClimatologyProfile(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = try cross_section_asset.toCrossSectionTable(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    var lut = try lut_asset.toAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);
    var mie_table = try mie_asset.toMiePhaseTable(std.testing.allocator);
    defer mie_table.deinit(std.testing.allocator);

    const scene: zdisamar.Scene = .{
        .id = "mie-sublayers",
        .atmosphere = .{
            .layer_count = 4,
            .sublayer_divisions = 3,
            .has_clouds = false,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.18,
            .single_scatter_albedo = 0.94,
            .asymmetry_factor = 0.72,
            .angstrom_exponent = 1.2,
            .reference_wavelength_nm = 550.0,
            .layer_center_km = 2.0,
            .layer_width_km = 2.0,
        },
        .geometry = .{
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 10.0,
            .relative_azimuth_deg = 30.0,
        },
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
    };

    var prepared = try zdisamar.optics.prepare.prepareWithParticleTables(
        std.testing.allocator,
        scene,
        profile,
        cross_sections,
        null,
        null,
        lut,
        mie_table,
        null,
    );
    defer prepared.deinit(std.testing.allocator);

    var aerosol_sum: f64 = 0.0;
    for (prepared.sublayers.?) |sublayer| aerosol_sum += sublayer.aerosol_optical_depth;

    const first = prepared.sublayers.?[0];
    try std.testing.expectApproxEqAbs(@as(f64, 0.17554067586), aerosol_sum, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.878231386), first.aerosol_single_scatter_albedo, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 2.3337024), first.aerosol_phase_coefficients[1], 1e-6);
    try std.testing.expect(first.combined_phase_coefficients[1] > scene.aerosol.asymmetry_factor);
}
