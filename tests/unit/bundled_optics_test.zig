const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

const bundled_optics = internal.runtime.reference.bundled_optics;
const bundled_optics_assets = internal.runtime.reference.bundled_optics_assets;
const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.preparation;
const Absorber = zdisamar.Absorber;
const AbsorberSpecies = @typeInfo(@TypeOf(@as(zdisamar.Absorber, .{}).resolved_species)).optional.child;

test "runtime bundled optics uses NO2 assets in the visible band" {
    const scene: zdisamar.Scene = .{
        .id = "runtime-no2",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 48,
        },
        .observation_model = .{
            .instrument = .{ .custom = "unit-test" },
            .sampling = .native,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 24,
        },
    };

    var prepared = try bundled_optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.spectroscopy_lines != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.strong_lines == null);
    try std.testing.expect(prepared.mean_cross_section_cm2_per_molecule > 0.0);
}

test "runtime bundled optics skips visible line and cia defaults for explicit cross-section scenes" {
    var no2_points = [_]ReferenceData.CrossSectionPoint{
        .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 4.8e-19 },
        .{ .wavelength_nm = 420.0, .sigma_cm2_per_molecule = 3.4e-19 },
        .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 2.2e-19 },
        .{ .wavelength_nm = 450.0, .sigma_cm2_per_molecule = 1.7e-19 },
        .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 1.1e-19 },
    };

    const scene: zdisamar.Scene = .{
        .id = "runtime-visible-cross-sections",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 48,
        },
        .bands = .{
            .items = &.{
                .{
                    .id = "vis-no2",
                    .start_nm = 405.0,
                    .end_nm = 465.0,
                    .step_nm = 1.25,
                },
            },
        },
        .absorbers = .{
            .items = &[_]Absorber{
                .{
                    .id = "no2",
                    .species = "no2",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "no2").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 0.09 },
                        .{ 450.0, 0.03 },
                    },
                    .spectroscopy = .{
                        .mode = .cross_sections,
                        .resolved_cross_section_table = .{
                            .points = no2_points[0..],
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .{ .custom = "unit-test" },
            .sampling = .native,
            .noise_model = .shot_noise,
            .cross_section_fit = .{
                .use_effective_cross_section_oe = true,
                .use_polynomial_expansion = true,
                .xsec_strong_absorption_bands = &.{true},
                .polynomial_degree_bands = &.{4},
            },
        },
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = 2,
        },
    };

    var prepared = try bundled_optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.spectroscopy_lines == null);
    try std.testing.expectEqual(@as(usize, 1), prepared.cross_section_absorbers.len);
    try std.testing.expectEqual(@as(usize, 0), prepared.line_absorbers.len);
    try std.testing.expect(prepared.collision_induced_absorption == null);
    try std.testing.expectEqual(
        OpticsPrepare.state.CrossSectionRepresentationKind.effective_table,
        prepared.cross_section_absorbers[0].representation_kind,
    );
    try std.testing.expect(prepared.gas_optical_depth > 0.0);
}

test "runtime bundled optics replaces explicit cross-section tables when generating LUTs" {
    var no2_points = [_]ReferenceData.CrossSectionPoint{
        .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 4.8e-19 },
        .{ .wavelength_nm = 420.0, .sigma_cm2_per_molecule = 3.4e-19 },
        .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 2.2e-19 },
        .{ .wavelength_nm = 450.0, .sigma_cm2_per_molecule = 1.7e-19 },
        .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 1.1e-19 },
    };

    const scene: zdisamar.Scene = .{
        .id = "runtime-visible-cross-sections-generate-lut",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 48,
        },
        .bands = .{
            .items = &.{
                .{
                    .id = "vis-no2",
                    .start_nm = 405.0,
                    .end_nm = 465.0,
                    .step_nm = 1.25,
                },
            },
        },
        .absorbers = .{
            .items = &[_]Absorber{
                .{
                    .id = "no2",
                    .species = "no2",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "no2").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 0.09 },
                        .{ 450.0, 0.03 },
                    },
                    .spectroscopy = .{
                        .mode = .cross_sections,
                        .resolved_cross_section_table = .{
                            .points = no2_points[0..],
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .{ .custom = "unit-test" },
            .sampling = .native,
            .noise_model = .shot_noise,
            .cross_section_fit = .{
                .use_effective_cross_section_oe = true,
                .use_polynomial_expansion = true,
                .xsec_strong_absorption_bands = &.{true},
                .polynomial_degree_bands = &.{4},
            },
        },
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = 2,
        },
        .lut_controls = .{
            .xsec = .{
                .mode = .generate,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 6,
                .pressure_grid_count = 8,
                .temperature_coefficient_count = 3,
                .pressure_coefficient_count = 4,
            },
        },
    };

    var prepared = try bundled_optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), prepared.cross_section_absorbers.len);
    try std.testing.expectEqual(
        OpticsPrepare.state.CrossSectionRepresentationKind.effective_lut,
        prepared.cross_section_absorbers[0].representation_kind,
    );
    try std.testing.expectEqual(@as(usize, 1), prepared.generated_lut_assets.len);
    try std.testing.expectEqualStrings("no2:xsec_lut:generated", prepared.generated_lut_assets[0].provenance_label);
}

