use zdisamar::common::math::interpolation::spline::{
    Error, endpoint_secant_second_derivatives, sample_endpoint_secant,
    sample_with_second_derivatives,
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

#[test]
fn endpoint_secant_spline_preserves_linear_series() {
    let x = [760.0, 762.0, 764.0];
    let y = [1.0, 3.0, 5.0];

    let second = endpoint_secant_second_derivatives(&x, &y).unwrap();

    assert_eq!(second.len(), 3);
    for value in &second {
        assert_close(*value, 0.0, 1.0e-14);
    }
    assert_close(sample_endpoint_secant(&x, &y, 761.0).unwrap(), 2.0, 1.0e-14);
    assert_close(
        sample_with_second_derivatives(&x, &y, &second, 763.0).unwrap(),
        4.0,
        1.0e-14,
    );
}

#[test]
fn endpoint_secant_spline_reports_shape_and_domain_errors() {
    assert_eq!(
        sample_endpoint_secant(&[1.0, 2.0], &[1.0, 2.0], 1.5),
        Err(Error::NotEnoughPoints)
    );
    assert_eq!(
        sample_endpoint_secant(&[1.0, 2.0, 3.0], &[1.0, 2.0], 1.5),
        Err(Error::ShapeMismatch)
    );
    assert_eq!(
        sample_endpoint_secant(&[1.0, 2.0, 3.0], &[1.0, 2.0, 3.0], 4.0),
        Err(Error::OutOfDomain)
    );
}
