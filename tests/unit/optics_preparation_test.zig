const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.preparation;
const PreparationTransport = OpticsPrepare.transport;
const TransportDispatcher = internal.kernels.transport.dispatcher;
const centimeters_per_kilometer = 1.0e5;
const AbsorberSpecies = @typeInfo(@TypeOf(@as(zdisamar.Absorber, .{}).resolved_species)).optional.child;

fn prepareWithSpectroscopy(
    allocator: std.mem.Allocator,
    scene: *const zdisamar.Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList,
    lut: *const ReferenceData.AirmassFactorLut,
) !OpticsPrepare.PreparedOpticalState {
    return OpticsPrepare.prepare(allocator, scene, .{
        .profile = profile,
        .cross_sections = cross_sections,
        .spectroscopy_lines = spectroscopy_lines,
        .lut = lut,
    });
}

fn prepareWithSpectroscopyAndCollisionInducedAbsorption(
    allocator: std.mem.Allocator,
    scene: *const zdisamar.Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList,
    lut: *const ReferenceData.AirmassFactorLut,
) !OpticsPrepare.PreparedOpticalState {
    return OpticsPrepare.prepare(allocator, scene, .{
        .profile = profile,
        .cross_sections = cross_sections,
        .collision_induced_absorption = collision_induced_absorption,
        .spectroscopy_lines = spectroscopy_lines,
        .lut = lut,
    });
}

fn prepareWithParticleTables(
    allocator: std.mem.Allocator,
    scene: *const zdisamar.Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList,
    lut: *const ReferenceData.AirmassFactorLut,
    aerosol_mie: ?*const ReferenceData.MiePhaseTable,
    cloud_mie: ?*const ReferenceData.MiePhaseTable,
) !OpticsPrepare.PreparedOpticalState {
    return OpticsPrepare.prepare(allocator, scene, .{
        .profile = profile,
        .cross_sections = cross_sections,
        .collision_induced_absorption = collision_induced_absorption,
        .spectroscopy_lines = spectroscopy_lines,
        .lut = lut,
        .aerosol_mie = aerosol_mie,
        .cloud_mie = cloud_mie,
    });
}

