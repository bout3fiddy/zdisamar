use zdisamar::{
    common::errors::Error,
    input::{
        AdaptiveReferenceGrid, BuiltinLineShapeKind, Instrument, InstrumentId, InstrumentLineShape,
        InstrumentLineShapeTable, IntegrationMode, NoiseControls, NoiseModelKind,
        OperationalBandSupport, OperationalCrossSectionLut, OperationalReferenceGrid,
        OperationalSolarSpectrum, SamplingMode, SlitIndex, SpectralChannelControls,
        SpectralResponse,
    },
};

fn assert_close(actual: f64, expected: f64) {
    assert!(
        (actual - expected).abs() < 1.0e-12,
        "{actual} != {expected}"
    );
}

#[test]
fn instrument_id_and_mode_parsing_match_public_labels() {
    assert_eq!(InstrumentId::parse(""), InstrumentId::Unset);
    assert_eq!(InstrumentId::parse("tropomi").label(), "tropomi");
    assert_eq!(
        InstrumentId::parse("custom_sensor").label(),
        "custom_sensor"
    );
    assert_eq!(
        InstrumentId::Unset.validate(),
        Err(Error::MissingObservationInstrument)
    );
    assert_eq!(
        SamplingMode::parse("operational"),
        Ok(SamplingMode::Operational)
    );
    assert_eq!(
        BuiltinLineShapeKind::parse("vendor_flat_top"),
        Ok(BuiltinLineShapeKind::FlatTopN4)
    );
    assert_eq!(SlitIndex::parse("5"), Ok(SlitIndex::Table));
    assert_eq!(
        SlitIndex::FlatTopN4.builtin_kind(),
        BuiltinLineShapeKind::FlatTopN4
    );
}

#[test]
fn line_shape_validates_and_normalizes_kernel_weights() {
    let line_shape = InstrumentLineShape {
        sample_count: 3,
        offsets_nm: vec![-0.1, 0.0, 0.1],
        weights: vec![1.0, 2.0, 1.0],
    };

    assert_eq!(line_shape.validate(), Ok(()));
    let mut offsets = [0.0; 3];
    let mut weights = [0.0; 3];
    assert_eq!(
        line_shape.write_normalized_kernel(&mut offsets, &mut weights),
        3
    );
    assert_eq!(offsets, [-0.1, 0.0, 0.1]);
    assert_close(weights[1], 0.5);

    assert_eq!(
        InstrumentLineShape {
            sample_count: 1,
            offsets_nm: vec![0.0],
            weights: vec![0.0],
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn line_shape_table_chooses_nearest_nominal_row() {
    let table = InstrumentLineShapeTable {
        nominal_count: 2,
        sample_count: 2,
        nominal_wavelengths_nm: vec![760.0, 761.0],
        offsets_nm: vec![-0.05, 0.05],
        weights: vec![1.0, 3.0, 2.0, 2.0],
    };

    assert_eq!(table.validate(), Ok(()));
    assert_eq!(table.nearest_nominal_index(760.8), Some(1));
    let mut offsets = [0.0; 2];
    let mut weights = [0.0; 2];
    assert_eq!(
        table.write_normalized_kernel_for_nominal(760.8, &mut offsets, &mut weights),
        2
    );
    assert_close(weights[0], 0.5);
    assert_close(weights[1], 0.5);
}

#[test]
fn reference_grid_and_solar_spectrum_validate_and_interpolate() {
    let grid = OperationalReferenceGrid {
        wavelengths_nm: vec![760.0, 761.0, 763.0],
        weights: vec![1.0, 2.0, 1.0],
    };

    assert_eq!(grid.validate(), Ok(()));
    assert_close(grid.effective_spacing_nm(), 1.5);

    let mut solar = OperationalSolarSpectrum {
        wavelengths_nm: vec![760.0, 761.0, 762.0],
        irradiance: vec![10.0, 20.0, 30.0],
        spline_second_derivatives: Vec::new(),
    };
    assert_eq!(solar.validate(), Ok(()));
    assert_close(solar.interpolate_irradiance_linear(760.5), 15.0);
    assert_eq!(solar.prepare_interpolation(), Ok(()));
    assert!(solar.interpolate_irradiance(761.5).is_finite());
    assert!(solar.covers_range(760.1, 761.9));
    assert_eq!(
        solar.correct_measured_spectrum_onto(&[760.0], &[2.0], &[762.0]),
        Ok(vec![6.0])
    );
}

#[test]
fn operational_cross_section_lut_validates_and_evaluates_basis() {
    let lut = OperationalCrossSectionLut {
        wavelengths_nm: vec![760.0, 762.0],
        coefficients: vec![1.0, 2.0],
        temperature_coefficient_count: 1,
        pressure_coefficient_count: 1,
        min_temperature_k: 200.0,
        max_temperature_k: 320.0,
        min_pressure_hpa: 100.0,
        max_pressure_hpa: 1000.0,
    };

    assert_eq!(lut.validate(), Ok(()));
    assert_close(lut.sigma_at(761.0, 250.0, 500.0), 1.5);
    assert_close(lut.d_sigma_d_temperature_at(761.0, 250.0, 500.0), 0.0);

    assert_eq!(
        OperationalCrossSectionLut {
            wavelengths_nm: vec![760.0],
            coefficients: vec![1.0],
            temperature_coefficient_count: 0,
            pressure_coefficient_count: 1,
            min_temperature_k: 200.0,
            max_temperature_k: 320.0,
            min_pressure_hpa: 100.0,
            max_pressure_hpa: 1000.0,
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn instrument_and_operational_support_validate_nested_controls() {
    let support = OperationalBandSupport {
        id: "band-0".to_string(),
        high_resolution_step_nm: 0.08,
        high_resolution_half_span_nm: 0.32,
        instrument_line_shape: InstrumentLineShape {
            sample_count: 3,
            offsets_nm: vec![-0.1, 0.0, 0.1],
            weights: vec![0.25, 0.5, 0.25],
        },
        ..OperationalBandSupport::default()
    };
    assert_eq!(support.validate(), Ok(()));

    let instrument = Instrument {
        id: InstrumentId::Tropomi,
        adaptive_reference_grid: AdaptiveReferenceGrid {
            points_per_fwhm: 5,
            strong_line_min_divisions: 2,
            strong_line_max_divisions: 8,
        },
        ..Instrument::default()
    };
    assert_eq!(instrument.validate(), Ok(()));

    assert_eq!(
        SpectralResponse {
            slit_index: SlitIndex::Table,
            integration_mode: IntegrationMode::ExplicitHrGrid,
            high_resolution_step_nm: 0.01,
            high_resolution_half_span_nm: 0.1,
            ..SpectralResponse::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );

    assert_eq!(
        SpectralChannelControls {
            noise: NoiseControls {
                enabled: true,
                model: NoiseModelKind::LabOperational,
                lab_a: 1.0,
                ..NoiseControls::default()
            },
            ..SpectralChannelControls::default()
        }
        .validate(),
        Ok(())
    );
}
