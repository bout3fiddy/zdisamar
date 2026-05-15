use zdisamar::input::reference::airmass_phase::{
    AirmassFactorLut, AirmassFactorPoint, Error, MiePhasePoint, MiePhaseTable,
    spectral_profile_from_optical_depth,
};
use zdisamar::input::reference::solar_irradiance::{
    bundled_solar_irradiance, default_solar_continuum_irradiance, irradiance_at_wavelength,
};
use zdisamar::input::reference_data::{
    CollisionInducedAbsorptionPoint, CollisionInducedAbsorptionTable, CrossSectionPoint,
    CrossSectionTable,
};
use zdisamar::input::{binding::Binding, scene::Scene};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

#[test]
fn solar_irradiance_uses_bundled_o2a_source_or_continuum_fallback() {
    assert_close(
        bundled_solar_irradiance(760.01).unwrap(),
        4.858697784e14,
        1.0,
    );
    assert!(bundled_solar_irradiance(700.0).is_none());
    assert_close(default_solar_continuum_irradiance(760.0), 4.87401e14, 1.0);

    let mut scene = Scene::default();
    scene.observation_model.solar_spectrum_source = Binding::BundleDefault;
    assert_close(
        irradiance_at_wavelength(&scene, 760.01),
        4.858697784e14,
        1.0,
    );

    scene.observation_model.solar_spectrum_source = Binding::None;
    assert_close(irradiance_at_wavelength(&scene, 760.0), 4.87401e14, 1.0);
}

#[test]
fn mie_phase_table_interpolates_spectral_support() {
    let table = MiePhaseTable {
        points: vec![
            MiePhasePoint {
                wavelength_nm: 760.0,
                extinction_scale: 1.0,
                single_scatter_albedo: 0.9,
                phase_coefficients: [1.0, 0.2, 0.1, 0.0],
            },
            MiePhasePoint {
                wavelength_nm: 770.0,
                extinction_scale: 1.4,
                single_scatter_albedo: 0.8,
                phase_coefficients: [1.0, 0.4, 0.3, 0.2],
            },
        ],
    };

    let midpoint = table.interpolate(765.0);

    assert_close(midpoint.extinction_scale, 1.2, 1.0e-14);
    assert_close(midpoint.single_scatter_albedo, 0.85, 1.0e-14);
    for (actual, expected) in midpoint.phase_coefficients.iter().zip([1.0, 0.3, 0.2, 0.1]) {
        assert_close(*actual, expected, 1.0e-14);
    }
    assert_eq!(table.interpolate(750.0), table.points[0]);
    assert_eq!(table.interpolate(780.0), table.points[1]);
}

#[test]
fn airmass_lut_selects_nearest_geometry() {
    let lut = AirmassFactorLut {
        points: vec![
            AirmassFactorPoint {
                solar_zenith_deg: 20.0,
                view_zenith_deg: 10.0,
                relative_azimuth_deg: 0.0,
                airmass_factor: 1.1,
            },
            AirmassFactorPoint {
                solar_zenith_deg: 60.0,
                view_zenith_deg: 30.0,
                relative_azimuth_deg: 90.0,
                airmass_factor: 2.4,
            },
        ],
    };

    assert_close(lut.nearest(58.0, 29.0, 80.0), 2.4, 0.0);
    assert!(lut.provides_support_only());
    assert_close(AirmassFactorLut::default().nearest(1.0, 2.0, 3.0), 1.0, 0.0);
}

#[test]
fn spectral_profile_preserves_requested_mean() {
    let wavelengths = [760.0, 761.0, 762.0];
    let proxy = [1.0, 2.0, 3.0];
    let profile = spectral_profile_from_optical_depth(&wavelengths, 2.0, &proxy).unwrap();
    let mean = profile.iter().sum::<f64>() / profile.len() as f64;

    assert_close(mean, 2.0, 1.0e-14);
    assert!(profile[2] > profile[1]);
    assert!(profile[1] > profile[0]);
    assert_eq!(
        spectral_profile_from_optical_depth(&wavelengths, 2.0, &proxy[..2]),
        Err(Error::ShapeMismatch)
    );
}

#[test]
fn cross_section_table_interpolates_and_averages_ranges() {
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
            CrossSectionPoint {
                wavelength_nm: 764.0,
                sigma_cm2_per_molecule: 5.0,
            },
        ],
    };

    assert_close(table.interpolate_sigma(761.0), 2.0, 1.0e-14);
    assert_close(table.interpolate_sigma(700.0), 1.0, 0.0);
    assert_close(table.interpolate_sigma(800.0), 5.0, 0.0);
    assert_eq!(table.bracket_for_wavelength(761.0), Some((0, 1)));
    assert_close(table.sigma_at_high_resolution(763.0), 4.0, 1.0e-14);
    assert_close(table.mean_sigma_in_range(760.0, 762.0), 2.0, 1.0e-14);
    assert_close(table.mean_sigma_in_range(765.0, 766.0), 5.0, 0.0);
}

#[test]
fn collision_induced_absorption_table_evaluates_temperature_polynomial() {
    let table = CollisionInducedAbsorptionTable {
        scale_factor_cm5_per_molecule2: 2.0,
        points: vec![
            CollisionInducedAbsorptionPoint {
                wavelength_nm: 760.0,
                a0: 1.0,
                a1: 0.1,
                a2: 0.01,
            },
            CollisionInducedAbsorptionPoint {
                wavelength_nm: 762.0,
                a0: 3.0,
                a1: 0.3,
                a2: 0.03,
            },
            CollisionInducedAbsorptionPoint {
                wavelength_nm: 764.0,
                a0: 5.0,
                a1: 0.5,
                a2: 0.05,
            },
        ],
    };
    let temperature_k = 274.15;

    assert_close(table.sigma_at(761.0, temperature_k), 4.44, 1.0e-14);
    assert_close(
        table.d_sigma_d_temperature_at(761.0, temperature_k),
        0.48,
        1.0e-14,
    );
    assert_close(
        table.mean_sigma_in_range(760.0, 762.0, temperature_k),
        (2.22 + 6.66) * 0.5,
        1.0e-14,
    );
    let coefficients = table.interpolate_coefficients(765.0);
    assert_close(coefficients.a0, 5.0, 0.0);
}

#[test]
fn collision_induced_absorption_clamps_negative_sigma_and_derivative() {
    let table = CollisionInducedAbsorptionTable {
        scale_factor_cm5_per_molecule2: 3.0,
        points: vec![CollisionInducedAbsorptionPoint {
            wavelength_nm: 760.0,
            a0: -1.0,
            a1: 0.0,
            a2: 0.0,
        }],
    };

    assert_close(table.sigma_at(760.0, 273.15), 0.0, 0.0);
    assert_close(table.d_sigma_d_temperature_at(760.0, 273.15), 0.0, 0.0);
    assert_close(table.mean_sigma_in_range(761.0, 762.0, 273.15), 0.0, 0.0);
}