fn prepareVendorAnchoredSwirMultiGasCase(
    allocator: std.mem.Allocator,
    nh3_scale: f64,
) !OpticsPrepare.PreparedOpticalState {
    var profile = ReferenceData.ClimatologyProfile{
        .rows = try allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.0e19 },
            .{ .altitude_km = 4.0, .pressure_hpa = 820.0, .temperature_k = 275.0, .air_number_density_cm3 = 1.7e19 },
            .{ .altitude_km = 8.0, .pressure_hpa = 620.0, .temperature_k = 255.0, .air_number_density_cm3 = 1.3e19 },
            .{ .altitude_km = 12.0, .pressure_hpa = 430.0, .temperature_k = 235.0, .air_number_density_cm3 = 9.0e18 },
        }),
    };
    defer profile.deinit(allocator);

    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 2340.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 2350.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 2360.0, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
    defer cross_sections.deinit(allocator);

    var line_list = ReferenceData.SpectroscopyLineList{
        .lines = try allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{ .gas_index = 11, .isotope_number = 1, .center_wavelength_nm = 2349.82, .line_strength_cm2_per_molecule = 5.5e-15, .air_half_width_nm = 0.0010, .temperature_exponent = 0.72, .lower_state_energy_cm1 = 110.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 11, .isotope_number = 3, .center_wavelength_nm = 2349.98, .line_strength_cm2_per_molecule = 4.8e-15, .air_half_width_nm = 0.0010, .temperature_exponent = 0.72, .lower_state_energy_cm1 = 118.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 1, .isotope_number = 1, .center_wavelength_nm = 2347.18, .line_strength_cm2_per_molecule = 1.8e-15, .air_half_width_nm = 0.0011, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 95.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 1, .isotope_number = 7, .center_wavelength_nm = 2347.34, .line_strength_cm2_per_molecule = 1.4e-15, .air_half_width_nm = 0.0011, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 102.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 6, .isotope_number = 1, .center_wavelength_nm = 2352.36, .line_strength_cm2_per_molecule = 9.0e-16, .air_half_width_nm = 0.0012, .temperature_exponent = 0.68, .lower_state_energy_cm1 = 130.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 6, .isotope_number = 4, .center_wavelength_nm = 2352.58, .line_strength_cm2_per_molecule = 8.5e-16, .air_half_width_nm = 0.0012, .temperature_exponent = 0.68, .lower_state_energy_cm1 = 138.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 5, .isotope_number = 1, .center_wavelength_nm = 2342.42, .line_strength_cm2_per_molecule = 6.5e-16, .air_half_width_nm = 0.0010, .temperature_exponent = 0.70, .lower_state_energy_cm1 = 90.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 5, .isotope_number = 7, .center_wavelength_nm = 2342.68, .line_strength_cm2_per_molecule = 5.8e-16, .air_half_width_nm = 0.0010, .temperature_exponent = 0.70, .lower_state_energy_cm1 = 98.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        }),
    };
    defer line_list.deinit(allocator);

    var lut = try ReferenceData.buildDemoAirmassFactorLut(allocator);
    defer lut.deinit(allocator);

    const scene: zdisamar.Scene = .{
        .id = "vendor-anchored-h2o-nh3-unit",
        .surface = .{
            .albedo = 0.18,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 35.0,
            .viewing_zenith_deg = 15.0,
            .relative_azimuth_deg = 40.0,
        },
        .atmosphere = .{
            .layer_count = 3,
            .sublayer_divisions = 2,
        },
        .spectral_grid = .{
            .start_nm = 2340.0,
            .end_nm = 2360.0,
            .sample_count = 81,
        },
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "nh3",
                    .species = "nh3",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "nh3").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 12.0 * nh3_scale },
                        .{ 430.0, 3.0 * nh3_scale },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .isotopes_sim = &.{ 1, 2 },
                            .threshold_line_sim = 3.0e-5,
                            .cutoff_sim_cm1 = 10.0,
                            .active_stage = .simulation,
                        },
                    },
                },
                zdisamar.Absorber{
                    .id = "h2o",
                    .species = "h2o",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "h2o").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 12000.0 },
                        .{ 430.0, 3500.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .isotopes_sim = &.{ 1, 2, 3, 4, 5, 6 },
                            .threshold_line_sim = 3.0e-5,
                            .cutoff_sim_cm1 = 10.0,
                            .active_stage = .simulation,
                        },
                    },
                },
                zdisamar.Absorber{
                    .id = "ch4",
                    .species = "ch4",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "ch4").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 1800.0 },
                        .{ 430.0, 950.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .isotopes_sim = &.{ 1, 2, 3 },
                            .threshold_line_sim = 3.0e-5,
                            .cutoff_sim_cm1 = 10.0,
                            .active_stage = .simulation,
                        },
                    },
                },
                zdisamar.Absorber{
                    .id = "co",
                    .species = "co",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "co").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 120.0 },
                        .{ 430.0, 65.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .isotopes_sim = &.{ 1, 2, 3, 4, 5, 6 },
                            .threshold_line_sim = 3.0e-5,
                            .cutoff_sim_cm1 = 10.0,
                            .active_stage = .simulation,
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.25,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.020833333333333332,
            .high_resolution_half_span_nm = 0.75,
            .adaptive_reference_grid = .{
                .points_per_fwhm = 12,
                .strong_line_min_divisions = 4,
                .strong_line_max_divisions = 16,
            },
        },
    };

    return prepareWithSpectroscopy(
        allocator,
        &scene,
        &profile,
        &cross_sections,
        &line_list,
        &lut,
    );
}

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

    var prepared = try prepareWithSpectroscopy(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        &spectroscopy,
        &lut,
    );
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), prepared.layers.len);
    try std.testing.expectEqual(@as(usize, 15), prepared.sublayers.?.len);
    try std.testing.expect(prepared.mean_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expect(prepared.line_mean_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expectEqual(@as(f64, 0.0), prepared.line_mixing_mean_cross_section_cm2_per_molecule);
    try std.testing.expect(prepared.total_optical_depth > 0.0);
    try std.testing.expect(prepared.gas_optical_depth > 0.0);
    try std.testing.expect(prepared.layers[0].gas_scattering_optical_depth > 0.0);
    try std.testing.expect(prepared.aerosol_optical_depth > 0.0);
    try std.testing.expect(prepared.d_optical_depth_d_temperature != 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.756), prepared.effective_air_mass_factor, 1e-9);
    try std.testing.expect(prepared.totalCrossSectionAtWavelength(434.6) > prepared.totalCrossSectionAtWavelength(465.0));
    try std.testing.expect(prepared.aerosolOpticalDepthAtWavelength(405.0) > prepared.aerosolOpticalDepthAtWavelength(465.0));
    try std.testing.expect(prepared.totalOpticalDepthAtWavelength(405.0) > prepared.totalOpticalDepthAtWavelength(465.0));
    try std.testing.expect(prepared.sublayers.?[0].gas_extinction_optical_depth > 0.0);
    try std.testing.expect(prepared.sublayers.?[0].gas_scattering_optical_depth > 0.0);
    try std.testing.expect(prepared.sublayers.?[0].d_gas_optical_depth_d_temperature != 0.0);
    try std.testing.expect(prepared.sublayers.?[0].combined_phase_coefficients[0] == 1.0);
    try std.testing.expect(prepared.sublayers.?[0].aerosol_single_scatter_albedo > 0.0);
    try std.testing.expect(prepared.sublayers.?[0].cloud_single_scatter_albedo > 0.0);

    const route = try TransportDispatcher.prepare(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    const result = try TransportDispatcher.executePrepared(
        std.testing.allocator,
        route,
        PreparationTransport.toForwardInput(&prepared, &scene),
    );

    try std.testing.expect(result.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result.toa_reflectance_factor <= 1.0);
    try std.testing.expect(result.jacobian_column != null);
}

test "optical preparation uses staged non-o2 line-gas profiles instead of O2 density" {
    var profile = ReferenceData.ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.0e19 },
            .{ .altitude_km = 10.0, .pressure_hpa = 500.0, .temperature_k = 250.0, .air_number_density_cm3 = 1.0e19 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 760.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 760.5, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);

    var line_list = ReferenceData.SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{
                .gas_index = 2,
                .isotope_number = 1,
                .center_wavelength_nm = 760.25,
                .line_strength_cm2_per_molecule = 2.0e-21,
                .air_half_width_nm = 0.001,
                .temperature_exponent = 0.7,
                .lower_state_energy_cm1 = 120.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
        }),
    };
    defer line_list.deinit(std.testing.allocator);

    var lut = try ReferenceData.buildDemoAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const scene: zdisamar.Scene = .{
        .id = "co2-line-gas-profile",
        .atmosphere = .{
            .layer_count = 1,
        },
        .geometry = .{
            .solar_zenith_deg = 30.0,
            .viewing_zenith_deg = 10.0,
            .relative_azimuth_deg = 30.0,
        },
        .spectral_grid = .{
            .start_nm = 760.0,
            .end_nm = 760.5,
            .sample_count = 5,
        },
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "co2",
                    .species = "co2",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "co2").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 400.0 },
                        .{ 500.0, 200.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
        },
    };

    var prepared = try prepareWithSpectroscopy(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        &line_list,
        &lut,
    );
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.column_density_factor > 0.0);
    try std.testing.expect(prepared.air_column_density_factor > prepared.column_density_factor);
    try std.testing.expect(prepared.column_density_factor < prepared.air_column_density_factor * 1.0e-3);
    try std.testing.expectApproxEqAbs(@as(f64, 6.722222222222222e15), prepared.sublayers.?[0].absorber_number_density_cm3, 5.0e13);
    try std.testing.expectApproxEqAbs(@as(f64, 3.8408333333333335e18), prepared.sublayers.?[0].oxygen_number_density_cm3, 5.0e16);
}

