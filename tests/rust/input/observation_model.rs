use zdisamar::{
    common::errors,
    input::{
        instrument::{
            BuiltinLineShapeKind, InstrumentLineShape, InstrumentLineShapeTable, IntegrationMode,
            NoiseControls, NoiseModelKind, OperationalBandSupport, SlitIndex, SpectralChannel,
            SpectralChannelControls,
        },
        observation_model::{CrossSectionFitControls, ObservationModel},
    },
};

#[test]
fn cross_section_fit_controls_validate_per_band_vectors() {
    let controls = CrossSectionFitControls {
        use_effective_cross_section_oe: true,
        use_polynomial_expansion: true,
        xsec_strong_absorption_bands: vec![true, false],
        polynomial_degree_bands: vec![2, 7],
    };
    assert_eq!(controls.validate_for_band_count(2), Ok(()));
    assert!(controls.strong_absorption_for_band(0));
    assert!(!controls.strong_absorption_for_band(2));
    assert_eq!(controls.polynomial_order_for_band(1), 7);
    assert_eq!(controls.maximum_polynomial_order(), 7);
    assert_eq!(
        CrossSectionFitControls {
            polynomial_degree_bands: vec![8],
            ..CrossSectionFitControls::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn observation_model_validates_noise_and_measured_channel_contracts() {
    assert_eq!(ObservationModel::default().validate(), Ok(()));
    assert_eq!(
        ObservationModel {
            noise_model: NoiseModelKind::SnrFromInput,
            ..ObservationModel::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        ObservationModel {
            noise_model: NoiseModelKind::SnrFromInput,
            measured_wavelengths_nm: vec![760.0, 761.0],
            ingested_noise_sigma: vec![0.1],
            ..ObservationModel::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        ObservationModel {
            noise_model: NoiseModelKind::SnrFromInput,
            measured_wavelengths_nm: vec![760.0, 761.0],
            ingested_noise_sigma: vec![0.1, 0.2],
            ..ObservationModel::default()
        }
        .validate(),
        Ok(())
    );
}

#[test]
fn observation_model_resolves_legacy_channel_controls() {
    let model = ObservationModel {
        noise_model: NoiseModelKind::ShotNoise,
        wavelength_shift_nm: 0.02,
        multiplicative_offset: 1.1,
        stray_light: 0.03,
        instrument_line_fwhm_nm: 0.45,
        builtin_line_shape: BuiltinLineShapeKind::Gaussian,
        high_resolution_step_nm: 0.01,
        high_resolution_half_span_nm: 0.5,
        instrument_line_shape_table: InstrumentLineShapeTable {
            nominal_count: 1,
            sample_count: 2,
            nominal_wavelengths_nm: vec![760.0],
            offsets_nm: vec![-0.2, 0.2],
            weights: vec![1.0, 1.0],
        },
        reference_radiance: vec![100.0],
        ingested_noise_sigma: vec![0.5],
        ..ObservationModel::default()
    };

    let radiance = model.resolved_channel_controls(SpectralChannel::Radiance);
    assert_eq!(radiance.response.slit_index, SlitIndex::Table);
    assert_eq!(
        radiance.response.integration_mode,
        IntegrationMode::ExplicitHrGrid
    );
    assert_eq!(radiance.wavelength_shift_nm, 0.02);
    assert_eq!(radiance.multiplicative_offset, 1.1);
    assert_eq!(radiance.stray_light, 0.03);
    assert_eq!(radiance.noise.model, NoiseModelKind::ShotNoise);
    assert_eq!(radiance.noise.reference_sigma, vec![0.5]);

    let irradiance = model.resolved_channel_controls(SpectralChannel::Irradiance);
    assert_eq!(irradiance.noise.model, NoiseModelKind::ShotNoise);
    assert!(irradiance.noise.enabled);
    assert!(irradiance.noise.reference_sigma.is_empty());
}

#[test]
fn observation_model_prefers_explicit_pipeline_controls() {
    let explicit = SpectralChannelControls {
        explicit: true,
        wavelength_shift_nm: 0.4,
        noise: NoiseControls {
            enabled: true,
            model: NoiseModelKind::LabOperational,
            lab_a: 2.0,
            ..NoiseControls::default()
        },
        ..SpectralChannelControls::default()
    };
    let model = ObservationModel {
        measurement_pipeline: zdisamar::input::instrument::MeasurementPipeline {
            radiance: explicit.clone(),
            ..Default::default()
        },
        ..ObservationModel::default()
    };
    assert_eq!(
        model
            .resolved_channel_controls(SpectralChannel::Radiance)
            .wavelength_shift_nm,
        0.4
    );
}

#[test]
fn operational_band_support_merges_legacy_and_explicit_replacements() {
    let model = ObservationModel {
        high_resolution_step_nm: 0.01,
        high_resolution_half_span_nm: 0.3,
        instrument_line_shape: InstrumentLineShape {
            sample_count: 2,
            offsets_nm: vec![-0.4, 0.4],
            weights: vec![1.0, 1.0],
        },
        operational_band_support: vec![OperationalBandSupport {
            id: "band_4".to_string(),
            high_resolution_step_nm: 0.02,
            high_resolution_half_span_nm: 0.5,
            ..OperationalBandSupport::default()
        }],
        ..ObservationModel::default()
    };

    assert_eq!(model.operational_band_count(), 1);
    let support = model.primary_operational_band_support();
    assert_eq!(support.id, "band_4");
    assert_eq!(support.high_resolution_step_nm, 0.02);
    assert_eq!(model.lut_sampling_half_span_nm(), 0.5);
    assert_eq!(
        model.operational_replacement_labels(),
        vec!["band_4:hr_grid,isrf"]
    );

    assert_eq!(
        ObservationModel {
            operational_band_support: vec![
                OperationalBandSupport {
                    id: "a".to_string(),
                    ..OperationalBandSupport::default()
                },
                OperationalBandSupport {
                    id: "b".to_string(),
                    ..OperationalBandSupport::default()
                },
            ],
            ..ObservationModel::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}
