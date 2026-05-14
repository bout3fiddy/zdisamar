use zdisamar::input::atmospheric_types::AbsorberSpecies;

#[test]
fn absorber_species_preserve_reference_classification() {
    assert!(AbsorberSpecies::O2.is_line_absorbing());
    assert!(!AbsorberSpecies::O2O2.is_line_absorbing());
    assert!(AbsorberSpecies::O2O2.is_cross_section());
    assert!(!AbsorberSpecies::O2.is_cross_section());
    assert!(!AbsorberSpecies::O2.is_column_fittable());
    assert!(!AbsorberSpecies::O2O2.is_profile_fittable());
    assert_eq!(AbsorberSpecies::O2.hitran_index(), Some(7));
    assert_eq!(AbsorberSpecies::O2O2.hitran_index(), None);
}

#[test]
fn absorber_species_parse_vendor_names() {
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