test "optical preparation splits vendor-anchored swir line gases into per-species prepared absorbers" {
    var low_nh3 = try prepareVendorAnchoredSwirMultiGasCase(std.testing.allocator, 0.25);
    defer low_nh3.deinit(std.testing.allocator);
    var high_nh3 = try prepareVendorAnchoredSwirMultiGasCase(std.testing.allocator, 1.0);
    defer high_nh3.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), high_nh3.line_absorbers.len);
    try std.testing.expect(high_nh3.spectroscopy_lines == null);
    try std.testing.expectEqual(@as(usize, 1), high_nh3.line_absorbers[0].line_list.lines.len);
    try std.testing.expectEqual(@as(usize, 1), high_nh3.line_absorbers[1].line_list.lines.len);
    try std.testing.expectEqual(@as(usize, 1), high_nh3.line_absorbers[2].line_list.lines.len);
    try std.testing.expectEqual(@as(usize, 1), high_nh3.line_absorbers[3].line_list.lines.len);
    try std.testing.expect(high_nh3.line_absorbers[0].column_density_factor > 0.0);
    try std.testing.expect(high_nh3.line_absorbers[1].column_density_factor > high_nh3.line_absorbers[0].column_density_factor);

    const nh3_tau_delta =
        high_nh3.totalOpticalDepthAtWavelength(2349.82) -
        low_nh3.totalOpticalDepthAtWavelength(2349.82);
    const h2o_tau_delta = @abs(
        high_nh3.totalOpticalDepthAtWavelength(2347.18) -
            low_nh3.totalOpticalDepthAtWavelength(2347.18),
    );
    const ch4_tau_delta = @abs(
        high_nh3.totalOpticalDepthAtWavelength(2352.36) -
            low_nh3.totalOpticalDepthAtWavelength(2352.36),
    );

    try std.testing.expect(nh3_tau_delta > 0.0);
    try std.testing.expect(nh3_tau_delta > h2o_tau_delta * 10.0);
    try std.testing.expect(nh3_tau_delta > ch4_tau_delta * 10.0);
    try std.testing.expect(high_nh3.sublayers.?[0].absorber_number_density_cm3 > high_nh3.line_absorbers[1].number_densities_cm3[0]);
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
    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
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
    try line_list.applyRuntimeControls(std.testing.allocator, 7, &.{}, null, null, 1.0);
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

    var prepared = try prepareWithSpectroscopyAndCollisionInducedAbsorption(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        &cia_table,
        &line_list,
        &lut,
    );
    defer prepared.deinit(std.testing.allocator);

    const band_center = prepared.totalCrossSectionAtWavelength(771.3);
    const off_band = prepared.totalCrossSectionAtWavelength(766.0);
    const gas_tau_band_center = prepared.gasOpticalDepthAtWavelength(771.3);
    const gas_tau_off_band = prepared.gasOpticalDepthAtWavelength(766.0);
    try std.testing.expect(prepared.line_mean_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expect(@abs(prepared.line_mixing_mean_cross_section_cm2_per_molecule) > 0.0);
    try std.testing.expect(prepared.collision_induced_absorption != null);
    try std.testing.expect(prepared.cia_optical_depth > 0.0);
    try std.testing.expect(prepared.column_density_factor > 1.0e24);
    try std.testing.expect(prepared.collisionInducedOpticalDepthAtWavelength(761.0) > 0.0);
    try std.testing.expect(prepared.collisionInducedOpticalDepthAtWavelength(761.0) > prepared.collisionInducedOpticalDepthAtWavelength(771.3));
    try std.testing.expect(band_center > off_band);
    try std.testing.expect(gas_tau_band_center > 0.0);
    try std.testing.expect(gas_tau_band_center > gas_tau_off_band);
    try std.testing.expect(@abs(prepared.spectroscopy_lines.?.evaluateAt(771.3, prepared.effective_temperature_k, prepared.effective_pressure_hpa).line_mixing_sigma_cm2_per_molecule) > 0.0);
    try std.testing.expect(prepared.sublayers.?[prepared.sublayers.?.len - 1].combined_phase_coefficients[1] >= 0.0);
}

