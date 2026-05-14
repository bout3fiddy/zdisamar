use super::types::{MAX_EXTRA, MAX_GAUSS, Mat, Vec as LabosVec};

const THRESHOLD_Q: f64 = 1.0e-3;

pub fn smul(n: usize, n_gauss: usize, threshold_mul: f64, a: &Mat, b: &Mat) -> Mat {
    let trace_a = trace_gauss(n, n_gauss, a);
    let trace_b = trace_gauss(n, n_gauss, b);
    if (trace_a * trace_b).abs() <= threshold_mul {
        return Mat::zero(n);
    }
    smul_nonzero_product(n, n_gauss, a, b)
}

pub fn smul_into(out: &mut Mat, n: usize, n_gauss: usize, threshold_mul: f64, a: &Mat, b: &Mat) {
    *out = smul(n, n_gauss, threshold_mul, a, b);
}

#[allow(clippy::too_many_arguments)]
pub fn smul_into_known_traces(
    out: &mut Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    trace_a: f64,
    trace_b: f64,
    a: &Mat,
    b: &Mat,
) {
    if smul_into_known_traces_if_nonzero(out, n, n_gauss, threshold_mul, trace_a, trace_b, a, b) {
        return;
    }
    *out = Mat::zero(n);
}

#[allow(clippy::too_many_arguments)]
pub fn smul_into_known_traces_if_nonzero(
    out: &mut Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    trace_a: f64,
    trace_b: f64,
    a: &Mat,
    b: &Mat,
) -> bool {
    if (trace_a * trace_b).abs() <= threshold_mul {
        return false;
    }
    *out = smul_nonzero_product(n, n_gauss, a, b);
    true
}

pub fn esmul(n: usize, e: &LabosVec, a: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        for i in 0..n {
            let idx = i * n + j;
            result.data[idx] = e.data[i] * a.data[idx];
        }
    }
    result
}

pub fn semul(n: usize, a: &Mat, e: &LabosVec) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        for i in 0..n {
            let idx = i * n + j;
            result.data[idx] = a.data[idx] * ej;
        }
    }
    result
}

pub fn mat_add(n: usize, a: &Mat, b: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for idx in 0..n * n {
        result.data[idx] = a.data[idx] + b.data[idx];
    }
    result
}

pub fn mat_add_semul3(n: usize, a: &Mat, b: &Mat, e: &LabosVec, c: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        for i in 0..n {
            let idx = i * n + j;
            result.data[idx] = (a.data[idx] + b.data[idx] * ej) + c.data[idx];
        }
    }
    result
}

pub fn smul_add_semul3(
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: &Mat,
    e: &LabosVec,
    c: &Mat,
) -> Mat {
    let product = smul(n, n_gauss, threshold_mul, a, c);
    mat_add_semul3(n, c, a, e, &product)
}

pub fn smul_add_semul3_known_right_trace(
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: &Mat,
    e: &LabosVec,
    c: &Mat,
    trace_c: f64,
) -> Mat {
    let trace_a = trace_gauss(n, n_gauss, a);
    let mut product = Mat::zero(n);
    if smul_into_known_traces_if_nonzero(
        &mut product,
        n,
        n_gauss,
        threshold_mul,
        trace_a,
        trace_c,
        a,
        c,
    ) {
        return mat_add_semul3(n, c, a, e, &product);
    }
    semul_add(n, a, e, c)
}

pub fn mat_add_esmul3(n: usize, a: &Mat, e: &LabosVec, b: &Mat, c: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        for i in 0..n {
            let idx = i * n + j;
            result.data[idx] = (a.data[idx] + e.data[i] * b.data[idx]) + c.data[idx];
        }
    }
    result
}

pub fn mat_add_esmul(n: usize, a: &Mat, e: &LabosVec, b: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        for i in 0..n {
            let idx = i * n + j;
            result.data[idx] = a.data[idx] + e.data[i] * b.data[idx];
        }
    }
    result
}

pub fn semul_add(n: usize, a: &Mat, e: &LabosVec, b: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        for i in 0..n {
            let idx = i * n + j;
            result.data[idx] = a.data[idx] * ej + b.data[idx];
        }
    }
    result
}

pub fn esmul_semul(n: usize, e: &LabosVec, a: &Mat, b: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        for i in 0..n {
            let idx = i * n + j;
            result.data[idx] = e.data[i] * a.data[idx] + b.data[idx] * ej;
        }
    }
    result
}

pub fn esmul_semul_add(n: usize, e: &LabosVec, a: &Mat, b: &Mat, c: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        for i in 0..n {
            let idx = i * n + j;
            result.data[idx] = (e.data[i] * a.data[idx] + b.data[idx] * ej) + c.data[idx];
        }
    }
    result
}

pub fn qseries(n: usize, n_gauss: usize, threshold_mul: f64, a: &Mat, b: &Mat) -> Mat {
    let ab = smul(n, n_gauss, threshold_mul, a, b);
    qseries_from_product(n, n_gauss, &ab)
}

pub fn qseries_known_nonzero_product(n: usize, n_gauss: usize, a: &Mat, b: &Mat) -> Mat {
    let ab = smul_nonzero_product(n, n_gauss, a, b);
    qseries_from_product(n, n_gauss, &ab)
}

