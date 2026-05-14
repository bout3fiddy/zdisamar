use zdisamar::forward_model::{
    jacobian::{self, State},
    optical_properties::shared::phase_functions,
    radiative_transfer::{
        LayerInput, PseudoSphericalGrid, PseudoSphericalSample,
        labos::{
            FourierPlmBasis, Geometry, MAX_EXTRA, MAX_GAUSS, MAX_N2, MAX_NMUTOT, Mat,
            Vec as LabosVec, Vec2, attenuation, fill_zplus_zmin,
            fill_zplus_zmin_from_basis_limited, fill_zplus_zmin_row_from_basis_limited, matrix,
        },
    },
};

fn assert_close(left: f64, right: f64) {
    assert!((left - right).abs() <= 1.0e-12, "{left} != {right}");
}

#[test]
fn labos_fixed_size_types_match_zig_layout_limits() {
    assert_eq!(MAX_GAUSS, 10);
    assert_eq!(MAX_EXTRA, 2);
    assert_eq!(MAX_NMUTOT, 12);
    assert_eq!(MAX_N2, 144);

    let mut mat = Mat::identity(4);
    assert_eq!(mat.get(2, 2), 1.0);
    assert_eq!(mat.get(2, 1), 0.0);
    mat.set(2, 1, 3.5);
    assert_eq!(mat.get(2, 1), 3.5);

    let mut vector = LabosVec::zero(4);
    vector.set(3, 1.25);
    assert_eq!(vector.get(3), 1.25);

    let two = Vec2::zero(4);
    assert_eq!(two.n, 4);
    assert_eq!(two.col[0].n, 4);
    assert_eq!(two.col[1].get(0), 0.0);
}

#[test]
fn labos_matrix_products_use_only_active_gauss_columns() {
    let n = 3;
    let mut a = Mat::identity(n);
    let mut b = Mat::zero(n);
    for i in 0..n {
        for j in 0..n {
            b.set(i, j, 10.0 * i as f64 + j as f64 + 1.0);
        }
    }

    let product = matrix::smul(n, 2, 0.0, &a, &b);
    assert_close(product.get(0, 0), 1.0);
    assert_close(product.get(1, 2), 13.0);
    assert_close(product.get(2, 0), 0.0);

    a.set(0, 0, 0.0);
    a.set(1, 1, 0.0);
    let zeroed = matrix::smul(n, 2, 1.0e-12, &a, &b);
    assert_eq!(zeroed.data[..n * n], [0.0; 9]);
}

#[test]
fn labos_matrix_scale_and_add_helpers_match_column_and_row_rules() {
    let n = 3;
    let mut e = LabosVec::zero(n);
    e.set(0, 2.0);
    e.set(1, 3.0);
    e.set(2, 4.0);

    let mut a = Mat::zero(n);
    let mut b = Mat::zero(n);
    for i in 0..n {
        for j in 0..n {
            a.set(i, j, 1.0 + i as f64 + j as f64);
            b.set(i, j, 10.0 + i as f64 + j as f64);
        }
    }

    assert_close(matrix::esmul(n, &e, &a).get(2, 1), e.get(2) * a.get(2, 1));
    assert_close(matrix::semul(n, &a, &e).get(2, 1), a.get(2, 1) * e.get(1));
    assert_close(
        matrix::mat_add(n, &a, &b).get(0, 2),
        a.get(0, 2) + b.get(0, 2),
    );
    assert_close(
        matrix::mat_add_semul3(n, &a, &b, &e, &a).get(1, 2),
        a.get(1, 2) + b.get(1, 2) * e.get(2) + a.get(1, 2),
    );
    assert_close(
        matrix::esmul_semul_add(n, &e, &a, &b, &a).get(1, 2),
        e.get(1) * a.get(1, 2) + b.get(1, 2) * e.get(2) + a.get(1, 2),
    );
}

#[test]
fn labos_qseries_solves_gauss_block_and_preserves_weak_products() {
    let n = 3;
    let mut small = Mat::zero(n);
    small.set(0, 0, 1.0e-4);
    small.set(1, 1, 1.0e-4);

    let weak = matrix::qseries_known_nonzero_product(n, 2, &small, &Mat::identity(n));
    assert_close(weak.get(0, 0), 1.0e-4);

    let mut a = Mat::zero(n);
    a.set(0, 0, 0.2);
    a.set(1, 1, 0.1);
    a.set(2, 0, 0.4);
    let mut b = Mat::zero(n);
    b.set(0, 0, 1.0);
    b.set(0, 2, 1.5);
    b.set(1, 1, 1.0);

    let series = matrix::qseries_known_nonzero_product(n, 2, &a, &b);
    assert_close(series.get(0, 0), 0.25);
    assert_close(series.get(1, 1), 1.0 / 0.9 - 1.0);
    assert_close(series.get(0, 2), 0.375);
    assert_close(series.get(2, 0), 0.5);
    assert_close(series.get(2, 2), 0.75);
}