test "pseudo-spherical prepared carriers preserve strong-line prepared states" {
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

    var profile = try climatology_asset.toClimatologyProfile(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
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
    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(std.testing.allocator);
    var lut = try lut_asset.toAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const scene: zdisamar.Scene = .{
        .id = "o2a-pseudo-strong-line",
        .atmosphere = .{
            .layer_count = 6,
            .sublayer_divisions = 3,
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

    var prepared = try prepareWithSpectroscopyAndCollisionInducedAbsorption(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        &cia_table,
        &line_list,
        &lut,
    );
    defer prepared.deinit(std.testing.allocator);

    const transport_common = internal.kernels.transport.common;
    const sublayers = prepared.sublayers.?;
    const strong_line_states = prepared.strong_line_states.?;
    const solver_layer_count = sublayers.len;
    const wavelength_nm = 771.3;
    const continuum_sigma = (ReferenceData.CrossSectionTable{
        .points = prepared.continuum_points,
    }).interpolateSigma(wavelength_nm);

    const attenuation_layers = try std.testing.allocator.alloc(transport_common.LayerInput, solver_layer_count);
    defer std.testing.allocator.free(attenuation_layers);
    const attenuation_samples = try std.testing.allocator.alloc(
        transport_common.PseudoSphericalSample,
        solver_layer_count * scene.atmosphere.sublayer_divisions,
    );
    defer std.testing.allocator.free(attenuation_samples);
    const level_sample_starts = try std.testing.allocator.alloc(usize, solver_layer_count + 1);
    defer std.testing.allocator.free(level_sample_starts);
    const level_altitudes_km = try std.testing.allocator.alloc(f64, solver_layer_count + 1);
    defer std.testing.allocator.free(level_altitudes_km);

    var selected_index: ?usize = null;
    for (strong_line_states, 0..) |prepared_state, index| {
        if (prepared_state.line_count == 0) continue;
        strong_line_states[index].population_t[0] *= 1.25;
        selected_index = index;
        break;
    }
    try std.testing.expect(selected_index != null);

    try std.testing.expect(PreparationTransport.fillPseudoSphericalGridAtWavelength(
        &prepared,
        &scene,
        wavelength_nm,
        solver_layer_count,
        attenuation_layers,
        attenuation_samples,
        level_sample_starts,
        level_altitudes_km,
    ));

    const sublayer = sublayers[selected_index.?];
    const prepared_sigma = prepared.spectroscopy_lines.?.sigmaAtPrepared(
        wavelength_nm,
        sublayer.temperature_k,
        sublayer.pressure_hpa,
        &strong_line_states[selected_index.?],
    );
    const raw_sigma = prepared.spectroscopy_lines.?.sigmaAt(
        wavelength_nm,
        sublayer.temperature_k,
        sublayer.pressure_hpa,
    );
    try std.testing.expect(@abs(prepared_sigma - raw_sigma) > 0.0);

    const sample_index = level_sample_starts[selected_index.?] + 1;
    const sample = attenuation_samples[sample_index];
    const expected_optical_depth =
        sample.thickness_km *
        ((continuum_sigma + prepared_sigma) * sublayer.oxygen_number_density_cm3 * centimeters_per_kilometer +
            ReferenceData.Rayleigh.crossSectionCm2(wavelength_nm) * sublayer.number_density_cm3 * centimeters_per_kilometer +
            prepared.collision_induced_absorption.?.sigmaAt(wavelength_nm, sublayer.temperature_k) *
                sublayer.oxygen_number_density_cm3 *
                sublayer.oxygen_number_density_cm3 *
                centimeters_per_kilometer);
    const raw_optical_depth =
        sample.thickness_km *
        ((continuum_sigma + raw_sigma) * sublayer.oxygen_number_density_cm3 * centimeters_per_kilometer +
            ReferenceData.Rayleigh.crossSectionCm2(wavelength_nm) * sublayer.number_density_cm3 * centimeters_per_kilometer +
            prepared.collision_induced_absorption.?.sigmaAt(wavelength_nm, sublayer.temperature_k) *
                sublayer.oxygen_number_density_cm3 *
                sublayer.oxygen_number_density_cm3 *
                centimeters_per_kilometer);

    try std.testing.expectApproxEqRel(expected_optical_depth, sample.optical_depth, 1e-12);
    try std.testing.expect(@abs(sample.optical_depth - raw_optical_depth) > 0.0);
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
    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
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
            .instrument = .tropomi,
            .sampling = .operational,
            .noise_model = .s5p_operational,
            .reference_radiance = &[_]f64{1.0} ** 9,
            .ingested_noise_sigma = &[_]f64{0.02} ** 9,
            .operational_refspec_grid = .{
                .wavelengths_nm = &[_]f64{ 760.8, 761.0, 761.2 },
                .weights = &[_]f64{ 0.15, 0.70, 0.15 },
            },
            .o2_operational_lut = o2_lut,
            .o2o2_operational_lut = o2o2_lut,
        },
    };

    var prepared = try prepareWithSpectroscopyAndCollisionInducedAbsorption(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        null,
        null,
        &lut,
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

test "operational O2 LUT keeps non-O2 line absorbers in total and pseudo-spherical optics" {
    var profile = ReferenceData.ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.0e19 },
            .{ .altitude_km = 8.0, .pressure_hpa = 600.0, .temperature_k = 255.0, .air_number_density_cm3 = 1.2e19 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 760.8, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 761.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 761.2, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);

    var line_list = ReferenceData.SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{
                .gas_index = 1,
                .isotope_number = 1,
                .center_wavelength_nm = 761.0,
                .line_strength_cm2_per_molecule = 4.0e-21,
                .air_half_width_nm = 0.0010,
                .temperature_exponent = 0.7,
                .lower_state_energy_cm1 = 100.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
        }),
    };
    defer line_list.deinit(std.testing.allocator);

    var lut = try ReferenceData.buildDemoAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const o2_lut: zdisamar.OperationalCrossSectionLut = .{
        .wavelengths_nm = &[_]f64{ 760.8, 761.0, 761.2 },
        .coefficients = &[_]f64{
            0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 0.0,
        },
        .temperature_coefficient_count = 2,
        .pressure_coefficient_count = 2,
        .min_temperature_k = 220.0,
        .max_temperature_k = 320.0,
        .min_pressure_hpa = 150.0,
        .max_pressure_hpa = 1000.0,
    };

    const base_scene: zdisamar.Scene = .{
        .id = "o2-lut-base",
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 15.0,
            .relative_azimuth_deg = 20.0,
        },
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 9,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .operational,
            .noise_model = .shot_noise,
            .o2_operational_lut = o2_lut,
        },
    };

    var base_prepared = try prepareWithSpectroscopy(
        std.testing.allocator,
        &base_scene,
        &profile,
        &cross_sections,
        null,
        &lut,
    );
    defer base_prepared.deinit(std.testing.allocator);

    var line_scene = base_scene;
    line_scene.id = "o2-lut-with-h2o";
    line_scene.absorbers = .{
        .items = &.{
            zdisamar.Absorber{
                .id = "h2o",
                .species = "h2o",
                .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "h2o").?,
                .profile_source = .atmosphere,
                .volume_mixing_ratio_profile_ppmv = &.{
                    .{ 1000.0, 12000.0 },
                    .{ 600.0, 3500.0 },
                },
                .spectroscopy = .{
                    .mode = .line_by_line,
                    .line_gas_controls = .{
                        .active_stage = .simulation,
                    },
                },
            },
        },
    };

    var line_prepared = try prepareWithSpectroscopy(
        std.testing.allocator,
        &line_scene,
        &profile,
        &cross_sections,
        &line_list,
        &lut,
    );
    defer line_prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), line_prepared.line_absorbers.len);
    try std.testing.expect(line_prepared.column_density_factor > base_prepared.column_density_factor);
    try std.testing.expect(line_prepared.totalCrossSectionAtWavelength(761.0) > base_prepared.totalCrossSectionAtWavelength(761.0));

    const transport_common = internal.kernels.transport.common;
    const solver_layer_count = line_prepared.sublayers.?.len;
    const wavelength_nm = 761.0;

    const base_layers = try std.testing.allocator.alloc(transport_common.LayerInput, solver_layer_count);
    defer std.testing.allocator.free(base_layers);
    const base_samples = try std.testing.allocator.alloc(
        transport_common.PseudoSphericalSample,
        solver_layer_count * base_scene.atmosphere.sublayer_divisions,
    );
    defer std.testing.allocator.free(base_samples);
    const base_starts = try std.testing.allocator.alloc(usize, solver_layer_count + 1);
    defer std.testing.allocator.free(base_starts);
    const base_altitudes = try std.testing.allocator.alloc(f64, solver_layer_count + 1);
    defer std.testing.allocator.free(base_altitudes);

    const line_layers = try std.testing.allocator.alloc(transport_common.LayerInput, solver_layer_count);
    defer std.testing.allocator.free(line_layers);
    const line_samples = try std.testing.allocator.alloc(
        transport_common.PseudoSphericalSample,
        solver_layer_count * line_scene.atmosphere.sublayer_divisions,
    );
    defer std.testing.allocator.free(line_samples);
    const line_starts = try std.testing.allocator.alloc(usize, solver_layer_count + 1);
    defer std.testing.allocator.free(line_starts);
    const line_altitudes = try std.testing.allocator.alloc(f64, solver_layer_count + 1);
    defer std.testing.allocator.free(line_altitudes);

    try std.testing.expect(PreparationTransport.fillPseudoSphericalGridAtWavelength(
        &base_prepared,
        &base_scene,
        wavelength_nm,
        solver_layer_count,
        base_layers,
        base_samples,
        base_starts,
        base_altitudes,
    ));
    try std.testing.expect(PreparationTransport.fillPseudoSphericalGridAtWavelength(
        &line_prepared,
        &line_scene,
        wavelength_nm,
        solver_layer_count,
        line_layers,
        line_samples,
        line_starts,
        line_altitudes,
    ));

    var base_optical_depth_sum: f64 = 0.0;
    for (base_samples[0..base_starts[solver_layer_count]]) |sample| {
        base_optical_depth_sum += sample.optical_depth;
    }
    var line_optical_depth_sum: f64 = 0.0;
    for (line_samples[0..line_starts[solver_layer_count]]) |sample| {
        line_optical_depth_sum += sample.optical_depth;
    }

    try std.testing.expect(line_optical_depth_sum > base_optical_depth_sum);
}