fn qseries_from_product(n: usize, n_gauss: usize, ab: &Mat) -> Mat {
    let trace_ab = trace_gauss(n, n_gauss, ab);
    if trace_ab.abs() < THRESHOLD_Q {
        return *ab;
    }

    let n_extra = n - n_gauss;
    let mut one_minus_ab_gg = [0.0; MAX_GAUSS * MAX_GAUSS];
    for i in 0..n_gauss {
        for j in 0..n_gauss {
            let delta = if i == j { 1.0 } else { 0.0 };
            one_minus_ab_gg[i * n_gauss + j] = delta - ab.data[i * n + j];
        }
    }

    let Some(inverse) = invert_gauss_block(n_gauss, &mut one_minus_ab_gg) else {
        return *ab;
    };

    let mut result = Mat::zero(n);
    for i in 0..n_gauss {
        for j in 0..n_gauss {
            let delta = if i == j { 1.0 } else { 0.0 };
            result.data[i * n + j] = inverse[i * n_gauss + j] - delta;
        }
    }

    for ja in 0..n_extra {
        let j = n_gauss + ja;
        for i in 0..n_gauss {
            let mut s = 0.0;
            for k in 0..n_gauss {
                s += inverse[i * n_gauss + k] * ab.data[k * n + j];
            }
            result.data[i * n + j] = s;
        }
    }

    let mut tmp = [0.0; MAX_EXTRA * MAX_GAUSS];
    for ia in 0..n_extra {
        for j in 0..n_gauss {
            let mut s = 0.0;
            for k in 0..n_gauss {
                s += ab.data[(n_gauss + ia) * n + k] * inverse[k * n_gauss + j];
            }
            tmp[ia * n_gauss + j] = s;
            result.data[(n_gauss + ia) * n + j] = s;
        }
    }

    for ia in 0..n_extra {
        let i = n_gauss + ia;
        for ja in 0..n_extra {
            let j = n_gauss + ja;
            let mut s = 0.0;
            for k in 0..n_gauss {
                s += tmp[ia * n_gauss + k] * ab.data[k * n + j];
            }
            result.data[i * n + j] = s + ab.data[i * n + j];
        }
    }

    result
}

fn invert_gauss_block(
    n_gauss: usize,
    one_minus_ab_gg: &mut [f64; MAX_GAUSS * MAX_GAUSS],
) -> Option<[f64; MAX_GAUSS * MAX_GAUSS]> {
    let mut pivot = [0usize; MAX_GAUSS];
    let mut pivot_offset = [0usize; MAX_GAUSS];
    let mut inverse_diag = [0.0; MAX_GAUSS];
    for i in 0..n_gauss {
        pivot[i] = i;
        pivot_offset[i] = i * n_gauss;
    }

    for col in 0..n_gauss {
        let mut max_val = one_minus_ab_gg[pivot_offset[col] + col].abs();
        let mut max_row = col;
        for row in col + 1..n_gauss {
            let val = one_minus_ab_gg[pivot_offset[row] + col].abs();
            if val > max_val {
                max_val = val;
                max_row = row;
            }
        }
        if max_row != col {
            pivot.swap(col, max_row);
            pivot_offset.swap(col, max_row);
        }
        let diag = one_minus_ab_gg[pivot_offset[col] + col];
        if diag.abs() < 1.0e-30 {
            return None;
        }
        let inv_diag = 1.0 / diag;
        inverse_diag[col] = inv_diag;
        for row in col + 1..n_gauss {
            let row_offset = pivot_offset[row];
            let col_offset = pivot_offset[col];
            let factor = one_minus_ab_gg[row_offset + col] * inv_diag;
            one_minus_ab_gg[row_offset + col] = factor;
            for k in col + 1..n_gauss {
                one_minus_ab_gg[row_offset + k] -= factor * one_minus_ab_gg[col_offset + k];
            }
        }
    }

    let mut inverse = [0.0; MAX_GAUSS * MAX_GAUSS];
    for rhs_col in 0..n_gauss {
        let mut y = [0.0; MAX_GAUSS];
        for i in 0..n_gauss {
            let mut s = if pivot[i] == rhs_col { 1.0 } else { 0.0 };
            let row_offset = pivot_offset[i];
            for j in 0..i {
                s -= one_minus_ab_gg[row_offset + j] * y[j];
            }
            y[i] = s;
        }

        let mut x = [0.0; MAX_GAUSS];
        for ii in (0..n_gauss).rev() {
            let mut s = y[ii];
            let row_offset = pivot_offset[ii];
            for j in ii + 1..n_gauss {
                s -= one_minus_ab_gg[row_offset + j] * x[j];
            }
            x[ii] = s * inverse_diag[ii];
        }
        for i in 0..n_gauss {
            inverse[i * n_gauss + rhs_col] = x[i];
        }
    }
    Some(inverse)
}

fn smul_nonzero_product(n: usize, n_gauss: usize, a: &Mat, b: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    // Zig has a 12x10 SIMD fast path. This loop keeps the exact truncated Gauss-column product first;
    // the specialization can be restored once full parity is in place.
    for j in 0..n {
        for i in 0..n {
            let mut value = 0.0;
            for k in 0..n_gauss {
                value += a.data[i * n + k] * b.data[k * n + j];
            }
            result.data[i * n + j] = value;
        }
    }
    result
}

fn trace_gauss(n: usize, n_gauss: usize, matrix: &Mat) -> f64 {
    let mut trace = 0.0;
    for k in 0..n_gauss {
        trace += matrix.data[k * n + k];
    }
    trace
}