test "runtime bundled optics generates low-resolution LUTs on measured wavelengths" {
    var no2_points = [_]ReferenceData.CrossSectionPoint{
        .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 4.8e-19 },
        .{ .wavelength_nm = 420.0, .sigma_cm2_per_molecule = 3.4e-19 },
        .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 2.2e-19 },
        .{ .wavelength_nm = 450.0, .sigma_cm2_per_molecule = 1.7e-19 },
        .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 1.1e-19 },
    };
    const measured_wavelengths = [_]f64{ 405.0, 408.5, 417.25, 465.0 };

    const scene: zdisamar.Scene = .{
        .id = "runtime-visible-cross-sections-generate-lut-measured",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = measured_wavelengths.len,
        },
        .bands = .{
            .items = &.{
                .{
                    .id = "vis-no2",
                    .start_nm = 405.0,
                    .end_nm = 465.0,
                    .step_nm = 1.25,
                },
            },
        },
        .absorbers = .{
            .items = &[_]Absorber{
                .{
                    .id = "no2",
                    .species = "no2",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "no2").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 0.09 },
                        .{ 450.0, 0.03 },
                    },
                    .spectroscopy = .{
                        .mode = .cross_sections,
                        .resolved_cross_section_table = .{
                            .points = no2_points[0..],
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .{ .custom = "unit-test" },
            .sampling = .native,
            .noise_model = .shot_noise,
            .measured_wavelengths_nm = measured_wavelengths[0..],
            .cross_section_fit = .{
                .use_effective_cross_section_oe = true,
                .use_polynomial_expansion = true,
                .xsec_strong_absorption_bands = &.{true},
                .polynomial_degree_bands = &.{4},
            },
        },
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = 2,
        },
        .lut_controls = .{
            .xsec = .{
                .mode = .generate,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 6,
                .pressure_grid_count = 8,
                .temperature_coefficient_count = 3,
                .pressure_coefficient_count = 4,
            },
        },
    };

    var prepared = try bundled_optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    const lut = switch (prepared.cross_section_absorbers[0].representation) {
        .lut => |lut| lut,
        .table => unreachable,
    };
    try std.testing.expectEqualSlices(f64, measured_wavelengths[0..], lut.wavelengths_nm);
}

test "runtime bundled optics rejects reflectance LUT consume modes without a source" {
    const scene: zdisamar.Scene = .{
        .id = "runtime-reflectance-lut-consume",
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 771.5,
            .sample_count = 48,
        },
        .observation_model = .{
            .instrument = .{ .custom = "unit-test" },
            .sampling = .native,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 24,
        },
        .lut_controls = .{
            .reflectance = .{
                .correction_mode = .consume,
            },
        },
    };

    try std.testing.expectError(error.InvalidRequest, bundled_optics.prepareForScene(std.testing.allocator, &scene));
}

test "runtime bundled optics keeps visible bundled line fallback for implicit absorbers" {
    const scene: zdisamar.Scene = .{
        .id = "runtime-visible-implicit-absorbers",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 48,
        },
        .absorbers = .{
            .items = &[_]Absorber{
                .{
                    .id = "no2",
                    .species = "no2",
                    .profile_source = .atmosphere,
                },
            },
        },
        .observation_model = .{
            .instrument = .{ .custom = "unit-test" },
            .sampling = .native,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 24,
        },
    };

    var prepared = try bundled_optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.spectroscopy_lines != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.lines.len != 0);
}

test "bundled optics and preparation helpers accept O2_O2 species aliases" {
    const absorber: Absorber = .{
        .id = "o2-o2-alias",
        .species = "O2_O2",
        .profile_source = .atmosphere,
        .spectroscopy = .{ .mode = .cross_sections },
    };

    try std.testing.expectEqual(
        AbsorberSpecies.o2_o2,
        bundled_optics_assets.resolvedAbsorberSpecies(absorber).?,
    );
    try std.testing.expectEqual(
        AbsorberSpecies.o2_o2,
        OpticsPrepare.spectroscopy.resolvedAbsorberSpecies(absorber).?,
    );
}