test "operational O2 LUT keeps continuum scoped to oxygen in mixed-gas preparation" {
    var profile = ReferenceData.ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.0e19 },
            .{ .altitude_km = 8.0, .pressure_hpa = 600.0, .temperature_k = 255.0, .air_number_density_cm3 = 1.2e19 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 760.8, .sigma_cm2_per_molecule = 4.0e-26 },
            .{ .wavelength_nm = 761.0, .sigma_cm2_per_molecule = 4.5e-26 },
            .{ .wavelength_nm = 761.2, .sigma_cm2_per_molecule = 4.0e-26 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);

    var line_list = ReferenceData.SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{
                .gas_index = 1,
                .isotope_number = 1,
                .center_wavelength_nm = 761.0,
                .line_strength_cm2_per_molecule = 0.0,
                .air_half_width_nm = 0.0010,
                .temperature_exponent = 0.7,
                .lower_state_energy_cm1 = 100.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
        }),
    };
    defer line_list.deinit(std.testing.allocator);

    var lut = try ReferenceData.buildDemoAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

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

    const base_scene: zdisamar.Scene = .{
        .id = "o2-lut-continuum-base",
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 15.0,
            .relative_azimuth_deg = 20.0,
        },
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 9,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .operational,
            .noise_model = .shot_noise,
            .o2_operational_lut = o2_lut,
        },
    };

    var base_prepared = try prepareWithSpectroscopy(
        std.testing.allocator,
        &base_scene,
        &profile,
        &cross_sections,
        null,
        &lut,
    );
    defer base_prepared.deinit(std.testing.allocator);

    var line_scene = base_scene;
    line_scene.id = "o2-lut-continuum-h2o";
    line_scene.absorbers = .{
        .items = &.{
            zdisamar.Absorber{
                .id = "h2o",
                .species = "h2o",
                .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "h2o").?,
                .profile_source = .atmosphere,
                .volume_mixing_ratio_profile_ppmv = &.{
                    .{ 1000.0, 12000.0 },
                    .{ 600.0, 3500.0 },
                },
                .spectroscopy = .{
                    .mode = .line_by_line,
                    .line_gas_controls = .{
                        .active_stage = .simulation,
                    },
                },
            },
        },
    };

    var line_prepared = try prepareWithSpectroscopy(
        std.testing.allocator,
        &line_scene,
        &profile,
        &cross_sections,
        &line_list,
        &lut,
    );
    defer line_prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), line_prepared.line_absorbers.len);
    try std.testing.expectApproxEqAbs(
        base_prepared.totalOpticalDepthAtWavelength(761.0),
        line_prepared.totalOpticalDepthAtWavelength(761.0),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        base_prepared.gas_optical_depth,
        line_prepared.gas_optical_depth,
        1.0e-12,
    );
    for (base_prepared.layers, line_prepared.layers) |base_layer, line_layer| {
        try std.testing.expectApproxEqAbs(
            base_layer.gas_optical_depth,
            line_layer.gas_optical_depth,
            1.0e-12,
        );
    }
    for (base_prepared.sublayers.?, line_prepared.sublayers.?) |base_sublayer, line_sublayer| {
        try std.testing.expectApproxEqAbs(
            base_sublayer.gas_absorption_optical_depth,
            line_sublayer.gas_absorption_optical_depth,
            1.0e-12,
        );
    }
}

