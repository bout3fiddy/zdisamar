use zdisamar::{
    common::errors,
    input::instrument::{
        AdaptiveReferenceGrid, BuiltinLineShapeKind, Id, Instrument, InstrumentLineShape,
        InstrumentLineShapeTable, NodalCorrection, NoiseControls, NoiseModelKind,
        OperationalBandSupport, OperationalCrossSectionLut, OperationalReferenceGrid,
        OperationalSolarSpectrum, RingControls, SamplingMode, SlitIndex, SpectralResponse,
    },
};

#[test]
fn instrument_id_parses_labels_and_validates_required_selection() {
    assert_eq!(Id::parse(""), Id::Unset);
    assert_eq!(Id::parse("generic"), Id::Generic);
    assert_eq!(Id::parse("tropomi").label(), "tropomi");
    assert_eq!(Id::parse("custom_lab").label(), "custom_lab");
    assert_eq!(
        Id::Unset.validate(),
        Err(errors::Error::MissingObservationInstrument)
    );
    assert_eq!(Id::Synthetic.validate(), Ok(()));
}

#[test]
fn builtin_line_shape_parses_vendor_aliases() {
    assert_eq!(
        BuiltinLineShapeKind::parse(""),
        Ok(BuiltinLineShapeKind::Gaussian)
    );
    assert_eq!(
        BuiltinLineShapeKind::parse("vendor_flat_top"),
        Ok(BuiltinLineShapeKind::FlatTopN4)
    );
    assert_eq!(
        BuiltinLineShapeKind::parse("triple_flat_top"),
        Ok(BuiltinLineShapeKind::TripleFlatTopN4)
    );
    assert_eq!(
        BuiltinLineShapeKind::parse("mystery"),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn instrument_pipeline_enums_parse_vendor_control_values() {
    assert_eq!(SamplingMode::parse("native"), Ok(SamplingMode::Native));
    assert_eq!(SamplingMode::Operational.label(), "operational");
    assert_eq!(SlitIndex::parse("flat_top"), Ok(SlitIndex::FlatTopN4));
    assert_eq!(SlitIndex::parse("5"), Ok(SlitIndex::Table));
    assert_eq!(
        SlitIndex::TripleFlatTopN4.builtin_kind(),
        BuiltinLineShapeKind::TripleFlatTopN4
    );
}

#[test]
fn line_shape_validates_and_writes_normalized_kernel() {
    let shape = InstrumentLineShape {
        sample_count: 3,
        offsets_nm: vec![-0.1, 0.0, 0.1],
        weights: vec![1.0, 2.0, 1.0],
    };
    assert_eq!(shape.validate(), Ok(()));

    let mut offsets = [0.0; 3];
    let mut weights = [0.0; 3];
    assert_eq!(shape.write_normalized_kernel(&mut offsets, &mut weights), 3);
    assert_eq!(offsets, [-0.1, 0.0, 0.1]);
    assert_eq!(weights, [0.25, 0.5, 0.25]);

    assert_eq!(
        InstrumentLineShape {
            sample_count: 1,
            offsets_nm: vec![0.0],
            weights: vec![-1.0],
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn line_shape_table_selects_nearest_nominal_and_normalizes_rows() {
    let mut table = InstrumentLineShapeTable {
        nominal_count: 2,
        sample_count: 3,
        nominal_wavelengths_nm: vec![760.0, 761.0],
        offsets_nm: vec![-0.1, 0.0, 0.1],
        weights: vec![1.0, 2.0, 1.0, 2.0, 2.0, 4.0],
    };
    assert_eq!(table.validate(), Ok(()));
    assert_eq!(table.nearest_nominal_index(760.8), Some(1));
    assert_eq!(table.weight_at(1, 2), 4.0);
    table.set_weight(1, 2, 2.0);
    assert_eq!(table.weight_at(1, 2), 2.0);

    let mut offsets = [0.0; 3];
    let mut weights = [0.0; 3];
    assert_eq!(
        table.write_normalized_kernel_for_nominal(760.8, &mut offsets, &mut weights),
        3
    );
    assert_eq!(offsets, [-0.1, 0.0, 0.1]);
    assert_eq!(weights, [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0]);
}

#[test]
fn operational_reference_grid_validates_monotonic_weighted_grid() {
    let grid = OperationalReferenceGrid {
        wavelengths_nm: vec![760.0, 760.2, 760.5],
        weights: vec![1.0, 3.0, 2.0],
    };
    assert_eq!(grid.validate(), Ok(()));
    assert!((grid.effective_spacing_nm() - (1.15 / 4.5)).abs() < 1.0e-14);

    assert_eq!(
        OperationalReferenceGrid {
            wavelengths_nm: Vec::new(),
            weights: vec![1.0],
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn adaptive_reference_grid_requires_complete_division_controls() {
    assert_eq!(AdaptiveReferenceGrid::default().validate(), Ok(()));
    assert_eq!(
        AdaptiveReferenceGrid {
            points_per_fwhm: 4,
            strong_line_min_divisions: 2,
            strong_line_max_divisions: 8,
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        AdaptiveReferenceGrid {
            points_per_fwhm: 4,
            strong_line_min_divisions: 9,
            strong_line_max_divisions: 8,
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn solar_spectrum_validates_and_interpolates_linearly_when_unprepared() {
    let solar = OperationalSolarSpectrum {
        wavelengths_nm: vec![760.0, 761.0, 763.0],
        irradiance: vec![10.0, 20.0, 60.0],
        spline_second_derivatives: Vec::new(),
    };
    assert_eq!(solar.validate(), Ok(()));
    assert_eq!(solar.interpolate_irradiance_linear(762.0), 40.0);
    assert_eq!(solar.interpolate_irradiance(759.0), 10.0);
    assert_eq!(solar.interpolate_irradiance(764.0), 60.0);
    assert!(solar.covers_range(760.0, 763.0));
    assert!(!solar.covers_range(759.9, 763.0));

    assert_eq!(
        OperationalSolarSpectrum {
            wavelengths_nm: vec![760.0, 760.0],
            irradiance: vec![1.0, 2.0],
            spline_second_derivatives: Vec::new(),
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn solar_spectrum_prepares_disamar_style_spline_and_corrects_measured_values() {
    let mut solar = OperationalSolarSpectrum {
        wavelengths_nm: vec![760.0, 761.0, 762.0, 763.0],
        irradiance: vec![10.0, 20.0, 30.0, 40.0],
        spline_second_derivatives: Vec::new(),
    };
    assert_eq!(solar.prepare_interpolation(), Ok(()));
    assert_eq!(solar.spline_second_derivatives, vec![0.0; 4]);
    assert_eq!(solar.interpolate_irradiance(761.5), 25.0);
    let prepared_clone = solar.clone_prepared().unwrap();
    assert_eq!(prepared_clone.spline_second_derivatives, vec![0.0; 4]);

    let corrected = solar
        .correct_measured_spectrum_onto(&[760.0, 761.0], &[2.0, 4.0], &[761.0, 762.0])
        .unwrap();
    assert_eq!(corrected, vec![4.0, 6.0]);
}

#[test]
fn operational_cross_section_lut_validates_and_interpolates_sigma() {
    let lut = OperationalCrossSectionLut {
        wavelengths_nm: vec![760.0, 761.0],
        coefficients: vec![2.0, 4.0],
        temperature_coefficient_count: 1,
        pressure_coefficient_count: 1,
        min_temperature_k: 180.0,
        max_temperature_k: 320.0,
        min_pressure_hpa: 200.0,
        max_pressure_hpa: 1000.0,
    };
    assert_eq!(lut.validate(), Ok(()));
    assert_eq!(lut.sigma_at(760.5, 250.0, 500.0), 3.0);
    assert_eq!(lut.d_sigma_d_temperature_at(760.5, 250.0, 500.0), 0.0);

    assert_eq!(
        OperationalCrossSectionLut {
            coefficients: vec![1.0],
            ..OperationalCrossSectionLut::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn operational_cross_section_lut_evaluates_temperature_derivative_basis() {
    let lut = OperationalCrossSectionLut {
        wavelengths_nm: vec![760.0],
        coefficients: vec![10.0, 2.0],
        temperature_coefficient_count: 2,
        pressure_coefficient_count: 1,
        min_temperature_k: 100.0,
        max_temperature_k: 400.0,
        min_pressure_hpa: 100.0,
        max_pressure_hpa: 1000.0,
    };
    assert_eq!(lut.validate(), Ok(()));
    assert!((lut.sigma_at(760.0, 200.0, 500.0) - 10.0).abs() < 1.0e-14);
    let expected_derivative = 4.0 / (400.0_f64.ln() - 100.0_f64.ln()) / 200.0;
    assert!(
        (lut.d_sigma_d_temperature_at(760.0, 200.0, 500.0) - expected_derivative).abs() < 1.0e-14
    );
}

#[test]
fn spectral_response_requires_line_shape_for_table_slit() {
    assert_eq!(
        SpectralResponse {
            slit_index: SlitIndex::Table,
            scale: 1.0,
            ..SpectralResponse::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        SpectralResponse {
            slit_index: SlitIndex::Table,
            scale: 1.0,
            instrument_line_shape: InstrumentLineShape {
                sample_count: 2,
                offsets_nm: vec![-0.1, 0.1],
                weights: vec![1.0, 1.0],
            },
            ..SpectralResponse::default()
        }
        .validate(),
        Ok(())
    );
}

#[test]
fn ring_controls_validate_degree_and_spectrum_values() {
    assert_eq!(
        RingControls {
            degree_poly: 8,
            ..RingControls::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        RingControls {
            spectrum: vec![1.0, 2.0],
            ..RingControls::default()
        }
        .validate(),
        Ok(())
    );
}

#[test]
fn nodal_and_noise_controls_validate_nested_measurement_inputs() {
    assert_eq!(
        NodalCorrection {
            wavelengths_nm: vec![760.0, 760.0],
            values: vec![1.0, 2.0],
            ..NodalCorrection::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        NodalCorrection {
            wavelengths_nm: vec![760.0, 761.0],
            values: vec![1.0, 2.0],
            variances: vec![0.1, 0.2],
            ..NodalCorrection::default()
        }
        .validate(),
        Ok(())
    );

    assert_eq!(
        NoiseControls {
            enabled: true,
            model: NoiseModelKind::LabOperational,
            ..NoiseControls::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        NoiseControls {
            enabled: true,
            model: NoiseModelKind::LabOperational,
            lab_a: 1.0,
            ..NoiseControls::default()
        }
        .validate(),
        Ok(())
    );
}

#[test]
fn instrument_contract_validates_nested_operational_support() {
    assert_eq!(Instrument::default().validate(), Ok(()));
    assert_eq!(
        Instrument {
            high_resolution_step_nm: 0.01,
            ..Instrument::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );

    let support_without_id = OperationalBandSupport {
        high_resolution_step_nm: 0.01,
        high_resolution_half_span_nm: 0.5,
        ..OperationalBandSupport::default()
    };
    assert_eq!(
        support_without_id.validate(),
        Err(errors::Error::InvalidRequest)
    );

    let support = OperationalBandSupport {
        id: "band_4".to_string(),
        high_resolution_step_nm: 0.01,
        high_resolution_half_span_nm: 0.5,
        operational_solar_spectrum: OperationalSolarSpectrum {
            wavelengths_nm: vec![760.0, 761.0, 762.0],
            irradiance: vec![10.0, 20.0, 30.0],
            spline_second_derivatives: Vec::new(),
        },
        ..OperationalBandSupport::default()
    };
    assert_eq!(support.validate(), Ok(()));
    assert_eq!(
        support
            .clone_prepared()
            .unwrap()
            .operational_solar_spectrum
            .spline_second_derivatives
            .len(),
        3
    );
}
