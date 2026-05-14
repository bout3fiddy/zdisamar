use zdisamar::{
    common::errors::Error,
    input::{
        AdaptiveReferenceGrid, CrossSectionFitControls, InstrumentId, InstrumentLineShape,
        InstrumentLineShapeTable, IntegrationMode, NoiseControls, NoiseModelKind, ObservationModel,
        OperationalBandSupport, OperationalSolarSpectrum, SlitIndex, SpectralChannel,
    },
};

#[test]
fn observation_model_validates_noise_and_measured_wavelength_shapes() {
    assert_eq!(ObservationModel::default().validate(), Ok(()));
    assert_eq!(
        ObservationModel {
            noise_model: NoiseModelKind::SnrFromInput,
            ..ObservationModel::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        ObservationModel {
            noise_model: NoiseModelKind::S5pOperational,
            ingested_noise_sigma: vec![1.0],
            reference_radiance: vec![],
            ..ObservationModel::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        ObservationModel {
            measured_wavelengths_nm: vec![761.0, 760.0],
            ..ObservationModel::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn observation_model_resolves_legacy_channel_controls() {
    let model = ObservationModel {
        noise_model: NoiseModelKind::ShotNoise,
        wavelength_shift_nm: 0.02,
        multiplicative_offset: 1.01,
        stray_light: 0.001,
        instrument_line_fwhm_nm: 0.45,
        high_resolution_step_nm: 0.08,
        high_resolution_half_span_nm: 0.32,
        instrument_line_shape: InstrumentLineShape {
            sample_count: 3,
            offsets_nm: vec![-0.1, 0.0, 0.1],
            weights: vec![0.25, 0.5, 0.25],
        },
        reference_radiance: vec![10.0, 11.0],
        ingested_noise_sigma: vec![0.1, 0.2],
        ..ObservationModel::default()
    };

    let radiance = model.resolved_channel_controls(SpectralChannel::Radiance);
    assert_eq!(radiance.noise.model, NoiseModelKind::ShotNoise);
    assert_eq!(radiance.noise.reference_sigma, vec![0.1, 0.2]);
    assert_eq!(
        radiance.response.integration_mode,
        IntegrationMode::ExplicitHrGrid
    );
    assert_eq!(radiance.response.instrument_line_shape.sample_count, 3);

    let irradiance = model.resolved_channel_controls(SpectralChannel::Irradiance);
    assert_eq!(irradiance.noise.model, NoiseModelKind::ShotNoise);
    assert!(irradiance.noise.reference_sigma.is_empty());
}

#[test]
fn observation_model_resolves_legacy_operational_support() {
    let mut solar = OperationalSolarSpectrum {
        wavelengths_nm: vec![760.8, 761.0, 761.2],
        irradiance: vec![2.7e14, 2.8e14, 2.75e14],
        spline_second_derivatives: Vec::new(),
    };
    solar.prepare_interpolation().unwrap();

    let model = ObservationModel {
        instrument: InstrumentId::Tropomi,
        high_resolution_step_nm: 0.08,
        high_resolution_half_span_nm: 0.32,
        operational_solar_spectrum: solar,
        operational_band_support: vec![OperationalBandSupport {
            id: "band-0".to_string(),
            instrument_line_shape: InstrumentLineShape {
                sample_count: 3,
                offsets_nm: vec![-0.1, 0.0, 0.1],
                weights: vec![0.25, 0.5, 0.25],
            },
            ..OperationalBandSupport::default()
        }],
        ..ObservationModel::default()
    };

    let support = model.primary_operational_band_support();
    assert_eq!(support.id, "band-0");
    assert_eq!(support.high_resolution_step_nm, 0.08);
    assert_eq!(support.high_resolution_half_span_nm, 0.32);
    assert_eq!(support.instrument_line_shape.sample_count, 3);
    assert!(support.operational_solar_spectrum.enabled());
    assert!(
        (support
            .operational_solar_spectrum
            .interpolate_irradiance(761.0)
            - 2.8e14)
            .abs()
            < 1.0e9
    );
    assert_eq!(model.lut_sampling_half_span_nm(), 0.32);
    assert_eq!(
        model.operational_replacement_labels(),
        vec!["band-0:hr_grid,isrf,solar".to_string()]
    );
}

#[test]
fn observation_model_rejects_partial_high_resolution_setup_and_multiple_supports() {
    assert_eq!(
        ObservationModel {
            high_resolution_step_nm: 0.01,
            ..ObservationModel::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        ObservationModel {
            operational_band_support: vec![
                OperationalBandSupport {
                    id: "a".to_string(),
                    high_resolution_step_nm: 0.01,
                    high_resolution_half_span_nm: 0.1,
                    ..OperationalBandSupport::default()
                },
                OperationalBandSupport {
                    id: "b".to_string(),
                    high_resolution_step_nm: 0.01,
                    high_resolution_half_span_nm: 0.1,
                    ..OperationalBandSupport::default()
                },
            ],
            ..ObservationModel::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn cross_section_fit_controls_validate_band_specific_settings() {
    let controls = CrossSectionFitControls {
        xsec_strong_absorption_bands: vec![true, false],
        polynomial_degree_bands: vec![2, 3],
        ..CrossSectionFitControls::default()
    };

    assert_eq!(controls.validate_for_band_count(2), Ok(()));
    assert!(controls.strong_absorption_for_band(0));
    assert_eq!(controls.polynomial_order_for_band(1), 3);
    assert_eq!(controls.maximum_polynomial_order(), 3);
    assert_eq!(
        controls.validate_for_band_count(1),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        CrossSectionFitControls {
            polynomial_degree_bands: vec![8],
            ..CrossSectionFitControls::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn observation_model_prefers_explicit_channel_pipeline() {
    let model = ObservationModel {
        measurement_pipeline: zdisamar::input::MeasurementPipeline {
            radiance: zdisamar::input::SpectralChannelControls {
                explicit: true,
                response: zdisamar::input::SpectralResponse {
                    slit_index: SlitIndex::Table,
                    instrument_line_shape_table: InstrumentLineShapeTable {
                        nominal_count: 1,
                        sample_count: 1,
                        nominal_wavelengths_nm: vec![761.0],
                        offsets_nm: vec![0.0],
                        weights: vec![1.0],
                    },
                    ..zdisamar::input::SpectralResponse::default()
                },
                noise: NoiseControls {
                    enabled: true,
                    model: NoiseModelKind::LabOperational,
                    lab_a: 1.0,
                    ..NoiseControls::default()
                },
                ..zdisamar::input::SpectralChannelControls::default()
            },
            ..zdisamar::input::MeasurementPipeline::default()
        },
        ..ObservationModel::default()
    };

    let radiance = model.resolved_channel_controls(SpectralChannel::Radiance);
    assert_eq!(radiance.response.slit_index, SlitIndex::Table);
    assert_eq!(radiance.noise.model, NoiseModelKind::LabOperational);
}

#[test]
fn adaptive_reference_grid_selects_adaptive_response_mode() {
    let model = ObservationModel {
        adaptive_reference_grid: AdaptiveReferenceGrid {
            points_per_fwhm: 4,
            strong_line_min_divisions: 2,
            strong_line_max_divisions: 6,
        },
        high_resolution_step_nm: 0.01,
        high_resolution_half_span_nm: 0.1,
        ..ObservationModel::default()
    };

    assert_eq!(
        model
            .resolved_channel_controls(SpectralChannel::Radiance)
            .response
            .integration_mode,
        IntegrationMode::Adaptive
    );
}
