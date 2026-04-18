const std = @import("std");
const internal = @import("internal");

const Scene = internal.Scene;
const Blueprint = internal.scene.Blueprint;
const InverseProblem = internal.scene.InverseProblem;
const StateParameter = internal.scene.StateParameter;
const SpectralBand = internal.scene.SpectralBand;
const Absorber = internal.scene.Absorber;
const Instrument = internal.scene.Instrument;

test "scene validation rejects missing instrument and accepts valid scene" {
    var scene: Scene = .{ .id = "scene-ok", .spectral_grid = .{ .sample_count = 16 } };
    try scene.validate();

    scene.observation_model.instrument = .unset;
    try std.testing.expectError(error.MissingObservationInstrument, scene.validate());
}

test "blueprint and inverse problem expose canonical layout and validation contracts" {
    const blueprint_requirements = (Blueprint{
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
        .layer_count_hint = 48,
        .state_parameter_count_hint = 3,
        .measurement_count_hint = 121,
    }).layoutRequirements();

    try std.testing.expectEqual(@as(u32, 48), blueprint_requirements.layer_count);
    try std.testing.expectEqual(@as(u32, 3), blueprint_requirements.state_parameter_count);
    try std.testing.expectEqual(@as(u32, 121), blueprint_requirements.measurement_count);

    try (InverseProblem{
        .id = "retrieval-1",
        .state_vector = .{
            .parameters = &[_]StateParameter{
                .{ .name = "albedo", .target = .surface_albedo },
                .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm },
            },
        },
        .measurements = .{
            .product_name = "slant_column",
            .observable = .slant_column,
            .sample_count = 121,
        },
    }).validate();
}

test "scene derives LUT compatibility keys from geometry and instrument settings" {
    const scene: Scene = .{
        .id = "lut-compatibility",
        .geometry = .{
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 770.0,
            .sample_count = 121,
        },
        .surface = .{
            .kind = .lambertian,
            .albedo = 0.2,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .instrument_line_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
        },
        .lut_controls = .{
            .xsec = .{
                .mode = .generate,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 10,
                .pressure_grid_count = 20,
                .temperature_coefficient_count = 5,
                .pressure_coefficient_count = 10,
            },
        },
    };

    const key = scene.lutCompatibilityKey();
    try key.validate();
    try std.testing.expectEqual(@TypeOf(key.controls.xsec.mode).generate, key.controls.xsec.mode);
    try std.testing.expectEqual(@as(f64, 120.0), key.relative_azimuth_deg);
    try std.testing.expectEqual(@as(f64, 0.38), key.instrument_line_fwhm_nm);
    try std.testing.expectEqual(@as(f64, 1.14), key.lut_sampling_half_span_nm);

    const offsets = [_]f64{ -1.5, 0.0, 1.5 };
    const weights = [_]f64{ 0.25, 0.5, 0.25 };
    var wider_support_scene = scene;
    wider_support_scene.observation_model.instrument_line_shape = .{
        .sample_count = 3,
        .offsets_nm = offsets[0..],
        .weights = weights[0..],
    };

    const wider_support_key = wider_support_scene.lutCompatibilityKey();
    try wider_support_key.validate();
    try std.testing.expectEqual(@as(f64, 1.5), wider_support_key.lut_sampling_half_span_nm);
    try std.testing.expect(!key.matches(wider_support_key));
}

test "scene LUT compatibility key follows effective nominal wavelengths and operational support" {
    const measured_wavelengths = [_]f64{ 758.2, 758.4, 758.6 };
    const operational_support = [_]Instrument.OperationalBandSupport{.{
        .id = "primary",
        .high_resolution_step_nm = 0.01,
        .high_resolution_half_span_nm = 1.14,
    }};

    const scene: Scene = .{
        .id = "lut-compatibility-effective-support",
        .geometry = .{
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 770.0,
            .sample_count = 3,
        },
        .surface = .{
            .kind = .lambertian,
            .albedo = 0.2,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .instrument_line_fwhm_nm = 0.38,
            .measured_wavelengths_nm = measured_wavelengths[0..],
            .operational_band_support = operational_support[0..],
        },
        .lut_controls = .{
            .xsec = .{
                .mode = .generate,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 10,
                .pressure_grid_count = 20,
                .temperature_coefficient_count = 5,
                .pressure_coefficient_count = 10,
            },
        },
    };

    const key = scene.lutCompatibilityKey();
    try key.validate();
    try std.testing.expectEqual(@as(f64, 758.2), key.spectral_start_nm);
    try std.testing.expectEqual(@as(f64, 758.6), key.spectral_end_nm);
    try std.testing.expectEqual(@as(f64, 0.01), key.high_resolution_step_nm);
    try std.testing.expectEqual(@as(f64, 1.14), key.high_resolution_half_span_nm);
    try std.testing.expectEqual(@as(u32, 0), key.nominal_sample_count);
    try std.testing.expectEqual(@as(u64, 0), key.nominal_wavelength_hash);
}

