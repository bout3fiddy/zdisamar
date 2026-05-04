const types = @import("types.zig");

const Mat = types.Mat;
const Vec = types.Vec;

const threshold_q: f64 = 1.0e-3;

pub fn smul(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    if (n == 12 and n_gauss == 10) {
        var tra = a.data[0];
        tra += a.data[13];
        tra += a.data[26];
        tra += a.data[39];
        tra += a.data[52];
        tra += a.data[65];
        tra += a.data[78];
        tra += a.data[91];
        tra += a.data[104];
        tra += a.data[117];
        var trb = b.data[0];
        trb += b.data[13];
        trb += b.data[26];
        trb += b.data[39];
        trb += b.data[52];
        trb += b.data[65];
        trb += b.data[78];
        trb += b.data[91];
        trb += b.data[104];
        trb += b.data[117];
        if (@abs(tra * trb) <= threshold_mul) return Mat.zero(n);
        return smul12x10(a, b);
    }

    var tra: f64 = 0.0;
    var trb: f64 = 0.0;
    for (0..n_gauss) |k| {
        const idx = k * n + k;
        tra += a.data[idx];
        trb += b.data[idx];
    }
    if (@abs(tra * trb) <= threshold_mul) return Mat.zero(n);

    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        if (n_gauss == 0) break;
        const b0j = b.data[j];
        var idx = j;
        var a_idx: usize = 0;
        for (0..n) |_| {
            result.data[idx] = a.data[a_idx] * b0j;
            idx += n;
            a_idx += n;
        }
        for (1..n_gauss) |k| {
            const bkj = b.data[k * n + j];
            idx = j;
            a_idx = k;
            for (0..n) |_| {
                result.data[idx] += a.data[a_idx] * bkj;
                idx += n;
                a_idx += n;
            }
        }
    }
    return result;
}

fn smul12x10(a: *const Mat, b: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    for (0..12) |i| {
        const row = i * 12;
        const a0 = a.data[row];
        const a1 = a.data[row + 1];
        const a2 = a.data[row + 2];
        const a3 = a.data[row + 3];
        const a4 = a.data[row + 4];
        const a5 = a.data[row + 5];
        const a6 = a.data[row + 6];
        const a7 = a.data[row + 7];
        const a8 = a.data[row + 8];
        const a9 = a.data[row + 9];
        for (0..12) |j| {
            var s = a0 * b.data[j];
            s += a1 * b.data[12 + j];
            s += a2 * b.data[24 + j];
            s += a3 * b.data[36 + j];
            s += a4 * b.data[48 + j];
            s += a5 * b.data[60 + j];
            s += a6 * b.data[72 + j];
            s += a7 * b.data[84 + j];
            s += a8 * b.data[96 + j];
            s += a9 * b.data[108 + j];
            result.data[row + j] = s;
        }
    }
    return result;
}

pub fn esmul(n: usize, e: *const Vec, a: *const Mat) Mat {
    if (n == 12) return esmul12(e, a);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        var idx = j;
        for (0..n) |i| {
            result.data[idx] = e.data[i] * a.data[idx];
            idx += n;
        }
    }
    return result;
}

pub fn semul(n: usize, a: *const Mat, e: *const Vec) Mat {
    if (n == 12) return semul12(a, e);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |_| {
            result.data[idx] = a.data[idx] * ej;
            idx += n;
        }
    }
    return result;
}

pub fn matAdd(n: usize, a: *const Mat, b: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = n };
    for (0..n * n) |idx| result.data[idx] = a.data[idx] + b.data[idx];
    return result;
}

pub fn matAddSemul3(n: usize, a: *const Mat, b: *const Mat, e: *const Vec, c: *const Mat) Mat {
    if (n == 12) return matAddSemul3_12(a, b, e, c);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |_| {
            result.data[idx] = (a.data[idx] + b.data[idx] * ej) + c.data[idx];
            idx += n;
        }
    }
    return result;
}

pub fn matAddEsmul3(n: usize, a: *const Mat, e: *const Vec, b: *const Mat, c: *const Mat) Mat {
    if (n == 12) return matAddEsmul3_12(a, e, b, c);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        var idx = j;
        for (0..n) |i| {
            result.data[idx] = (a.data[idx] + e.data[i] * b.data[idx]) + c.data[idx];
            idx += n;
        }
    }
    return result;
}

pub fn semulAdd(n: usize, a: *const Mat, e: *const Vec, b: *const Mat) Mat {
    if (n == 12) return semulAdd12(a, e, b);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |_| {
            result.data[idx] = a.data[idx] * ej + b.data[idx];
            idx += n;
        }
    }
    return result;
}

pub fn esmulSemulAdd(n: usize, e: *const Vec, a: *const Mat, b: *const Mat, c: *const Mat) Mat {
    if (n == 12) return esmulSemulAdd12(e, a, b, c);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |i| {
            result.data[idx] = (e.data[i] * a.data[idx] + b.data[idx] * ej) + c.data[idx];
            idx += n;
        }
    }
    return result;
}

fn esmul12(e: *const Vec, a: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    for (0..12) |j| {
        var idx = j;
        for (0..12) |i| {
            result.data[idx] = e.data[i] * a.data[idx];
            idx += 12;
        }
    }
    return result;
}

fn semul12(a: *const Mat, e: *const Vec) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    for (0..12) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..12) |_| {
            result.data[idx] = a.data[idx] * ej;
            idx += 12;
        }
    }
    return result;
}