test "preparation rejects line-gas absorbers whose filtered line lists are empty" {
    var profile = ReferenceData.ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.0e19 },
            .{ .altitude_km = 8.0, .pressure_hpa = 600.0, .temperature_k = 255.0, .air_number_density_cm3 = 1.2e19 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 760.8, .sigma_cm2_per_molecule = 4.0e-26 },
            .{ .wavelength_nm = 761.0, .sigma_cm2_per_molecule = 4.5e-26 },
            .{ .wavelength_nm = 761.2, .sigma_cm2_per_molecule = 4.0e-26 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);

    var line_list = ReferenceData.SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{
                .gas_index = 1,
                .isotope_number = 1,
                .center_wavelength_nm = 761.0,
                .line_strength_cm2_per_molecule = 1.0e-24,
                .air_half_width_nm = 0.0010,
                .temperature_exponent = 0.7,
                .lower_state_energy_cm1 = 100.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
        }),
    };
    defer line_list.deinit(std.testing.allocator);

    var lut = try ReferenceData.buildDemoAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const multi_scene: zdisamar.Scene = .{
        .id = "empty-filtered-lines-multi",
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 15.0,
            .relative_azimuth_deg = 20.0,
        },
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 9,
        },
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "h2o",
                    .species = "h2o",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "h2o").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 12000.0 },
                        .{ 600.0, 3500.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                        },
                    },
                },
                zdisamar.Absorber{
                    .id = "nh3",
                    .species = "nh3",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "nh3").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 50.0 },
                        .{ 600.0, 20.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                        },
                    },
                },
            },
        },
    };

    try std.testing.expectError(
        error.InvalidRequest,
        prepareWithSpectroscopy(
            std.testing.allocator,
            &multi_scene,
            &profile,
            &cross_sections,
            &line_list,
            &lut,
        ),
    );

    const single_scene: zdisamar.Scene = .{
        .id = "empty-filtered-lines-single",
        .atmosphere = multi_scene.atmosphere,
        .geometry = multi_scene.geometry,
        .spectral_grid = multi_scene.spectral_grid,
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "nh3",
                    .species = "nh3",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "nh3").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 50.0 },
                        .{ 600.0, 20.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                        },
                    },
                },
            },
        },
    };

    try std.testing.expectError(
        error.InvalidRequest,
        prepareWithSpectroscopy(
            std.testing.allocator,
            &single_scene,
            &profile,
            &cross_sections,
            &line_list,
            &lut,
        ),
    );
}

test "mixed non-o2 line-gas preparation preserves continuum when owner is unknown" {
    var profile = ReferenceData.ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.0e19 },
            .{ .altitude_km = 8.0, .pressure_hpa = 600.0, .temperature_k = 255.0, .air_number_density_cm3 = 1.2e19 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 760.8, .sigma_cm2_per_molecule = 4.0e-26 },
            .{ .wavelength_nm = 761.0, .sigma_cm2_per_molecule = 4.5e-26 },
            .{ .wavelength_nm = 761.2, .sigma_cm2_per_molecule = 4.0e-26 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);

    var line_list = ReferenceData.SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{
                .gas_index = 1,
                .isotope_number = 1,
                .center_wavelength_nm = 761.0,
                .line_strength_cm2_per_molecule = 0.0,
                .air_half_width_nm = 0.0010,
                .temperature_exponent = 0.7,
                .lower_state_energy_cm1 = 100.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
            .{
                .gas_index = 11,
                .isotope_number = 1,
                .center_wavelength_nm = 761.0,
                .line_strength_cm2_per_molecule = 0.0,
                .air_half_width_nm = 0.0010,
                .temperature_exponent = 0.7,
                .lower_state_energy_cm1 = 100.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
        }),
    };
    defer line_list.deinit(std.testing.allocator);

    var lut = try ReferenceData.buildDemoAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const scene: zdisamar.Scene = .{
        .id = "mixed-non-o2-continuum",
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 15.0,
            .relative_azimuth_deg = 20.0,
        },
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 9,
        },
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "h2o",
                    .species = "h2o",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "h2o").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 12000.0 },
                        .{ 600.0, 3500.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                        },
                    },
                },
                zdisamar.Absorber{
                    .id = "nh3",
                    .species = "nh3",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "nh3").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 50.0 },
                        .{ 600.0, 20.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                        },
                    },
                },
            },
        },
    };

    var prepared = try prepareWithSpectroscopy(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        &line_list,
        &lut,
    );
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.gas_optical_depth > 0.0);
    try std.testing.expect(prepared.totalOpticalDepthAtWavelength(761.0) > 0.0);
    for (prepared.sublayers.?) |sublayer| {
        try std.testing.expect(sublayer.gas_absorption_optical_depth > 0.0);
    }
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

    var prepared = try prepareWithSpectroscopy(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        &spectroscopy,
        &lut,
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

test "optical preparation builds sublayer-informed source interfaces for prepared transport inputs" {
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
        .id = "source-interface-grid",
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

    var prepared = try prepareWithSpectroscopy(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        &spectroscopy,
        &lut,
    );
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]internal.kernels.transport.common.LayerInput = undefined;
    _ = PreparationTransport.fillForwardLayersAtWavelength(&prepared, &scene, 434.6, &layer_inputs);

    var source_interfaces: [5]internal.kernels.transport.common.SourceInterfaceInput = undefined;
    PreparationTransport.fillSourceInterfacesAtWavelengthWithLayers(&prepared, 434.6, &layer_inputs, &source_interfaces);

    try std.testing.expectApproxEqRel(
        layer_inputs[0].scattering_optical_depth,
        source_interfaces[0].source_weight,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[0].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[0].ksca_above, 1.0e-12);
    try std.testing.expectApproxEqRel(
        0.5 * layer_inputs[3].scattering_optical_depth,
        source_interfaces[4].source_weight,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[4].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[4].ksca_above, 1.0e-12);
    const coarse_sublayers = prepared.sublayers.?;
    for (1..4) |ilevel| {
        const layer = prepared.layers[ilevel];
        const start_index: usize = @intCast(layer.sublayer_start_index);
        const stop_index = start_index + @as(usize, @intCast(layer.sublayer_count));
        var expected_weight_km: f64 = 0.0;
        for (coarse_sublayers[start_index..stop_index]) |sublayer| {
            expected_weight_km += @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
        }
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[ilevel].source_weight, 1.0e-12);
        try std.testing.expect(source_interfaces[ilevel].rtm_weight > 0.0);
        try std.testing.expect(source_interfaces[ilevel].ksca_above >= 0.0);
        try std.testing.expectApproxEqRel(
            expected_weight_km,
            source_interfaces[ilevel].rtm_weight,
            1.0e-12,
        );
        try std.testing.expectApproxEqRel(
            layer_inputs[ilevel].scattering_optical_depth,
            source_interfaces[ilevel].rtm_weight * source_interfaces[ilevel].ksca_above,
            1.0e-12,
        );
        try std.testing.expectEqual(
            layer_inputs[ilevel].phase_coefficients[0],
            source_interfaces[ilevel].phase_coefficients_above[0],
        );
        try std.testing.expectApproxEqRel(
            layer_inputs[ilevel].phase_coefficients[1],
            source_interfaces[ilevel].phase_coefficients_above[1],
            1.0e-12,
        );
    }

    var fine_layer_inputs: [16]internal.kernels.transport.common.LayerInput = undefined;
    _ = PreparationTransport.fillForwardLayersAtWavelength(&prepared, &scene, 434.6, &fine_layer_inputs);

    var fine_source_interfaces: [17]internal.kernels.transport.common.SourceInterfaceInput = undefined;
    PreparationTransport.fillSourceInterfacesAtWavelengthWithLayers(&prepared, 434.6, &fine_layer_inputs, &fine_source_interfaces);

    try std.testing.expectApproxEqRel(
        fine_layer_inputs[0].scattering_optical_depth,
        fine_source_interfaces[0].source_weight,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), fine_source_interfaces[0].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), fine_source_interfaces[0].ksca_above, 1.0e-12);
    try std.testing.expectApproxEqRel(
        0.5 * fine_layer_inputs[15].scattering_optical_depth,
        fine_source_interfaces[16].source_weight,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), fine_source_interfaces[16].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), fine_source_interfaces[16].ksca_above, 1.0e-12);
    const sublayers = prepared.sublayers.?;
    for (1..16) |ilevel| {
        const sublayer = sublayers[ilevel];
        const expected_weight_km = @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), fine_source_interfaces[ilevel].source_weight, 1.0e-12);
        try std.testing.expect(fine_source_interfaces[ilevel].rtm_weight > 0.0);
        try std.testing.expect(fine_source_interfaces[ilevel].ksca_above >= 0.0);
        try std.testing.expectApproxEqRel(
            expected_weight_km,
            fine_source_interfaces[ilevel].rtm_weight,
            1.0e-12,
        );
        try std.testing.expect(@abs(
            fine_source_interfaces[ilevel].rtm_weight - sublayer.path_length_cm,
        ) > 1.0);
        try std.testing.expectApproxEqRel(
            if (expected_weight_km > 0.0)
                fine_layer_inputs[ilevel].scattering_optical_depth / expected_weight_km
            else
                0.0,
            fine_source_interfaces[ilevel].ksca_above,
            1.0e-12,
        );
        try std.testing.expectApproxEqRel(
            fine_layer_inputs[ilevel].scattering_optical_depth,
            fine_source_interfaces[ilevel].rtm_weight * fine_source_interfaces[ilevel].ksca_above,
            1.0e-12,
        );
        try std.testing.expectEqual(
            fine_layer_inputs[ilevel].phase_coefficients[0],
            fine_source_interfaces[ilevel].phase_coefficients_above[0],
        );
        try std.testing.expectApproxEqRel(
            fine_layer_inputs[ilevel].phase_coefficients[1],
            fine_source_interfaces[ilevel].phase_coefficients_above[1],
            1.0e-12,
        );
    }
}

