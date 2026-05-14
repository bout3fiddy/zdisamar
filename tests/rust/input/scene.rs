use zdisamar::{
    common::{
        errors::Error,
        lut_controls::{Controls, Mode, XsecControls},
    },
    input::{
        Absorber, AbsorberSet, Binding, Geometry, InstrumentId, InstrumentLineShape, Model,
        NamedRef, ObservationModel, OperationalBandSupport, Scene, SpectralBand, SpectralBandSet,
        SpectralGrid, Spectroscopy, SpectroscopyMode, Surface,
    },
};

fn lut_controls() -> Controls {
    Controls {
        xsec: XsecControls {
            mode: Mode::Generate,
            min_temperature_k: 180.0,
            max_temperature_k: 325.0,
            min_pressure_hpa: 0.03,
            max_pressure_hpa: 1050.0,
            temperature_grid_count: 10,
            pressure_grid_count: 20,
            temperature_coefficient_count: 5,
            pressure_coefficient_count: 10,
        },
        ..Controls::default()
    }
}

#[test]
fn scene_validation_rejects_missing_instrument_and_accepts_valid_scene() {
    let scene = Scene {
        id: "scene-ok".to_string(),
        spectral_grid: SpectralGrid {
            sample_count: 16,
            ..SpectralGrid::default()
        },
        ..Scene::default()
    };
    assert_eq!(scene.validate(), Ok(()));

    let missing_instrument = Scene {
        observation_model: ObservationModel {
            instrument: InstrumentId::Unset,
            ..ObservationModel::default()
        },
        ..scene
    };
    assert_eq!(
        missing_instrument.validate(),
        Err(Error::MissingObservationInstrument)
    );
}

#[test]
fn scene_derives_lut_compatibility_key_from_geometry_and_instrument_settings() {
    let scene = Scene {
        id: "lut-compatibility".to_string(),
        geometry: Geometry {
            solar_zenith_deg: 60.0,
            viewing_zenith_deg: 30.0,
            relative_azimuth_deg: 120.0,
            ..Geometry::default()
        },
        spectral_grid: SpectralGrid {
            start_nm: 758.0,
            end_nm: 770.0,
            sample_count: 121,
        },
        surface: Surface {
            albedo: 0.2,
            ..Surface::default()
        },
        observation_model: ObservationModel {
            instrument: InstrumentId::Tropomi,
            instrument_line_fwhm_nm: 0.38,
            high_resolution_step_nm: 0.01,
            high_resolution_half_span_nm: 1.14,
            ..ObservationModel::default()
        },
        lut_controls: lut_controls(),
        ..Scene::default()
    };

    let key = scene.lut_compatibility_key();
    assert_eq!(key.validate(), Ok(()));
    assert_eq!(key.controls.xsec.mode, Mode::Generate);
    assert_eq!(key.relative_azimuth_deg, 120.0);
    assert_eq!(key.instrument_line_fwhm_nm, 0.38);
    assert_eq!(key.lut_sampling_half_span_nm, 1.14);

    let wider_support_scene = Scene {
        observation_model: ObservationModel {
            instrument_line_shape: InstrumentLineShape {
                sample_count: 3,
                offsets_nm: vec![-1.5, 0.0, 1.5],
                weights: vec![0.25, 0.5, 0.25],
            },
            ..scene.observation_model.clone()
        },
        ..scene
    };
    let wider_support_key = wider_support_scene.lut_compatibility_key();
    assert_eq!(wider_support_key.validate(), Ok(()));
    assert_eq!(wider_support_key.lut_sampling_half_span_nm, 1.5);
    assert!(!key.matches(wider_support_key));
}

#[test]
fn scene_lut_key_follows_measured_wavelengths_and_operational_support() {
    let scene = Scene {
        id: "lut-compatibility-effective-support".to_string(),
        geometry: Geometry {
            solar_zenith_deg: 60.0,
            viewing_zenith_deg: 30.0,
            relative_azimuth_deg: 120.0,
            ..Geometry::default()
        },
        spectral_grid: SpectralGrid {
            start_nm: 758.0,
            end_nm: 770.0,
            sample_count: 3,
        },
        surface: Surface {
            albedo: 0.2,
            ..Surface::default()
        },
        observation_model: ObservationModel {
            instrument: InstrumentId::Tropomi,
            instrument_line_fwhm_nm: 0.38,
            measured_wavelengths_nm: vec![758.2, 758.4, 758.6],
            operational_band_support: vec![OperationalBandSupport {
                id: "primary".to_string(),
                high_resolution_step_nm: 0.01,
                high_resolution_half_span_nm: 1.14,
                ..OperationalBandSupport::default()
            }],
            ..ObservationModel::default()
        },
        lut_controls: lut_controls(),
        ..Scene::default()
    };

    let key = scene.lut_compatibility_key();
    assert_eq!(key.validate(), Ok(()));
    assert_eq!(key.spectral_start_nm, 758.2);
    assert_eq!(key.spectral_end_nm, 758.6);
    assert_eq!(key.high_resolution_step_nm, 0.01);
    assert_eq!(key.high_resolution_half_span_nm, 1.14);
    assert_eq!(key.nominal_sample_count, 0);
    assert_eq!(key.nominal_wavelength_hash, 0);
}

