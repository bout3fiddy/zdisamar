use zdisamar::forward_model::radiative_transfer::labos::{
    Geometry, MAX_EXTRA, MAX_GAUSS, MAX_N2, MAX_NMUTOT, Mat, Vec as LabosVec, Vec2, matrix,
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
