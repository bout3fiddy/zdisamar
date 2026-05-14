use zdisamar::{
    common::{
        errors,
        lut_controls::{Controls, Mode, ReflectanceControls},
    },
    input::{
        bands::{SpectralBand, SpectralBandSet},
        observation_model::{CrossSectionFitControls, ObservationModel},
        scene::Scene,
        spectrum::SpectralGrid,
    },
};

fn valid_scene() -> Scene {
    Scene {
        spectral_grid: SpectralGrid {
            start_nm: 760.0,
            end_nm: 761.0,
            sample_count: 2,
        },
        ..Scene::default()
    }
}

#[test]
fn scene_validates_top_level_contracts() {
    assert_eq!(valid_scene().validate(), Ok(()));
    assert_eq!(
        Scene {
            id: String::new(),
            ..valid_scene()
        }
        .validate(),
        Err(errors::Error::MissingScene)
    );
    assert_eq!(
        Scene {
            observation_model: ObservationModel {
                measured_wavelengths_nm: vec![760.0],
                ..ObservationModel::default()
            },
            ..valid_scene()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn scene_validates_cross_section_fit_against_band_count() {
    let scene = Scene {
        bands: SpectralBandSet {
            items: vec![
                SpectralBand {
                    id: "b1".to_string(),
                    start_nm: 760.0,
                    end_nm: 761.0,
                    step_nm: 0.1,
                    exclude: Vec::new(),
                },
                SpectralBand {
                    id: "b2".to_string(),
                    start_nm: 761.0,
                    end_nm: 762.0,
                    step_nm: 0.1,
                    exclude: Vec::new(),
                },
            ],
        },
        observation_model: ObservationModel {
            cross_section_fit: CrossSectionFitControls {
                polynomial_degree_bands: vec![2],
                ..CrossSectionFitControls::default()
            },
            ..ObservationModel::default()
        },
        ..valid_scene()
    };
    assert_eq!(scene.validate(), Err(errors::Error::InvalidRequest));
}

#[test]
fn scene_lut_compatibility_key_uses_measured_channels_when_present() {
    let scene = Scene {
        observation_model: ObservationModel {
            measured_wavelengths_nm: vec![760.0, 760.5],
            instrument_line_fwhm_nm: 0.45,
            ..ObservationModel::default()
        },
        lut_controls: Controls {
            reflectance: ReflectanceControls {
                reflectance_mode: Mode::Consume,
                surface_albedo: 0.2,
                ..ReflectanceControls::default()
            },
            ..Controls::default()
        },
        ..valid_scene()
    };
    let key = scene.lut_compatibility_key();
    assert_eq!(key.spectral_start_nm, 760.0);
    assert_eq!(key.spectral_end_nm, 760.5);
    assert_eq!(key.nominal_sample_count, 2);
    assert_ne!(key.nominal_wavelength_hash, 0);
    assert_eq!(key.instrument_line_fwhm_nm, 0.45);
    assert_eq!(key.validate(), Ok(()));
}
