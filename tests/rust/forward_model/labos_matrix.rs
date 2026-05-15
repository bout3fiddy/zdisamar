use zdisamar::forward_model::radiative_transfer::labos::{
    Mat, Vec as LabosVec, esmul, mat_add, qseries, semul, smul, smul_known_traces_if_nonzero,
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

fn matrix_from_fn(n: usize, mut value_at: impl FnMut(usize, usize) -> f64) -> Mat {
    let mut matrix = Mat::zero(n);
    for i in 0..n {
        for j in 0..n {
            matrix.set(i, j, value_at(i, j));
        }
    }
    matrix
}

#[test]
fn smul_uses_gauss_block_columns_and_honors_trace_threshold() {
    let n = 3;
    let a = matrix_from_fn(n, |i, j| 1.0 + (i * 3 + j) as f64);
    let b = matrix_from_fn(n, |i, j| 0.5 + (i + j * 2) as f64);

    let product = smul(n, 2, 0.0, &a, &b);
    for i in 0..n {
        for j in 0..n {
            let expected = a.get(i, 0) * b.get(0, j) + a.get(i, 1) * b.get(1, j);
            assert_close(product.get(i, j), expected, 1.0e-12);
        }
    }

    let skipped = smul(n, 2, f64::MAX, &a, &b);
    for value in skipped.data[..n * n].iter() {
        assert_close(*value, 0.0, 0.0);
    }
}

#[test]
fn known_trace_multiply_reports_when_product_is_skipped() {
    let n = 3;
    let a = Mat::identity(n);
    let b = Mat::identity(n);
    assert!(smul_known_traces_if_nonzero(n, 2, 10.0, 1.0, 1.0, &a, &b).is_none());

    let out = smul_known_traces_if_nonzero(n, 2, 0.0, 1.0, 1.0, &a, &b).unwrap();
    assert_close(out.get(0, 0), 1.0, 0.0);
    assert_close(out.get(2, 2), 0.0, 0.0);
}

#[test]
fn row_and_column_scaling_helpers_match_labos_layout() {
    let n = 3;
    let matrix = matrix_from_fn(n, |i, j| 1.0 + (i * n + j) as f64);
    let mut scale = LabosVec::zero(n);
    scale.set(0, 2.0);
    scale.set(1, 3.0);
    scale.set(2, 4.0);

    let row_scaled = esmul(n, &scale, &matrix);
    let column_scaled = semul(n, &matrix, &scale);
    let added = mat_add(n, &row_scaled, &column_scaled);

    for i in 0..n {
        for j in 0..n {
            assert_close(row_scaled.get(i, j), scale.get(i) * matrix.get(i, j), 0.0);
            assert_close(
                column_scaled.get(i, j),
                matrix.get(i, j) * scale.get(j),
                0.0,
            );
            assert_close(
                added.get(i, j),
                (scale.get(i) + scale.get(j)) * matrix.get(i, j),
                0.0,
            );
        }
    }
}

#[test]
fn qseries_solves_gauss_block_closure_for_small_diagonal_product() {
    let n = 4;
    let a = Mat::identity(n);
    let mut b = Mat::zero(n);
    b.set(0, 0, 0.2);
    b.set(1, 1, 0.1);

    let q = qseries(n, 2, 0.0, &a, &b);
    assert_close(q.get(0, 0), 0.2 / 0.8, 1.0e-12);
    assert_close(q.get(1, 1), 0.1 / 0.9, 1.0e-12);
    assert_close(q.get(0, 1), 0.0, 1.0e-12);
    assert_close(q.get(2, 2), 0.0, 1.0e-12);
}
