use zdisamar::input::{AbsorberSpecies, AerosolType, CloudType};

#[test]
fn particle_type_defaults_match_disabled_zig_tags() {
    assert_eq!(CloudType::default(), CloudType::None);
    assert_eq!(AerosolType::default(), AerosolType::None);
}

#[test]
fn absorber_species_reports_domain_roles() {
    assert!(AbsorberSpecies::O2.is_line_absorbing());
    assert!(!AbsorberSpecies::O2.is_cross_section());
    assert_eq!(AbsorberSpecies::O2.hitran_index(), Some(7));

    assert!(!AbsorberSpecies::O2O2.is_line_absorbing());
    assert!(AbsorberSpecies::O2O2.is_cross_section());
    assert_eq!(AbsorberSpecies::O2O2.hitran_index(), None);
    assert!(!AbsorberSpecies::O2O2.is_column_fittable());
    assert!(!AbsorberSpecies::O2O2.is_profile_fittable());
}

#[test]
fn absorber_species_resolves_vendor_names() {
    assert_eq!(
        AbsorberSpecies::from_vendor_name("O2-O2"),
        Some(AbsorberSpecies::O2O2)
    );
    assert_eq!(
        AbsorberSpecies::from_vendor_name("O2"),
        Some(AbsorberSpecies::O2)
    );
    assert_eq!(AbsorberSpecies::from_vendor_name("CO2"), None);
}
