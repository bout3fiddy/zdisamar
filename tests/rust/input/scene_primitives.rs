use zdisamar::{
    common::errors::Error,
    input::{
        Geometry, Model, Parameter, SpectralBand, SpectralBandSet, SpectralWindow, Surface,
        SurfaceKind,
    },
};

fn assert_close(actual: f64, expected: f64) {
    assert!(
        (actual - expected).abs() < 1.0e-12,
        "{actual} != {expected}"
    );
}

#[test]
fn geometry_validates_angles_and_keeps_near_horizon_floor() {
    assert_eq!(Geometry::default().validate(), Ok(()));
    assert_eq!(
        Geometry {
            solar_zenith_deg: 181.0,
            ..Geometry::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );

    let plane = Geometry {
        solar_zenith_deg: 89.0,
        model: Model::PlaneParallel,
        ..Geometry::default()
    };
    assert_close(
        plane.solar_cosine_at_altitude(100.0),
        89.0_f64.to_radians().cos().max(0.05),
    );

    let spherical = Geometry {
        solar_zenith_deg: 89.9,
        model: Model::Spherical,
        ..Geometry::default()
    };
    assert!(spherical.solar_cosine_at_altitude(0.0) >= 0.05);
    assert!(spherical.viewing_cosine_at_altitude(20.0).is_finite());
}

#[test]
fn surface_parameters_and_kind_labels_match_input_names() {
    assert_eq!(
        SurfaceKind::parse("lambertian"),
        Ok(SurfaceKind::Lambertian)
    );
    assert_eq!(SurfaceKind::WavelDependent.label(), "wavel_dependent");

    let surface = Surface {
        albedo: 0.3,
        pressure_hpa: 1013.25,
        parameters: vec![Parameter {
            name: "roughness".to_string(),
            value: 0.1,
        }],
        ..Surface::default()
    };
    assert_eq!(surface.validate(), Ok(()));
    assert_eq!(
        Surface {
            albedo: 1.1,
            ..Surface::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn spectral_grid_and_bands_validate_ranges_and_exclusions() {
    let band = SpectralBand {
        id: "o2a".to_string(),
        start_nm: 755.0,
        end_nm: 770.0,
        step_nm: 0.01,
        exclude: vec![SpectralWindow {
            start_nm: 760.0,
            end_nm: 761.0,
        }],
    };
    assert_eq!(band.validate(), Ok(()));
    assert_eq!(
        SpectralBandSet {
            items: vec![band.clone(), band]
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        SpectralBand {
            id: "bad".to_string(),
            start_nm: 755.0,
            end_nm: 770.0,
            step_nm: 0.01,
            exclude: vec![SpectralWindow {
                start_nm: 754.0,
                end_nm: 755.5,
            }],
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}
