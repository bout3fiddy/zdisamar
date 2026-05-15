use zdisamar::forward_model::radiative_transfer::labos::{
    Geometry, MAX_EXTRA, MAX_N2, MAX_NMUTOT, Mat, Vec as LabosVec, Vec2,
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

#[test]
fn fixed_size_matrix_and_vector_helpers_match_zig_layout() {
    let mut matrix = Mat::identity(3);
    assert_eq!(matrix.n, 3);
    assert_eq!(matrix.data.len(), MAX_N2);
    assert_close(matrix.get(1, 1), 1.0, 0.0);
    matrix.set(1, 2, 4.5);
    assert_close(matrix.get(1, 2), 4.5, 0.0);

    let mut vector = LabosVec::zero(5);
    assert_eq!(vector.n, 5);
    assert_eq!(vector.data.len(), MAX_NMUTOT);
    vector.set(4, 0.25);
    assert_close(vector.get(4), 0.25, 0.0);

    let mut vectors = Vec2::zero(5);
    vectors.col[1].set(2, 0.75);
    assert_close(vectors.col[1].get(2), 0.75, 0.0);
}

#[test]
fn geometry_appends_view_and_solar_directions_after_gauss_streams() {
    let geometry = Geometry::init(4, 0.58, 0.64);

    assert_eq!(geometry.n_gauss, 4);
    assert_eq!(geometry.nmutot, 4 + MAX_EXTRA);
    assert_eq!(geometry.view_idx(), 4);
    assert_close(geometry.u[4], 0.64, 0.0);
    assert_close(geometry.u[5], 0.58, 0.0);
    assert_close(geometry.w[4], 1.0, 0.0);
    assert_close(geometry.w[5], 1.0, 0.0);
    assert_close(geometry.wg[..4].iter().sum::<f64>(), 1.0, 1.0e-12);

    for index in 0..geometry.n_gauss {
        assert_close(
            geometry.w[index] * geometry.w[index],
            2.0 * geometry.ug[index] * geometry.wg[index],
            1.0e-12,
        );
    }
}

#[test]
fn geometry_precomputes_same_and_distinct_mu_denominators() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let stride = geometry.nmutot;

    assert!(geometry.dmu_same[0]);
    assert_close(
        geometry.dmu_min[0],
        0.25 / (geometry.u[0] * geometry.u[0]),
        1.0e-12,
    );

    let distinct_idx = stride;
    assert!(!geometry.dmu_same[distinct_idx]);
    assert_close(
        geometry.dmu_plus[distinct_idx],
        0.25 / (geometry.u[1] + geometry.u[0]),
        1.0e-12,
    );
    assert_close(
        geometry.dmu_min[distinct_idx],
        0.25 / (geometry.u[1] - geometry.u[0]),
        1.0e-12,
    );
}
