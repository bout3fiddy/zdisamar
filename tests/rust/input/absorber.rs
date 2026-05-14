use zdisamar::{
    common::errors,
    input::{
        absorber::{
            Absorber, AbsorberSet, AbsorptionRepresentation, LineGasControls, Spectroscopy,
            SpectroscopyMode, SpectroscopyStage, resolved_absorber_species,
            validate_volume_mixing_ratio_profile,
        },
        atmospheric_types::AbsorberSpecies,
        binding::{Binding, IngestRef, NamedRef},
        instrument::OperationalCrossSectionLut,
        reference_data::{CrossSectionTable, SpectroscopyLineList},
    },
};

#[test]
fn absorber_set_validates_explicit_spectroscopy_bindings() {
    let valid = AbsorberSet {
        items: vec![
            Absorber {
                id: "o2".to_string(),
                species: "o2".to_string(),
                profile_source: Binding::Atmosphere,
                spectroscopy: Spectroscopy {
                    mode: SpectroscopyMode::LineByLine,
                    provider: "builtin.cross_sections".to_string(),
                    line_list: Binding::Asset(NamedRef {
                        name: "o2_hitran".to_string(),
                    }),
                    ..Spectroscopy::default()
                },
                ..Absorber::default()
            },
            Absorber {
                id: "o2o2".to_string(),
                species: "o2o2".to_string(),
                profile_source: Binding::Atmosphere,
                spectroscopy: Spectroscopy {
                    mode: SpectroscopyMode::Cia,
                    cia_table: Binding::Asset(NamedRef {
                        name: "o2o2_cia".to_string(),
                    }),
                    ..Spectroscopy::default()
                },
                ..Absorber::default()
            },
            Absorber {
                id: "o2o2_direct".to_string(),
                species: "o2o2".to_string(),
                profile_source: Binding::Atmosphere,
                spectroscopy: Spectroscopy {
                    mode: SpectroscopyMode::CrossSections,
                    cross_section_table: Binding::Asset(NamedRef {
                        name: "o2o2_direct_demo".to_string(),
                    }),
                    ..Spectroscopy::default()
                },
                ..Absorber::default()
            },
        ],
    };
    assert_eq!(valid.validate(), Ok(()));

    assert_eq!(
        AbsorberSet {
            items: vec![Absorber {
                id: "o2".to_string(),
                species: "o2".to_string(),
                spectroscopy: Spectroscopy {
                    mode: SpectroscopyMode::None,
                    line_list: Binding::Asset(NamedRef {
                        name: "unexpected".to_string(),
                    }),
                    ..Spectroscopy::default()
                },
                ..Absorber::default()
            }],
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );

    assert_eq!(
        AbsorberSet {
            items: vec![Absorber {
                id: "o2o2".to_string(),
                species: "o2o2".to_string(),
                profile_source: Binding::Atmosphere,
                spectroscopy: Spectroscopy {
                    mode: SpectroscopyMode::CrossSections,
                    cross_section_table: Binding::Asset(NamedRef {
                        name: "o2o2_table".to_string(),
                    }),
                    operational_lut: Binding::Ingest(IngestRef::from_full_name(
                        "demo.o2o2_operational_lut",
                    )),
                    ..Spectroscopy::default()
                },
                ..Absorber::default()
            }],
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn resolved_absorber_species_normalizes_legacy_o2_o2_aliases() {
    assert_eq!(
        resolved_absorber_species(&Absorber {
            id: "o2_o2".to_string(),
            species: "o2_o2".to_string(),
            ..Absorber::default()
        }),
        Some(AbsorberSpecies::O2O2)
    );
    assert_eq!(
        resolved_absorber_species(&Absorber {
            id: "o2o2".to_string(),
            species: "o2o2".to_string(),
            ..Absorber::default()
        }),
        Some(AbsorberSpecies::O2O2)
    );
    assert_eq!(
        resolved_absorber_species(&Absorber {
            id: "o2-o2".to_string(),
            species: "o2-o2".to_string(),
            ..Absorber::default()
        }),
        Some(AbsorberSpecies::O2O2)
    );
}

#[test]
fn spectroscopy_resolves_explicit_absorption_representation_tags() {
    let line_spectroscopy = Spectroscopy {
        resolved_line_list: Some(SpectroscopyLineList::default()),
        ..Spectroscopy::default()
    };
    assert!(matches!(
        line_spectroscopy.resolved_absorption_representation(),
        AbsorptionRepresentation::LineAbs(_)
    ));

    let cross_section_spectroscopy = Spectroscopy {
        mode: SpectroscopyMode::CrossSections,
        resolved_cross_section_table: Some(CrossSectionTable::default()),
        ..Spectroscopy::default()
    };
    assert!(matches!(
        cross_section_spectroscopy.resolved_absorption_representation(),
        AbsorptionRepresentation::XsecTable(_)
    ));

    let operational_lut_spectroscopy = Spectroscopy {
        mode: SpectroscopyMode::LineByLine,
        operational_lut: Binding::Ingest(IngestRef::from_full_name("demo.o2_operational_lut")),
        resolved_cross_section_lut: Some(OperationalCrossSectionLut {
            wavelengths_nm: vec![760.0, 761.0],
            coefficients: vec![1.0, 0.0, 1.1, 0.0],
            temperature_coefficient_count: 1,
            pressure_coefficient_count: 2,
            min_temperature_k: 200.0,
            max_temperature_k: 320.0,
            min_pressure_hpa: 100.0,
            max_pressure_hpa: 1100.0,
        }),
        ..Spectroscopy::default()
    };
    assert!(matches!(
        operational_lut_spectroscopy.resolved_absorption_representation(),
        AbsorptionRepresentation::XsecLut(_)
    ));
}

#[test]
fn line_gas_controls_validate_stage_specific_isotope_and_cutoff_selections() {
    assert_eq!(
        LineGasControls {
            factor_lm_sim: Some(1.0),
            isotopes_sim: vec![1, 2],
            threshold_line_sim: Some(0.05),
            cutoff_sim_cm1: Some(12.0),
            active_stage: SpectroscopyStage::Simulation,
            ..LineGasControls::default()
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        LineGasControls {
            factor_lm_sim: Some(1.0),
            active_stage: SpectroscopyStage::Simulation,
            ..LineGasControls::default()
        }
        .active_line_mixing_factor(),
        1.0
    );
    assert_eq!(
        LineGasControls {
            isotopes_retr: vec![1, 2],
            active_stage: SpectroscopyStage::Retrieval,
            ..LineGasControls::default()
        }
        .active_isotopes(),
        &[1, 2]
    );
    assert_eq!(
        LineGasControls {
            threshold_line_sim: Some(0.05),
            ..LineGasControls::default()
        }
        .active_threshold_line(),
        Some(0.05)
    );
    assert_eq!(
        LineGasControls {
            cutoff_sim_cm1: Some(12.0),
            ..LineGasControls::default()
        }
        .active_cutoff_cm1(),
        Some(12.0)
    );
    assert_eq!(
        LineGasControls {
            isotopes_sim: vec![1, 1],
            ..LineGasControls::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        LineGasControls {
            cutoff_retr_cm1: Some(0.0),
            ..LineGasControls::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn volume_mixing_ratio_profiles_must_be_strictly_monotonic_in_pressure() {
    assert_eq!(
        validate_volume_mixing_ratio_profile(&[[1000.0, 400.0], [700.0, 250.0], [430.0, 200.0]]),
        Ok(())
    );
    assert_eq!(
        validate_volume_mixing_ratio_profile(&[[430.0, 200.0], [700.0, 250.0], [1000.0, 400.0]]),
        Ok(())
    );
    assert_eq!(
        validate_volume_mixing_ratio_profile(&[[1000.0, 400.0], [430.0, 200.0], [700.0, 250.0]]),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        validate_volume_mixing_ratio_profile(&[[1000.0, 400.0], [1000.0, 350.0]]),
        Err(errors::Error::InvalidRequest)
    );
}
