use zdisamar::input::reference::airmass_phase::{
    AirmassFactorLut, AirmassFactorPoint, Error, MiePhasePoint, MiePhaseTable,
    spectral_profile_from_optical_depth,
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
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
