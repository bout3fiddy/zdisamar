const types = @import("types.zig");

const Mat = types.Mat;
const Vec = types.Vec;

const threshold_q: f64 = 1.0e-3;

pub fn smul(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    var result = Mat.zero(n);
    var tra: f64 = 0.0;
    var trb: f64 = 0.0;
    for (0..n_gauss) |k| {
        tra += a.get(k, k);
        trb += b.get(k, k);
    }
    if (@abs(tra * trb) <= threshold_mul) return result;

    for (0..n) |j| {
        for (0..n_gauss) |k| {
            const bkj = b.get(k, j);
            for (0..n) |i| result.addTo(i, j, a.get(i, k) * bkj);
        }
    }
    return result;
}

pub fn esmul(n: usize, e: *const Vec, a: *const Mat) Mat {
    var result = Mat.zero(n);
    for (0..n) |j| {
        for (0..n) |i| result.set(i, j, e.get(i) * a.get(i, j));
    }
    return result;
}

pub fn semul(n: usize, a: *const Mat, e: *const Vec) Mat {
    var result = Mat.zero(n);
    for (0..n) |j| {
        const ej = e.get(j);
        for (0..n) |i| result.set(i, j, a.get(i, j) * ej);
    }
    return result;
}

pub fn matAdd(n: usize, a: *const Mat, b: *const Mat) Mat {
    var result = Mat.zero(n);
    for (0..n * n) |idx| result.data[idx] = a.data[idx] + b.data[idx];
    return result;
}

pub fn qseries(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    const ab = smul(n, n_gauss, threshold_mul, a, b);

    var trab: f64 = 0.0;
    for (0..n_gauss) |k| trab += ab.get(k, k);
    if (@abs(trab) < threshold_q) return ab;

    const n_extra = n - n_gauss;

    var one_minus_ab_gg: [types.max_gauss * types.max_gauss]f64 = undefined;
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            one_minus_ab_gg[i * n_gauss + j] = delta - ab.get(i, j);
        }
    }

    var pivot: [types.max_gauss]usize = undefined;
    for (0..n_gauss) |i| pivot[i] = i;

    for (0..n_gauss) |col| {
        var max_val: f64 = @abs(one_minus_ab_gg[pivot[col] * n_gauss + col]);
        var max_row: usize = col;
        for (col + 1..n_gauss) |row| {
            const val = @abs(one_minus_ab_gg[pivot[row] * n_gauss + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }
        if (max_row != col) {
            const tmp = pivot[col];
            pivot[col] = pivot[max_row];
            pivot[max_row] = tmp;
        }
        const diag = one_minus_ab_gg[pivot[col] * n_gauss + col];
        if (@abs(diag) < 1.0e-30) return ab;
        for (col + 1..n_gauss) |row| {
            const factor = one_minus_ab_gg[pivot[row] * n_gauss + col] / diag;
            one_minus_ab_gg[pivot[row] * n_gauss + col] = factor;
            for (col + 1..n_gauss) |k| {
                one_minus_ab_gg[pivot[row] * n_gauss + k] -=
                    factor * one_minus_ab_gg[pivot[col] * n_gauss + k];
            }
        }
    }

    var inverse: [types.max_gauss * types.max_gauss]f64 = .{0.0} ** (types.max_gauss * types.max_gauss);
    for (0..n_gauss) |rhs_col| {
        var y: [types.max_gauss]f64 = .{0.0} ** types.max_gauss;
        for (0..n_gauss) |i| {
            var s: f64 = if (pivot[i] == rhs_col) 1.0 else 0.0;
            for (0..i) |j| s -= one_minus_ab_gg[pivot[i] * n_gauss + j] * y[j];
            y[i] = s;
        }

        var x: [types.max_gauss]f64 = .{0.0} ** types.max_gauss;
        var ii: usize = n_gauss;
        while (ii > 0) {
            ii -= 1;
            var s: f64 = y[ii];
            for (ii + 1..n_gauss) |j| s -= one_minus_ab_gg[pivot[ii] * n_gauss + j] * x[j];
            x[ii] = s / one_minus_ab_gg[pivot[ii] * n_gauss + ii];
        }
        for (0..n_gauss) |i| inverse[i * n_gauss + rhs_col] = x[i];
    }

    var result = Mat.zero(n);
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            result.set(i, j, inverse[i * n_gauss + j] - delta);
        }
    }

    for (0..n_extra) |ja| {
        for (0..n_gauss) |i| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| s += inverse[i * n_gauss + k] * ab.get(k, n_gauss + ja);
            result.set(i, n_gauss + ja, s);
        }
    }

    var tmp: [types.max_extra * types.max_gauss]f64 = .{0.0} ** (types.max_extra * types.max_gauss);
    for (0..n_extra) |ia| {
        for (0..n_gauss) |j| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| s += ab.get(n_gauss + ia, k) * inverse[k * n_gauss + j];
            tmp[ia * n_gauss + j] = s;
            result.set(n_gauss + ia, j, s);
        }
    }

    for (0..n_extra) |ia| {
        for (0..n_extra) |ja| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| s += tmp[ia * n_gauss + k] * ab.get(k, n_gauss + ja);
            result.set(n_gauss + ia, n_gauss + ja, s + ab.get(n_gauss + ia, n_gauss + ja));
        }
    }

    return result;
}
