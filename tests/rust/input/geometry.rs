use zdisamar::{
    common::errors,
    input::geometry::{Geometry, Model},
};

fn assert_close(actual: f64, expected: f64) {
    assert!(
        (actual - expected).abs() <= 1.0e-12,
        "{actual} != {expected}"
    );
}

#[test]
fn geometry_rejects_out_of_range_zenith_and_azimuth_angles() {
    assert_eq!(
        Geometry {
            solar_zenith_deg: 32.0,
            viewing_zenith_deg: 9.0,
            relative_azimuth_deg: 145.0,
            ..Geometry::default()
        }
        .validate(),
        Ok(())
    );

    assert_eq!(
        Geometry {
            solar_zenith_deg: 181.0,
            ..Geometry::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Geometry {
            relative_azimuth_deg: 400.0,
            ..Geometry::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn geometry_models_produce_propagation_cosines_with_altitude_consequences() {
    let plane_parallel = Geometry {
        model: Model::PlaneParallel,
        solar_zenith_deg: 70.0,
        viewing_zenith_deg: 55.0,
        ..Geometry::default()
    };
    let pseudo_spherical = Geometry {
        model: Model::PseudoSpherical,
        solar_zenith_deg: 70.0,
        viewing_zenith_deg: 55.0,
        ..Geometry::default()
    };

    let plane_mu = plane_parallel.solar_cosine_at_altitude(12.0);
    let pseudo_mu = pseudo_spherical.solar_cosine_at_altitude(12.0);
    assert_close(plane_mu, 70.0_f64.to_radians().cos());
    assert!(pseudo_mu >= plane_mu);
    assert!(
        pseudo_spherical.viewing_cosine_at_altitude(12.0)
            >= plane_parallel.viewing_cosine_at_altitude(12.0)
    );
}
