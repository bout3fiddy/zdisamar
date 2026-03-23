const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

const bundled_optics = internal.runtime.reference.bundled_optics;
const bundled_optics_assets = internal.runtime.reference.bundled_optics_assets;
const ReferenceData = internal.reference_data;
const Absorber = zdisamar.Absorber;

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