test "optical preparation recomputes layer phase mixing with wavelength-specific gas scattering" {
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
        .id = "wavelength-phase-mix",
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
            .angstrom_exponent = 0.0,
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

    var prepared = try OpticsPrepare.prepare(
        std.testing.allocator,
        &scene,
        .{
            .profile = &profile,
            .cross_sections = &cross_sections,
            .lut = &lut,
        },
    );
    defer prepared.deinit(std.testing.allocator);

    // The scalar gas phase basis used by the current optics preparation keeps
    // the first non-isotropic coefficient at zero.
    const gas_phase_l1: f64 = 0.0;
    const aerosol_phase_l1 = prepared.sublayers.?[0].aerosol_phase_coefficients[1];
    var layers_405: [4]internal.kernels.transport.common.LayerInput = undefined;
    var layers_465: [4]internal.kernels.transport.common.LayerInput = undefined;
    _ = PreparationTransport.fillForwardLayersAtWavelength(&prepared, &scene, 405.0, &layers_405);
    _ = PreparationTransport.fillForwardLayersAtWavelength(&prepared, &scene, 465.0, &layers_465);

    for (&[_][]const internal.kernels.transport.common.LayerInput{ &layers_405, &layers_465 }) |layer_set| {
        const layer = layer_set[0];
        const total_scattering = layer.gas_scattering_optical_depth + layer.aerosol_scattering_optical_depth;
        const expected_l1 =
            (layer.gas_scattering_optical_depth * gas_phase_l1 +
                layer.aerosol_scattering_optical_depth * aerosol_phase_l1) /
            total_scattering;
        try std.testing.expectApproxEqRel(expected_l1, layer.phase_coefficients[1], 1.0e-12);
    }

    try std.testing.expect(@abs(layers_405[0].phase_coefficients[1] - layers_465[0].phase_coefficients[1]) > 1.0e-4);
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

    var prepared = try OpticsPrepare.prepare(
        std.testing.allocator,
        &scene,
        .{
            .profile = &profile,
            .cross_sections = &cross_sections,
            .lut = &lut,
        },
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

    var prepared = try prepareWithParticleTables(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        null,
        null,
        &lut,
        &mie_table,
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

test "optical preparation derives deterministic layer optical depths from typed assets" {
    const scene: zdisamar.Scene = .{
        .id = "optical-scene",
        .atmosphere = .{
            .layer_count = 4,
            .has_clouds = true,
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

    var profile = ReferenceData.ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1013.25, .temperature_k = 288.15, .air_number_density_cm3 = 2.547e19 },
            .{ .altitude_km = 20.0, .pressure_hpa = 54.75, .temperature_k = 216.65, .air_number_density_cm3 = 1.095e18 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.21e-19 },
            .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 4.17e-19 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);
    const spectroscopy = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
        .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.041, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 140.0, .pressure_shift_nm = 0.003, .line_mixing_coefficient = 0.07 },
    });
    var line_list = ReferenceData.SpectroscopyLineList{ .lines = spectroscopy };
    defer line_list.deinit(std.testing.allocator);

    var lut = ReferenceData.AirmassFactorLut{
        .points = try std.testing.allocator.dupe(ReferenceData.AirmassFactorPoint, &.{
            .{ .solar_zenith_deg = 40.0, .view_zenith_deg = 10.0, .relative_azimuth_deg = 30.0, .airmass_factor = 1.241 },
        }),
    };
    defer lut.deinit(std.testing.allocator);

    var prepared = try prepareWithSpectroscopy(std.testing.allocator, &scene, &profile, &cross_sections, &line_list, &lut);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), prepared.layers.len);
    try std.testing.expect(prepared.total_optical_depth > 0.0);
    try std.testing.expect(prepared.layers[0].optical_depth > prepared.layers[3].optical_depth);
    try std.testing.expect(prepared.column_density_factor > 1.0e24);
    try std.testing.expectEqual(@as(f64, 0.0), prepared.line_mixing_mean_cross_section_cm2_per_molecule);
    try std.testing.expect(prepared.gas_optical_depth > 0.0);
    try std.testing.expect(prepared.d_optical_depth_d_temperature != 0.0);

    const input = PreparationTransport.toForwardInput(&prepared, &scene);
    try std.testing.expect(input.optical_depth > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.241), input.air_mass_factor, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), input.spectral_weight, 1e-9);
    try std.testing.expect(prepared.totalCrossSectionAtWavelength(434.6) > prepared.totalCrossSectionAtWavelength(465.0));

    try std.testing.expect(prepared.sublayers != null);
    try std.testing.expectEqual(prepared.sublayers.?.len, prepared.transportLayerCount());
    var transport_layers: [12]internal.kernels.transport.common.LayerInput = undefined;
    _ = PreparationTransport.fillForwardLayersAtWavelength(&prepared, &scene, 434.6, &transport_layers);
    try std.testing.expect(transport_layers[0].optical_depth > 0.0);
    try std.testing.expect(transport_layers[11].optical_depth > 0.0);
}