test "runtime bundled optics uses O2A sidecars and aerosol Mie tables when requested" {
    const scene: zdisamar.Scene = .{
        .id = "runtime-o2a",
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 771.5,
            .sample_count = 96,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .measured_channels,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = 4,
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
    };

    var prepared = try bundled_optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.spectroscopy_lines != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.strong_lines != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.relaxation_matrix != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.lines.len >= 1300);
    try std.testing.expect(prepared.spectroscopy_lines.?.strong_lines.?.len >= 70);
    try std.testing.expect(prepared.spectroscopy_lines.?.relaxation_matrix.?.line_count >= 70);
    try std.testing.expect(prepared.collision_induced_absorption != null);
    try std.testing.expect(prepared.collision_induced_absorption.?.points.len >= 18000);
    try std.testing.expect(prepared.cia_optical_depth > 0.0);
    try std.testing.expect(prepared.sublayers != null);
    try std.testing.expect(prepared.sublayers.?[0].aerosol_phase_coefficients[1] > scene.aerosol.asymmetry_factor);
}

test "runtime bundled optics keeps bundled O2A CIA for explicit o2-only scenes" {
    const scene: zdisamar.Scene = .{
        .id = "runtime-o2a-o2-only",
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 771.5,
            .sample_count = 64,
        },
        .absorbers = .{
            .items = &[_]Absorber{
                .{
                    .id = "o2",
                    .species = "o2",
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .line_by_line,
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 16,
            .sublayer_divisions = 2,
        },
    };

    var prepared = try bundled_optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.spectroscopy_lines != null);
    try std.testing.expect(prepared.collision_induced_absorption != null);
    try std.testing.expect(prepared.cia_optical_depth > 0.0);
}

test "runtime bundled optics loads bundled O2A CIA when explicit o2o2 absorber is present" {
    const scene: zdisamar.Scene = .{
        .id = "runtime-o2a-with-explicit-cia-absorber",
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 771.5,
            .sample_count = 64,
        },
        .absorbers = .{
            .items = &[_]Absorber{
                .{
                    .id = "o2",
                    .species = "o2",
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .line_by_line,
                    },
                },
                .{
                    .id = "o2o2",
                    .species = "o2o2",
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .cia,
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 16,
            .sublayer_divisions = 2,
        },
    };

    var prepared = try bundled_optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.spectroscopy_lines != null);
    try std.testing.expect(prepared.collision_induced_absorption != null);
    try std.testing.expect(prepared.cia_optical_depth > 0.0);
}

test "runtime bundled optics honors resolved scene spectroscopy assets before range defaults" {
    const lines = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
        .{
            .center_wavelength_nm = 760.7,
            .line_strength_cm2_per_molecule = 1.0e-24,
            .air_half_width_nm = 0.01,
            .temperature_exponent = 0.7,
            .lower_state_energy_cm1 = 10.0,
            .pressure_shift_nm = 0.0,
            .line_mixing_coefficient = 0.0,
        },
    });
    defer std.testing.allocator.free(lines);

    const cia_points = try std.testing.allocator.dupe(ReferenceData.CollisionInducedAbsorptionPoint, &.{
        .{
            .wavelength_nm = 760.7,
            .a0 = 1.0e-46,
            .a1 = 0.0,
            .a2 = 0.0,
        },
    });
    defer std.testing.allocator.free(cia_points);

    const scene: zdisamar.Scene = .{
        .id = "runtime-explicit-assets",
        .spectral_grid = .{
            .start_nm = 760.6,
            .end_nm = 760.8,
            .sample_count = 8,
        },
        .absorbers = .{
            .items = &[_]Absorber{
                .{
                    .id = "o2",
                    .species = "o2",
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_list = .{ .asset = .{ .name = "explicit_line_list" } },
                        .resolved_line_list = .{ .lines = lines },
                    },
                },
                .{
                    .id = "o2o2",
                    .species = "o2o2",
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .cia,
                        .cia_table = .{ .asset = .{ .name = "explicit_cia" } },
                        .resolved_cia_table = .{
                            .scale_factor_cm5_per_molecule2 = 1.0,
                            .points = cia_points,
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .{ .custom = "unit-test" },
            .sampling = .native,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 4,
        },
    };

    var prepared = try bundled_optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), prepared.spectroscopy_lines.?.lines.len);
    try std.testing.expectEqual(@as(usize, 1), prepared.collision_induced_absorption.?.points.len);
}

test "bundled optics helper keeps shared bundle ids centralized" {
    try std.testing.expectEqualStrings(
        "us_standard_1976_profile",
        bundled_optics_assets.asset_ids.standard_climatology_profile,
    );
    try std.testing.expectEqualStrings(
        "data/cross_sections/bundle_manifest.json",
        bundled_optics_assets.bundle_manifest_paths.cross_sections,
    );
}