#[test]
fn labos_attenuation_builds_symmetric_level_transmittance() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let layers = vec![
        LayerInput {
            optical_depth: 0.1,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.2,
            ..LayerInput::default()
        },
    ];
    let u = geometry.u[0];

    let atten = attenuation::fill_attenuation(&layers, &geometry, false);
    assert_close(atten.get(0, 0, 0), 1.0);
    assert_close(atten.get(0, 0, 1), (-0.1 / u).exp());
    assert_close(atten.get(0, 0, 2), (-(0.1 + 0.2) / u).exp());
    assert_close(atten.get(0, 2, 0), atten.get(0, 0, 2));

    let dynamic = attenuation::fill_attenuation_dynamic(&layers, &geometry, false);
    assert_close(dynamic.get(0, 0, 2), atten.get(0, 0, 2));
}

#[test]
fn labos_attenuation_uses_pseudo_spherical_top_level_direction_cosines() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let layers = vec![
        LayerInput {
            optical_depth: 0.1,
            view_mu: 0.5,
            solar_mu: 0.7,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.2,
            view_mu: 0.4,
            solar_mu: 0.6,
            ..LayerInput::default()
        },
    ];

    let atten = attenuation::fill_attenuation(&layers, &geometry, true);
    let view_idx = geometry.view_idx();
    let solar_idx = geometry.n_gauss + 1;
    assert_close(
        atten.get(view_idx, 2, 0),
        (-0.2_f64 / 0.4).exp() * (-0.1_f64 / 0.5).exp(),
    );
    assert_close(
        atten.get(solar_idx, 2, 0),
        (-0.2_f64 / 0.6).exp() * (-0.1_f64 / 0.7).exp(),
    );
}

#[test]
fn labos_dynamic_attenuation_uses_explicit_pseudo_spherical_grid_when_valid() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let layers = vec![
        LayerInput {
            optical_depth: 0.1,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.2,
            ..LayerInput::default()
        },
    ];
    let grid = PseudoSphericalGrid {
        samples: vec![
            PseudoSphericalSample {
                altitude_km: 1.0,
                thickness_km: 1.0,
                optical_depth: 0.05,
            },
            PseudoSphericalSample {
                altitude_km: 3.0,
                thickness_km: 1.0,
                optical_depth: 0.07,
            },
        ],
        level_sample_starts: vec![0, 1, 2],
        level_altitudes_km: vec![0.5, 2.5, 3.5],
    };

    let dynamic = attenuation::fill_attenuation_dynamic_with_grid(&layers, &grid, &geometry, true);
    assert_close(dynamic.get(0, 2, 2), 1.0);
    assert!(dynamic.get(0, 2, 0) < 1.0);
    assert!(dynamic.get(0, 2, 0) > 0.0);
}

#[test]
fn labos_tangent_attenuation_tracks_optical_depth_jacobian() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let mut layer0 = LayerInput {
        optical_depth: 0.1,
        ..LayerInput::default()
    };
    let mut layer1 = LayerInput {
        optical_depth: 0.2,
        ..LayerInput::default()
    };
    jacobian::set(
        &mut layer0.optical_depth_jacobian,
        State::AerosolOpticalDepth,
        0.01,
    );
    jacobian::set(
        &mut layer1.optical_depth_jacobian,
        State::AerosolOpticalDepth,
        0.02,
    );
    let layers = vec![layer0, layer1];
    let u = geometry.u[0];

    let tangent = attenuation::fill_attenuation_tangent_dynamic(
        &layers,
        State::AerosolOpticalDepth,
        &geometry,
    );
    let base = (-(0.1 + 0.2) / u).exp();
    assert_close(tangent.get(0, 0, 2), base * (-(0.01 + 0.02) / u));
    assert_close(tangent.get(0, 2, 0), tangent.get(0, 0, 2));
}

#[test]
fn labos_geometry_adds_view_and_solar_extra_ordinates() {
    let geometry = Geometry::init(5, 0.8, 0.6).unwrap();

    assert_eq!(geometry.n_gauss, 5);
    assert_eq!(geometry.nmutot, 7);
    assert_eq!(geometry.view_idx(), 5);
    assert_close(geometry.u[5], 0.6);
    assert_close(geometry.u[6], 0.8);
    assert_close(geometry.w[5], 1.0);
    assert_close(geometry.w[6], 1.0);
    assert!(geometry.ug[0] > 0.0);
    assert!(geometry.ug[4] < 1.0);
    assert_close(geometry.wg.iter().take(5).sum::<f64>(), 1.0);
}

