use zdisamar::forward_model::{
    optical_properties::shared::phase_functions,
    radiative_transfer::labos::{
        FourierPlmBasis, Geometry, fill_zplus_zmin, fill_zplus_zmin_from_basis_limited,
        fill_zplus_zmin_row_from_basis_limited,
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

#[test]
fn zero_fourier_basis_starts_with_geometry_weights() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let basis = FourierPlmBasis::init(0, 2, &geometry);

    for imu in 0..geometry.nmutot {
        assert_close(basis.plus[0][imu], geometry.w[imu], 1.0e-12);
        assert_close(basis.minus[0][imu], geometry.w[imu], 1.0e-12);
    }
}

#[test]
fn isotropic_zero_fourier_kernel_is_outer_product_of_weights() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let coefficients = phase_functions::zero_phase_coefficients();
    let kernel = fill_zplus_zmin(0, coefficients, &geometry);

    for i in 0..geometry.nmutot {
        for j in 0..geometry.nmutot {
            let expected = geometry.w[i] * geometry.w[j];
            assert_close(kernel.zplus.get(i, j), expected, 1.0e-12);
            assert_close(kernel.zmin.get(i, j), expected, 1.0e-12);
        }
    }
}

#[test]
fn row_limited_kernel_matches_full_kernel_row() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let mut coefficients = phase_functions::zero_phase_coefficients();
    coefficients[1] = 0.4;
    coefficients[2] = 0.1;
    let basis = FourierPlmBasis::init(1, 2, &geometry);

    let full = fill_zplus_zmin_from_basis_limited(1, coefficients, 2, &geometry, &basis);
    let row = fill_zplus_zmin_row_from_basis_limited(1, coefficients, 2, &geometry, &basis, 3);

    for j in 0..geometry.nmutot {
        assert_close(row.zplus[j], full.zplus.get(3, j), 1.0e-12);
        assert_close(row.zmin[j], full.zmin.get(3, j), 1.0e-12);
    }
}

#[test]
fn fourier_order_above_phase_support_returns_zero_kernel() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let coefficients = phase_functions::zero_phase_coefficients();
    let basis = FourierPlmBasis::init(3, 0, &geometry);

    let kernel = fill_zplus_zmin_from_basis_limited(3, coefficients, 0, &geometry, &basis);
    for value in kernel.zplus.data[..geometry.nmutot * geometry.nmutot].iter() {
        assert_close(*value, 0.0, 0.0);
    }
}