fn matAddSemul3_12(a: *const Mat, b: *const Mat, e: *const Vec, c: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    for (0..12) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..12) |_| {
            result.data[idx] = (a.data[idx] + b.data[idx] * ej) + c.data[idx];
            idx += 12;
        }
    }
    return result;
}

fn matAddEsmul3_12(a: *const Mat, e: *const Vec, b: *const Mat, c: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    for (0..12) |j| {
        var idx = j;
        for (0..12) |i| {
            result.data[idx] = (a.data[idx] + e.data[i] * b.data[idx]) + c.data[idx];
            idx += 12;
        }
    }
    return result;
}

fn semulAdd12(a: *const Mat, e: *const Vec, b: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    for (0..12) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..12) |_| {
            result.data[idx] = a.data[idx] * ej + b.data[idx];
            idx += 12;
        }
    }
    return result;
}

fn esmulSemulAdd12(e: *const Vec, a: *const Mat, b: *const Mat, c: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    for (0..12) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..12) |i| {
            result.data[idx] = (e.data[i] * a.data[idx] + b.data[idx] * ej) + c.data[idx];
            idx += 12;
        }
    }
    return result;
}

pub fn qseries(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    const ab = smul(n, n_gauss, threshold_mul, a, b);

    var trab: f64 = 0.0;
    for (0..n_gauss) |k| trab += ab.data[k * n + k];
    if (@abs(trab) < threshold_q) return ab;

    const n_extra = n - n_gauss;

    var one_minus_ab_gg: [types.max_gauss * types.max_gauss]f64 = undefined;
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            one_minus_ab_gg[i * n_gauss + j] = delta - ab.data[i * n + j];
        }
    }

    var pivot: [types.max_gauss]usize = undefined;
    var pivot_offset: [types.max_gauss]usize = undefined;
    for (0..n_gauss) |i| {
        pivot[i] = i;
        pivot_offset[i] = i * n_gauss;
    }

    for (0..n_gauss) |col| {
        var max_val: f64 = @abs(one_minus_ab_gg[pivot_offset[col] + col]);
        var max_row: usize = col;
        for (col + 1..n_gauss) |row| {
            const val = @abs(one_minus_ab_gg[pivot_offset[row] + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }
        if (max_row != col) {
            const tmp = pivot[col];
            pivot[col] = pivot[max_row];
            pivot[max_row] = tmp;
            const tmp_offset = pivot_offset[col];
            pivot_offset[col] = pivot_offset[max_row];
            pivot_offset[max_row] = tmp_offset;
        }
        const diag = one_minus_ab_gg[pivot_offset[col] + col];
        if (@abs(diag) < 1.0e-30) return ab;
        for (col + 1..n_gauss) |row| {
            const row_offset = pivot_offset[row];
            const col_offset = pivot_offset[col];
            const factor = one_minus_ab_gg[row_offset + col] / diag;
            one_minus_ab_gg[row_offset + col] = factor;
            for (col + 1..n_gauss) |k| {
                one_minus_ab_gg[row_offset + k] -=
                    factor * one_minus_ab_gg[col_offset + k];
            }
        }
    }

    var inverse: [types.max_gauss * types.max_gauss]f64 = undefined;
    for (0..n_gauss) |rhs_col| {
        var y: [types.max_gauss]f64 = undefined;
        for (0..n_gauss) |i| {
            var s: f64 = if (pivot[i] == rhs_col) 1.0 else 0.0;
            const row_offset = pivot_offset[i];
            for (0..i) |j| s -= one_minus_ab_gg[row_offset + j] * y[j];
            y[i] = s;
        }

        var x: [types.max_gauss]f64 = undefined;
        var ii: usize = n_gauss;
        while (ii > 0) {
            ii -= 1;
            var s: f64 = y[ii];
            const row_offset = pivot_offset[ii];
            for (ii + 1..n_gauss) |j| s -= one_minus_ab_gg[row_offset + j] * x[j];
            x[ii] = s / one_minus_ab_gg[row_offset + ii];
        }
        for (0..n_gauss) |i| inverse[i * n_gauss + rhs_col] = x[i];
    }

    var result = Mat{ .data = undefined, .n = n };
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            result.data[i * n + j] = inverse[i * n_gauss + j] - delta;
        }
    }

    for (0..n_extra) |ja| {
        const j = n_gauss + ja;
        for (0..n_gauss) |i| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| s += inverse[i * n_gauss + k] * ab.data[k * n + j];
            result.data[i * n + j] = s;
        }
    }

    var tmp: [types.max_extra * types.max_gauss]f64 = undefined;
    for (0..n_extra) |ia| {
        for (0..n_gauss) |j| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| s += ab.data[(n_gauss + ia) * n + k] * inverse[k * n_gauss + j];
            tmp[ia * n_gauss + j] = s;
            result.data[(n_gauss + ia) * n + j] = s;
        }
    }

    for (0..n_extra) |ia| {
        const i = n_gauss + ia;
        for (0..n_extra) |ja| {
            const j = n_gauss + ja;
            var s: f64 = 0.0;
            for (0..n_gauss) |k| s += tmp[ia * n_gauss + k] * ab.data[k * n + j];
            result.data[i * n + j] = s + ab.data[i * n + j];
        }
    }

    return result;
}