#[test]
fn labos_geometry_precomputes_same_and_different_mu_denominators() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let n = geometry.nmutot;

    let same_idx = n + 1;
    assert!(geometry.dmu_same[same_idx]);
    assert_close(
        geometry.dmu_plus[same_idx],
        0.25 / (geometry.u[1] + geometry.u[1]),
    );
    assert_close(
        geometry.dmu_min[same_idx],
        0.25 / (geometry.u[1] * geometry.u[1]),
    );

    let cross_idx = n;
    assert!(!geometry.dmu_same[cross_idx]);
    assert_close(
        geometry.dmu_min[cross_idx],
        0.25 / (geometry.u[1] - geometry.u[0]),
    );
}

#[test]
fn labos_fourier_plm_basis_starts_with_weighted_ordinates() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();

    let zero_fourier = FourierPlmBasis::init(0, 2, &geometry);
    for imu in 0..geometry.nmutot {
        assert_close(zero_fourier.plus[0][imu], geometry.w[imu]);
        assert_close(zero_fourier.minus[0][imu], geometry.w[imu]);
    }

    let first_fourier = FourierPlmBasis::init(1, 1, &geometry);
    for imu in 0..geometry.nmutot {
        let expected = (1.0 - geometry.u[imu] * geometry.u[imu]).max(0.0).sqrt() / 2.0_f64.sqrt()
            * geometry.w[imu];
        assert_close(first_fourier.plus[1][imu], expected);
        assert_close(first_fourier.minus[1][imu], expected);
    }
}

#[test]
fn labos_phase_kernel_zero_fourier_is_weight_outer_product() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let coefficients = phase_functions::zero_phase_coefficients();
    let basis = FourierPlmBasis::init(0, 0, &geometry);

    let kernel = fill_zplus_zmin_from_basis_limited(0, &coefficients, 0, &geometry, &basis);
    for i in 0..geometry.nmutot {
        for j in 0..geometry.nmutot {
            let expected = geometry.w[i] * geometry.w[j];
            assert_close(kernel.zplus.get(i, j), expected);
            assert_close(kernel.zmin.get(i, j), expected);
        }
    }
}

#[test]
fn labos_phase_kernel_row_matches_full_kernel_row() {
    let geometry = Geometry::init(3, 0.8, 0.6).unwrap();
    let mut coefficients = phase_functions::zero_phase_coefficients();
    coefficients[1] = 0.4;
    coefficients[2] = 0.15;
    let basis = FourierPlmBasis::init(0, 2, &geometry);
    let row_index = 2;

    let kernel = fill_zplus_zmin_from_basis_limited(0, &coefficients, 2, &geometry, &basis);
    let row =
        fill_zplus_zmin_row_from_basis_limited(0, &coefficients, 2, &geometry, &basis, row_index);

    assert_eq!(row.n, geometry.nmutot);
    for j in 0..geometry.nmutot {
        assert_close(row.zplus[j], kernel.zplus.get(row_index, j));
        assert_close(row.zmin[j], kernel.zmin.get(row_index, j));
    }
}

#[test]
fn labos_phase_kernel_can_extend_past_cached_basis() {
    let geometry = Geometry::init(3, 0.8, 0.6).unwrap();
    let mut coefficients = phase_functions::zero_phase_coefficients();
    coefficients[1] = 0.2;
    coefficients[2] = 0.1;

    let partial_basis = FourierPlmBasis::init(0, 1, &geometry);
    let partial_kernel =
        fill_zplus_zmin_from_basis_limited(0, &coefficients, 2, &geometry, &partial_basis);
    let full_kernel = fill_zplus_zmin(0, &coefficients, &geometry);

    for i in 0..geometry.nmutot {
        for j in 0..geometry.nmutot {
            assert_close(partial_kernel.zplus.get(i, j), full_kernel.zplus.get(i, j));
            assert_close(partial_kernel.zmin.get(i, j), full_kernel.zmin.get(i, j));
        }
    }
}

#[test]
fn labos_phase_kernel_is_zero_when_fourier_order_exceeds_phase_terms() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let coefficients = phase_functions::zero_phase_coefficients();
    let basis = FourierPlmBasis::init(3, 0, &geometry);

    let kernel = fill_zplus_zmin_from_basis_limited(3, &coefficients, 0, &geometry, &basis);
    let row = fill_zplus_zmin_row_from_basis_limited(3, &coefficients, 0, &geometry, &basis, 0);

    assert!(
        kernel.zplus.data[..geometry.nmutot * geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
    assert!(
        kernel.zmin.data[..geometry.nmutot * geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
    assert!(
        row.zplus[..geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
    assert!(
        row.zmin[..geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
}
