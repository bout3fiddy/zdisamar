use zdisamar::{
    common::errors::Error,
    input::{
        Absorber, AbsorberSet, AbsorberSpecies, AbsorptionRepresentation, Binding,
        CrossSectionPoint, CrossSectionTable, LineGasControls, NamedRef,
        OperationalCrossSectionLut, Spectroscopy, SpectroscopyLineList, SpectroscopyMode,
        SpectroscopyStage, resolve_absorber_species_name, resolved_absorber_species,
        validate_volume_mixing_ratio_profile,
    },
};

#[test]
fn absorber_species_resolution_accepts_vendor_names() {
    assert_eq!(
        resolve_absorber_species_name("O2"),
        Some(AbsorberSpecies::O2)
    );
    assert_eq!(
        resolve_absorber_species_name("O2-O2"),
        Some(AbsorberSpecies::O2O2)
    );
    assert_eq!(resolve_absorber_species_name("CO2"), None);
}

#[test]
fn line_gas_controls_validate_and_select_active_stage_values() {
    let controls = LineGasControls {
        factor_lm_sim: Some(0.8),
        factor_lm_retr: Some(1.2),
        isotopes_sim: vec![1, 2],
        isotopes_retr: vec![3],
        threshold_line_sim: Some(0.01),
        cutoff_retr_cm1: Some(12.0),
        active_stage: SpectroscopyStage::Retrieval,
        ..LineGasControls::default()
    };

    assert_eq!(controls.validate(), Ok(()));
    assert!(controls.configured());
    assert_eq!(controls.active_line_mixing_factor(), 1.2);
    assert_eq!(controls.active_isotopes(), &[3]);
    assert_eq!(controls.active_threshold_line(), None);
    assert_eq!(controls.active_cutoff_cm1(), Some(12.0));

    assert_eq!(
        LineGasControls {
            isotopes_sim: vec![1, 1],
            ..LineGasControls::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn spectroscopy_rejects_disabled_state_with_payloads_and_mismatched_resolved_data() {
    assert_eq!(
        Spectroscopy {
            provider: "hitran".to_string(),
            ..Spectroscopy::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        Spectroscopy {
            mode: SpectroscopyMode::LineByLine,
            resolved_cross_section_table: Some(CrossSectionTable::default()),
            ..Spectroscopy::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        Spectroscopy {
            mode: SpectroscopyMode::CrossSections,
            cross_section_table: Binding::Asset(NamedRef {
                name: "xsec".to_string()
            }),
            operational_lut: Binding::Asset(NamedRef {
                name: "lut".to_string()
            }),
            ..Spectroscopy::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn spectroscopy_reports_resolved_absorption_representation_priority() {
    let line_list = SpectroscopyLineList::default();
    let table = CrossSectionTable {
        points: vec![CrossSectionPoint {
            wavelength_nm: 760.0,
            sigma_cm2_per_molecule: 1.0,
        }],
    };
    let lut = OperationalCrossSectionLut {
        wavelengths_nm: vec![760.0],
        coefficients: vec![1.0],
        temperature_coefficient_count: 1,
        pressure_coefficient_count: 1,
        min_temperature_k: 200.0,
        max_temperature_k: 320.0,
        min_pressure_hpa: 100.0,
        max_pressure_hpa: 1000.0,
    };
    let spectroscopy = Spectroscopy {
        mode: SpectroscopyMode::CrossSections,
        operational_lut: Binding::Asset(NamedRef {
            name: "lut".to_string(),
        }),
        resolved_line_list: Some(line_list),
        resolved_cross_section_table: Some(table),
        resolved_cross_section_lut: Some(lut),
        ..Spectroscopy::default()
    };

    assert!(matches!(
        spectroscopy.resolved_absorption_representation(),
        AbsorptionRepresentation::XsecLut(_)
    ));
}

#[test]
fn absorber_validates_species_profile_and_duplicates() {
    let absorber = Absorber {
        id: "o2".to_string(),
        species: "O2".to_string(),
        profile_source: Binding::Asset(NamedRef {
            name: "profile".to_string(),
        }),
        volume_mixing_ratio_profile_ppmv: vec![[1000.0, 0.21], [500.0, 0.20], [100.0, 0.19]],
        ..Absorber::default()
    };

    assert_eq!(absorber.validate(), Ok(()));
    assert_eq!(
        resolved_absorber_species(&absorber),
        Some(AbsorberSpecies::O2)
    );
    assert_eq!(
        validate_volume_mixing_ratio_profile(&[[1000.0, 0.2], [500.0, 0.1], [700.0, 0.1]]),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        AbsorberSet {
            items: vec![absorber.clone(), absorber]
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}