fn testPreparedSublayer(
    parent_layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    absorber_number_density_cm3: f64,
) OpticsPrepare.PreparedSublayer {
    return .{
        .parent_layer_index = parent_layer_index,
        .sublayer_index = sublayer_index,
        .global_sublayer_index = global_sublayer_index,
        .altitude_km = altitude_km,
        .pressure_hpa = pressure_hpa,
        .temperature_k = temperature_k,
        .number_density_cm3 = number_density_cm3,
        .oxygen_number_density_cm3 = oxygen_number_density_cm3,
        .absorber_number_density_cm3 = absorber_number_density_cm3,
        .path_length_cm = 1.0,
        .continuum_cross_section_cm2_per_molecule = 0.0,
        .line_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_cross_section_cm2_per_molecule = 0.0,
        .cia_sigma_cm5_per_molecule2 = 0.0,
        .cia_optical_depth = 0.0,
        .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
        .gas_absorption_optical_depth = 0.0,
        .gas_scattering_optical_depth = 0.0,
        .gas_extinction_optical_depth = 0.0,
        .d_gas_optical_depth_d_temperature = 0.0,
        .d_cia_optical_depth_d_temperature = 0.0,
        .aerosol_optical_depth = 0.0,
        .cloud_optical_depth = 0.0,
        .aerosol_single_scatter_albedo = 0.0,
        .cloud_single_scatter_albedo = 0.0,
        .aerosol_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
        .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
        .combined_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
    };
}

test "prepared scalar helpers use global sublayer slots across later layers" {
    const sublayers = [_]OpticsPrepare.PreparedSublayer{
        testPreparedSublayer(0, 0, 0, 0.5, 900.0, 285.0, 2.0e19, 4.0e18, 2.0e15),
        testPreparedSublayer(0, 1, 1, 1.5, 820.0, 280.0, 1.8e19, 3.6e18, 4.0e15),
        testPreparedSublayer(1, 0, 2, 2.5, 700.0, 270.0, 1.4e19, 2.8e18, 6.0e15),
        testPreparedSublayer(1, 1, 3, 3.5, 620.0, 265.0, 1.1e19, 2.2e18, 8.0e15),
    };
    const values = [_]f64{ 2.0, 4.0, 6.0, 8.0 };

    try std.testing.expectApproxEqAbs(
        @as(f64, 6.0),
        OpticsPrepare.PreparedOpticalState.preparedScalarForSublayer(&values, sublayers[2]),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 7.0),
        OpticsPrepare.PreparedOpticalState.interpolatePreparedScalarAtAltitude(&sublayers, &values, 3.0),
        1.0e-12,
    );
}

test "collect active line absorbers resolves public species strings" {
    const scene: zdisamar.Scene = .{
        .id = "string-species-line-absorber",
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 9,
        },
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "o2",
                    .species = "o2",
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                            .threshold_line_sim = 1.0e-23,
                        },
                    },
                },
            },
        },
    };

    const active = try OpticsPrepare.spectroscopy.collectActiveLineAbsorbers(std.testing.allocator, &scene);
    defer std.testing.allocator.free(active);

    try std.testing.expectEqual(@as(usize, 1), active.len);
    try std.testing.expectEqual(AbsorberSpecies.o2, active[0].species);
}

test "resolve active line species maps HITRAN NO2 runtime controls" {
    var line_list = ReferenceData.SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{
                .gas_index = 10,
                .isotope_number = 1,
                .center_wavelength_nm = 435.0,
                .line_strength_cm2_per_molecule = 1.0e-20,
                .air_half_width_nm = 0.001,
                .temperature_exponent = 0.7,
                .lower_state_energy_cm1 = 0.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
        }),
        .runtime_controls = .{ .gas_index = 10 },
    };
    defer line_list.deinit(std.testing.allocator);

    try std.testing.expectEqual(
        AbsorberSpecies.no2,
        OpticsPrepare.spectroscopy.resolveActiveLineSpecies(null, line_list, .{}).?,
    );
}

test "species mixing ratio falls back to demo NO2 trace loading when scene omits absorber profiles" {
    const scene: zdisamar.Scene = .{
        .id = "default-no2-trace-loading",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 9,
        },
    };

    try std.testing.expectApproxEqAbs(
        @as(f64, 5.0e-8),
        OpticsPrepare.spectroscopy.speciesMixingRatioAtPressure(&scene, .no2, &.{}, 700.0, null).?,
        1.0e-18,
    );
}