test "scene LUT compatibility key tracks low-resolution measured wavelengths and sample density" {
    const measured_wavelengths = [_]f64{ 758.2, 758.35, 758.6 };
    const shifted_wavelengths = [_]f64{ 758.2, 758.5, 758.6 };

    const measured_scene: Scene = .{
        .id = "lut-compatibility-low-resolution-measured",
        .geometry = .{
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 770.0,
            .sample_count = measured_wavelengths.len,
        },
        .surface = .{
            .kind = .lambertian,
            .albedo = 0.2,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .instrument_line_fwhm_nm = 0.38,
            .measured_wavelengths_nm = measured_wavelengths[0..],
        },
        .lut_controls = .{
            .xsec = .{
                .mode = .generate,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 10,
                .pressure_grid_count = 20,
                .temperature_coefficient_count = 5,
                .pressure_coefficient_count = 10,
            },
        },
    };

    const measured_key = measured_scene.lutCompatibilityKey();
    try measured_key.validate();
    try std.testing.expectEqual(@as(u32, measured_wavelengths.len), measured_key.nominal_sample_count);
    try std.testing.expect(measured_key.nominal_wavelength_hash != 0);

    var shifted_scene = measured_scene;
    shifted_scene.observation_model.measured_wavelengths_nm = shifted_wavelengths[0..];
    const shifted_key = shifted_scene.lutCompatibilityKey();
    try shifted_key.validate();
    try std.testing.expect(!measured_key.matches(shifted_key));

    const uniform_scene: Scene = .{
        .id = "lut-compatibility-low-resolution-uniform",
        .geometry = measured_scene.geometry,
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 770.0,
            .sample_count = 3,
        },
        .surface = measured_scene.surface,
        .observation_model = .{
            .instrument = .tropomi,
            .instrument_line_fwhm_nm = 0.38,
        },
        .lut_controls = measured_scene.lut_controls,
    };

    var denser_uniform_scene = uniform_scene;
    denser_uniform_scene.spectral_grid.sample_count = 5;
    const uniform_key = uniform_scene.lutCompatibilityKey();
    const denser_uniform_key = denser_uniform_scene.lutCompatibilityKey();
    try uniform_key.validate();
    try denser_uniform_key.validate();
    try std.testing.expect(!uniform_key.matches(denser_uniform_key));
}

test "scene accepts canonical bands absorbers and supporting observation metadata" {
    try (Scene{
        .id = "scene-o2a",
        .atmosphere = .{
            .layer_count = 48,
            .profile_source = .{ .asset = .{ .name = "us_standard_profile" } },
            .surface_pressure_hpa = 1013.0,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 31.7,
            .viewing_zenith_deg = 7.9,
            .relative_azimuth_deg = 143.4,
        },
        .spectral_grid = .{ .start_nm = 758.0, .end_nm = 771.0, .sample_count = 121 },
        .bands = .{
            .items = &[_]SpectralBand{
                .{
                    .id = "o2a",
                    .start_nm = 758.0,
                    .end_nm = 771.0,
                    .step_nm = 0.01,
                },
            },
        },
        .absorbers = .{
            .items = &[_]Absorber{
                .{
                    .id = "o2",
                    .species = "o2",
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_list = .{ .asset = .{ .name = "o2_hitran" } },
                    },
                },
            },
        },
        .surface = .{
            .kind = .lambertian,
            .albedo = 0.028,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .solar_spectrum_source = .bundle_default,
            .weighted_reference_grid_source = .{ .ingest = .{
                .full_name = "refspec_demo.operational_refspec_grid",
                .ingest_name = "refspec_demo",
                .output_name = "operational_refspec_grid",
            } },
        },
    }).validate();
}

test "scene allows global legacy operational support across multiple bands" {
    try (Scene{
        .id = "scene-multi-band-operational-legacy",
        .spectral_grid = .{ .start_nm = 760.0, .end_nm = 763.0, .sample_count = 4 },
        .bands = .{
            .items = &[_]SpectralBand{
                .{ .id = "band-a", .start_nm = 760.0, .end_nm = 761.0, .step_nm = 0.5 },
                .{ .id = "band-b", .start_nm = 762.0, .end_nm = 763.0, .step_nm = 0.5 },
            },
        },
        .observation_model = .{
            .instrument = .tropomi,
            .operational_refspec_grid = .{
                .wavelengths_nm = &.{ 760.0, 760.5, 761.0 },
                .weights = &.{ 0.2, 0.6, 0.2 },
            },
        },
    }).validate();
}