#[test]
fn scene_lut_key_tracks_low_resolution_measured_wavelengths_and_sample_density() {
    let measured_scene = Scene {
        id: "lut-compatibility-low-resolution-measured".to_string(),
        geometry: Geometry {
            solar_zenith_deg: 60.0,
            viewing_zenith_deg: 30.0,
            relative_azimuth_deg: 120.0,
            ..Geometry::default()
        },
        spectral_grid: SpectralGrid {
            start_nm: 758.0,
            end_nm: 770.0,
            sample_count: 3,
        },
        surface: Surface {
            albedo: 0.2,
            ..Surface::default()
        },
        observation_model: ObservationModel {
            instrument: InstrumentId::Tropomi,
            instrument_line_fwhm_nm: 0.38,
            measured_wavelengths_nm: vec![758.2, 758.35, 758.6],
            ..ObservationModel::default()
        },
        lut_controls: lut_controls(),
        ..Scene::default()
    };

    let measured_key = measured_scene.lut_compatibility_key();
    assert_eq!(measured_key.validate(), Ok(()));
    assert_eq!(measured_key.nominal_sample_count, 3);
    assert_ne!(measured_key.nominal_wavelength_hash, 0);

    let shifted_scene = Scene {
        observation_model: ObservationModel {
            measured_wavelengths_nm: vec![758.2, 758.5, 758.6],
            ..measured_scene.observation_model.clone()
        },
        ..measured_scene.clone()
    };
    let shifted_key = shifted_scene.lut_compatibility_key();
    assert_eq!(shifted_key.validate(), Ok(()));
    assert!(!measured_key.matches(shifted_key));

    let uniform_scene = Scene {
        observation_model: ObservationModel {
            measured_wavelengths_nm: Vec::new(),
            ..measured_scene.observation_model
        },
        ..measured_scene
    };
    let denser_uniform_scene = Scene {
        spectral_grid: SpectralGrid {
            sample_count: 5,
            ..uniform_scene.spectral_grid
        },
        ..uniform_scene.clone()
    };
    assert!(
        !uniform_scene
            .lut_compatibility_key()
            .matches(denser_uniform_scene.lut_compatibility_key())
    );
}

#[test]
fn scene_accepts_canonical_bands_absorbers_and_supporting_metadata() {
    let scene = Scene {
        id: "scene-o2a".to_string(),
        atmosphere: zdisamar::input::Atmosphere {
            layer_count: 48,
            profile_source: Binding::Asset(NamedRef {
                name: "us_standard_profile".to_string(),
            }),
            surface_pressure_hpa: 1013.0,
            ..zdisamar::input::Atmosphere::default()
        },
        geometry: Geometry {
            model: Model::PseudoSpherical,
            solar_zenith_deg: 31.7,
            viewing_zenith_deg: 7.9,
            relative_azimuth_deg: 143.4,
            ..Geometry::default()
        },
        spectral_grid: SpectralGrid {
            start_nm: 758.0,
            end_nm: 771.0,
            sample_count: 121,
        },
        bands: SpectralBandSet {
            items: vec![SpectralBand {
                id: "o2a".to_string(),
                start_nm: 758.0,
                end_nm: 771.0,
                step_nm: 0.01,
                exclude: Vec::new(),
            }],
        },
        absorbers: AbsorberSet {
            items: vec![Absorber {
                id: "o2".to_string(),
                species: "o2".to_string(),
                profile_source: Binding::Atmosphere,
                spectroscopy: Spectroscopy {
                    mode: SpectroscopyMode::LineByLine,
                    line_list: Binding::Asset(NamedRef {
                        name: "o2_hitran".to_string(),
                    }),
                    ..Spectroscopy::default()
                },
                ..Absorber::default()
            }],
        },
        surface: Surface {
            albedo: 0.028,
            ..Surface::default()
        },
        observation_model: ObservationModel {
            instrument: InstrumentId::Tropomi,
            solar_spectrum_source: Binding::BundleDefault,
            weighted_reference_grid_source: Binding::Ingest(
                zdisamar::input::IngestRef::from_full_name("refspec_demo.operational_refspec_grid"),
            ),
            ..ObservationModel::default()
        },
        ..Scene::default()
    };

    assert_eq!(scene.validate(), Ok(()));
}

#[test]
fn scene_rejects_mismatched_measured_wavelength_count_and_bad_phase_threshold() {
    assert_eq!(
        Scene {
            spectral_grid: SpectralGrid {
                sample_count: 2,
                ..SpectralGrid::default()
            },
            observation_model: ObservationModel {
                measured_wavelengths_nm: vec![760.0],
                ..ObservationModel::default()
            },
            ..Scene::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        Scene {
            spectral_grid: SpectralGrid {
                sample_count: 2,
                ..SpectralGrid::default()
            },
            phase_function_truncation_threshold: 0.0,
            ..Scene::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}
