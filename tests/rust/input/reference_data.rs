use zdisamar::input::{
    AirmassFactorLut, AirmassFactorPoint, ClimatologyPoint, ClimatologyProfile,
    CollisionInducedAbsorptionPoint, CollisionInducedAbsorptionTable, CrossSectionPoint,
    CrossSectionTable, SpectroscopyLine, SpectroscopyLineList, SpectroscopyRuntimeControls,
    weighted_mean_samples,
};

fn assert_close(actual: f64, expected: f64) {
    assert!(
        (actual - expected).abs() < 1.0e-12,
        "{actual} != {expected}"
    );
}

#[test]
fn climatology_interpolates_profile_values() {
    let profile = ClimatologyProfile {
        rows: vec![
            ClimatologyPoint {
                altitude_km: 0.0,
                pressure_hpa: 1000.0,
                temperature_k: 290.0,
                air_number_density_cm3: 2.0,
            },
            ClimatologyPoint {
                altitude_km: 10.0,
                pressure_hpa: 250.0,
                temperature_k: 230.0,
                air_number_density_cm3: 1.0,
            },
        ],
    };

    assert_close(profile.mean_number_density(), 1.5);
    assert_close(profile.interpolate_temperature(5.0), 260.0);
    assert_close(profile.interpolate_density(5.0), 1.5);
    assert_close(profile.interpolate_altitude_for_pressure(500.0), 5.0);
    assert_eq!(profile.max_altitude(), 10.0);
}

#[test]
fn cross_section_table_interpolates_and_averages() {
    let table = CrossSectionTable {
        points: vec![
            CrossSectionPoint {
                wavelength_nm: 760.0,
                sigma_cm2_per_molecule: 1.0,
            },
            CrossSectionPoint {
                wavelength_nm: 762.0,
                sigma_cm2_per_molecule: 3.0,
            },
        ],
    };

    assert_close(table.interpolate_sigma(761.0), 2.0);
    assert_close(table.sigma_at_high_resolution(761.0), 2.0);
    assert_close(table.mean_sigma_in_range(760.0, 762.0), 2.0);
    assert_eq!(table.bracket_for_wavelength(761.0), Some((0, 1)));
}

#[test]
fn cia_table_interpolates_coefficients_and_temperature_terms() {
    let table = CollisionInducedAbsorptionTable {
        scale_factor_cm5_per_molecule2: 2.0,
        points: vec![
            CollisionInducedAbsorptionPoint {
                wavelength_nm: 760.0,
                a0: 1.0,
                a1: 0.1,
                a2: 0.0,
            },
            CollisionInducedAbsorptionPoint {
                wavelength_nm: 762.0,
                a0: 3.0,
                a1: 0.3,
                a2: 0.0,
            },
        ],
    };

    let sigma = table.sigma_at(761.0, 273.15);
    assert_close(sigma, 4.0);
    assert_close(table.d_sigma_d_temperature_at(761.0, 273.15), 0.4);
    assert_close(table.mean_sigma_in_range(760.0, 762.0, 273.15), 4.0);
}

#[test]
fn airmass_lut_uses_nearest_geometry() {
    let lut = AirmassFactorLut {
        points: vec![
            AirmassFactorPoint {
                solar_zenith_deg: 30.0,
                view_zenith_deg: 0.0,
                relative_azimuth_deg: 0.0,
                airmass_factor: 1.1,
            },
            AirmassFactorPoint {
                solar_zenith_deg: 70.0,
                view_zenith_deg: 20.0,
                relative_azimuth_deg: 180.0,
                airmass_factor: 3.0,
            },
        ],
    };

    assert_close(lut.nearest(69.0, 21.0, 179.0), 3.0);
    assert!(lut.provides_support_only());
}

#[test]
fn spectroscopy_runtime_controls_report_threshold_strength() {
    let controls = SpectroscopyRuntimeControls {
        threshold_line_scale: Some(0.1),
        ..SpectroscopyRuntimeControls::default()
    };
    let lines = vec![
        SpectroscopyLine {
            line_strength_cm2_per_molecule: 2.0,
            ..SpectroscopyLine::default()
        },
        SpectroscopyLine {
            line_strength_cm2_per_molecule: 5.0,
            ..SpectroscopyLine::default()
        },
    ];

    assert_close(controls.threshold_strength(&lines).unwrap(), 0.5);
    assert!(
        SpectroscopyLineList {
            lines,
            strong_lines: Some(Vec::new()),
            relaxation_matrix: Some(Default::default()),
            ..SpectroscopyLineList::default()
        }
        .has_strong_line_sidecars()
    );
    assert_close(weighted_mean_samples(&[1.0, 3.0], &[1.0, 3.0]), 2.5);
}
