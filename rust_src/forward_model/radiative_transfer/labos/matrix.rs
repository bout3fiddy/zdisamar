use super::types::{MAX_EXTRA, MAX_GAUSS, Mat, Vec};

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

pub fn smul_known_traces(
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    trace_a: f64,
    trace_b: f64,
    a: &Mat,
    b: &Mat,
) -> Mat {
    smul_known_traces_if_nonzero(n, n_gauss, threshold_mul, trace_a, trace_b, a, b)
        .unwrap_or_else(|| Mat::zero(n))
}

pub fn smul_known_traces_if_nonzero(
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    trace_a: f64,
    trace_b: f64,
    a: &Mat,
    b: &Mat,
) -> Option<Mat> {
    if (trace_a * trace_b).abs() <= threshold_mul {
        return None;
    }
    Some(smul_nonzero_product(n, n_gauss, a, b))
}

pub fn esmul(n: usize, e: &Vec, a: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let mut idx = j;
        for i in 0..n {
            result.data[idx] = e.data[i] * a.data[idx];
            idx += n;
        }
    }
    result
}

pub fn semul(n: usize, a: &Mat, e: &Vec) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        let mut idx = j;
        for _ in 0..n {
            result.data[idx] = a.data[idx] * ej;
            idx += n;
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

pub fn mat_add_semul3(n: usize, a: &Mat, b: &Mat, e: &Vec, c: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        let mut idx = j;
        for _ in 0..n {
            result.data[idx] = (a.data[idx] + b.data[idx] * ej) + c.data[idx];
            idx += n;
        }
    }
    result
}

pub fn smul_add_semul3(
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: &Mat,
    e: &Vec,
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
    e: &Vec,
    c: &Mat,
    trace_c: f64,
) -> Mat {
    let trace_a = trace_gauss(n, n_gauss, a);
    if let Some(product) =
        smul_known_traces_if_nonzero(n, n_gauss, threshold_mul, trace_a, trace_c, a, c)
    {
        return mat_add_semul3(n, c, a, e, &product);
    }
    semul_add(n, a, e, c)
}

pub fn mat_add_esmul3(n: usize, a: &Mat, e: &Vec, b: &Mat, c: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let mut idx = j;
        for i in 0..n {
            result.data[idx] = (a.data[idx] + e.data[i] * b.data[idx]) + c.data[idx];
            idx += n;
        }
    }
    result
}

pub fn mat_add_esmul(n: usize, a: &Mat, e: &Vec, b: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let mut idx = j;
        for i in 0..n {
            result.data[idx] = a.data[idx] + e.data[i] * b.data[idx];
            idx += n;
        }
    }
    result
}

pub fn semul_add(n: usize, a: &Mat, e: &Vec, b: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        let mut idx = j;
        for _ in 0..n {
            result.data[idx] = a.data[idx] * ej + b.data[idx];
            idx += n;
        }
    }
    result
}

pub fn esmul_semul(n: usize, e: &Vec, a: &Mat, b: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        let mut idx = j;
        for i in 0..n {
            result.data[idx] = e.data[i] * a.data[idx] + b.data[idx] * ej;
            idx += n;
        }
    }
    result
}

pub fn esmul_semul_add(n: usize, e: &Vec, a: &Mat, b: &Mat, c: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        let mut idx = j;
        for i in 0..n {
            result.data[idx] = (e.data[i] * a.data[idx] + b.data[idx] * ej) + c.data[idx];
            idx += n;
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

    let Some(inverse) = invert_gauss_block(&mut one_minus_ab_gg, n_gauss) else {
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
            let mut sum = 0.0;
            for k in 0..n_gauss {
                sum += inverse[i * n_gauss + k] * ab.data[k * n + j];
            }
            result.data[i * n + j] = sum;
        }
    }

    let mut tmp = [0.0; MAX_EXTRA * MAX_GAUSS];
    for ia in 0..n_extra {
        for j in 0..n_gauss {
            let mut sum = 0.0;
            for k in 0..n_gauss {
                sum += ab.data[(n_gauss + ia) * n + k] * inverse[k * n_gauss + j];
            }
            tmp[ia * n_gauss + j] = sum;
            result.data[(n_gauss + ia) * n + j] = sum;
        }
    }

    for ia in 0..n_extra {
        let i = n_gauss + ia;
        for ja in 0..n_extra {
            let j = n_gauss + ja;
            let mut sum = 0.0;
            for k in 0..n_gauss {
                sum += tmp[ia * n_gauss + k] * ab.data[k * n + j];
            }
            result.data[i * n + j] = sum + ab.data[i * n + j];
        }
    }

    result
}

fn invert_gauss_block(
    block: &mut [f64; MAX_GAUSS * MAX_GAUSS],
    n_gauss: usize,
) -> Option<[f64; MAX_GAUSS * MAX_GAUSS]> {
    let mut pivot = [0usize; MAX_GAUSS];
    let mut pivot_offset = [0usize; MAX_GAUSS];
    let mut inverse_diag = [0.0; MAX_GAUSS];
    for i in 0..n_gauss {
        pivot[i] = i;
        pivot_offset[i] = i * n_gauss;
    }

    // Pivoted LU is small enough to stay stack-local,
    // which matters because doubling calls this many times per RT layer.
    for col in 0..n_gauss {
        let mut max_val = block[pivot_offset[col] + col].abs();
        let mut max_row = col;
        for row in col + 1..n_gauss {
            let value = block[pivot_offset[row] + col].abs();
            if value > max_val {
                max_val = value;
                max_row = row;
            }
        }
        if max_row != col {
            pivot.swap(col, max_row);
            pivot_offset.swap(col, max_row);
        }
        let diag = block[pivot_offset[col] + col];
        if diag.abs() < 1.0e-30 {
            return None;
        }
        let inv_diag = 1.0 / diag;
        inverse_diag[col] = inv_diag;
        for row in col + 1..n_gauss {
            let row_offset = pivot_offset[row];
            let col_offset = pivot_offset[col];
            let factor = block[row_offset + col] * inv_diag;
            block[row_offset + col] = factor;
            for k in col + 1..n_gauss {
                block[row_offset + k] -= factor * block[col_offset + k];
            }
        }
    }

    let mut inverse = [0.0; MAX_GAUSS * MAX_GAUSS];
    for rhs_col in 0..n_gauss {
        let mut y = [0.0; MAX_GAUSS];
        for i in 0..n_gauss {
            let mut sum = if pivot[i] == rhs_col { 1.0 } else { 0.0 };
            let row_offset = pivot_offset[i];
            for j in 0..i {
                sum -= block[row_offset + j] * y[j];
            }
            y[i] = sum;
        }

        let mut x = [0.0; MAX_GAUSS];
        let mut ii = n_gauss;
        while ii > 0 {
            ii -= 1;
            let mut sum = y[ii];
            let row_offset = pivot_offset[ii];
            for j in ii + 1..n_gauss {
                sum -= block[row_offset + j] * x[j];
            }
            x[ii] = sum * inverse_diag[ii];
        }
        for i in 0..n_gauss {
            inverse[i * n_gauss + rhs_col] = x[i];
        }
    }
    Some(inverse)
}

fn smul_nonzero_product(n: usize, n_gauss: usize, a: &Mat, b: &Mat) -> Mat {
    let mut result = Mat::zero(n);
    for j in 0..n {
        for k in 0..n_gauss {
            let bkj = b.data[k * n + j];
            let mut idx = j;
            let mut a_idx = k;
            for _ in 0..n {
                result.data[idx] += a.data[a_idx] * bkj;
                idx += n;
                a_idx += n;
            }
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
