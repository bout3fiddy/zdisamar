const types = @import("types.zig");

const Mat = types.Mat;
const Vec = types.Vec;

const threshold_q: f64 = 1.0e-3;

// hot path:
//   when: dynamic LABOS matrix products are selected by stream count or route shape
//   work: multiplies small dense RT matrices with thresholded nonzero handling
//   data: Mat cell arrays, n/n_gauss dimensions, product threshold
//   follow: smulInto variants and dynamic q-series callers
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

pub inline fn smulInto(noalias out: *Mat, n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) void {
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
        if (@abs(tra * trb) <= threshold_mul) {
            out.* = Mat.zero(n);
            return;
        }
        smul12x10Into(out, a, b);
        return;
    }
    out.* = smul(n, n_gauss, threshold_mul, a, b);
}

pub inline fn smulIntoKnownTraces(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    trace_a: f64,
    trace_b: f64,
    a: *const Mat,
    b: *const Mat,
) void {
    if (smulIntoKnownTracesIfNonzero(out, n, n_gauss, threshold_mul, trace_a, trace_b, a, b)) return;
    out.* = Mat.zero(n);
}

pub inline fn smulIntoKnownTracesIfNonzero(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    trace_a: f64,
    trace_b: f64,
    a: *const Mat,
    b: *const Mat,
) bool {
    @setEvalBranchQuota(10_000);
    if (@abs(trace_a * trace_b) <= threshold_mul) {
        return false;
    }
    if (n == 12 and n_gauss == 10) {
        smul12x10Into(out, a, b);
        return true;
    }
    out.* = smulNonzeroProduct(n, n_gauss, a, b);
    return true;
}

inline fn smul12x10(a: *const Mat, b: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    smul12x10Into(&result, a, b);
    return result;
}

// hot path:
//   when: fixed 12x10 LABOS layer-doubling path multiplies RT matrices
//   work: writes matrix products directly into caller-owned storage
//   data: fixed Mat cells, left/right matrix operands, noalias result storage
//   follow: doDouble12x10Step and fixed-shape product composition
inline fn smul12x10Into(noalias result: *Mat, a: *const Mat, b: *const Mat) void {
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const a0: @Vector(2, f64) = @splat(a.data[row]);
        const a1: @Vector(2, f64) = @splat(a.data[row + 1]);
        const a2: @Vector(2, f64) = @splat(a.data[row + 2]);
        const a3: @Vector(2, f64) = @splat(a.data[row + 3]);
        const a4: @Vector(2, f64) = @splat(a.data[row + 4]);
        const a5: @Vector(2, f64) = @splat(a.data[row + 5]);
        const a6: @Vector(2, f64) = @splat(a.data[row + 6]);
        const a7: @Vector(2, f64) = @splat(a.data[row + 7]);
        const a8: @Vector(2, f64) = @splat(a.data[row + 8]);
        const a9: @Vector(2, f64) = @splat(a.data[row + 9]);
        const b0 = b.data[0..12];
        const b1 = b.data[12..24];
        const b2 = b.data[24..36];
        const b3 = b.data[36..48];
        const b4 = b.data[48..60];
        const b5 = b.data[60..72];
        const b6 = b.data[72..84];
        const b7 = b.data[84..96];
        const b8 = b.data[96..108];
        const b9 = b.data[108..120];
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;
            // TARGET:
            //   Keep this as separate vector multiply/add. In the generic
            //   x86_64 Linux wheel, `@mulAdd` lowers to compiler-rt `fma`
            //   calls unless hardware FMA is part of the target contract.
            var s = a0 * loadPair(b0, j);
            s += a1 * loadPair(b1, j);
            s += a2 * loadPair(b2, j);
            s += a3 * loadPair(b3, j);
            s += a4 * loadPair(b4, j);
            s += a5 * loadPair(b5, j);
            s += a6 * loadPair(b6, j);
            s += a7 * loadPair(b7, j);
            s += a8 * loadPair(b8, j);
            s += a9 * loadPair(b9, j);
            result.data[row + j] = s[0];
            result.data[row + j + 1] = s[1];
        }
    }
}

inline fn loadPair(row: []const f64, comptime j: usize) @Vector(2, f64) {
    const pair: *align(1) const @Vector(2, f64) = @ptrCast(&row[j]);
    return pair.*;
}

inline fn storePair(row: []f64, comptime j: usize, values: @Vector(2, f64)) void {
    const pair: *align(1) @Vector(2, f64) = @ptrCast(&row[j]);
    pair.* = values;
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

pub inline fn matAddSemul3(n: usize, a: *const Mat, b: *const Mat, e: *const Vec, c: *const Mat) Mat {
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

pub inline fn smulAddSemul3(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, e: *const Vec, c: *const Mat) Mat {
    if (n == 12 and n_gauss == 10) return smulAddSemul3_12(threshold_mul, a, e, c);
    var product: Mat = undefined;
    smulInto(&product, n, n_gauss, threshold_mul, a, c);
    return matAddSemul3(n, c, a, e, &product);
}

pub inline fn smulAddSemul3KnownRightTrace(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, e: *const Vec, c: *const Mat, trace_c: f64) Mat {
    if (n == 12 and n_gauss == 10) return smulAddSemul3_12KnownRightTrace(threshold_mul, a, e, c, trace_c);

    var trace_a: f64 = 0.0;
    for (0..n_gauss) |k| trace_a += a.data[k * n + k];

    var product: Mat = undefined;
    if (smulIntoKnownTracesIfNonzero(&product, n, n_gauss, threshold_mul, trace_a, trace_c, a, c)) {
        return matAddSemul3(n, c, a, e, &product);
    }
    return semulAdd(n, a, e, c);
}

pub inline fn smulAddSemul3KnownRightTraceInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: *const Mat,
    e: *const Vec,
    c: *const Mat,
    trace_c: f64,
) void {
    if (n == 12 and n_gauss == 10) return smulAddSemul3_12KnownRightTraceInto(out, threshold_mul, a, e, c, trace_c);
    out.* = smulAddSemul3KnownRightTrace(n, n_gauss, threshold_mul, a, e, c, trace_c);
}

pub inline fn matAddEsmul3(n: usize, a: *const Mat, e: *const Vec, b: *const Mat, c: *const Mat) Mat {
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

pub inline fn matAddEsmul3ProductKnownNonzeroInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    a: *const Mat,
    e: *const Vec,
    b: *const Mat,
    c: *const Mat,
) void {
    if (n == 12 and n_gauss == 10) return matAddEsmul3ProductKnownNonzero12x10Into(out, a, e, b, c);

    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        for (0..n) |i| {
            var product: f64 = 0.0;
            for (0..n_gauss) |k| product += c.data[i * n + k] * b.data[k * n + j];
            const idx = i * n + j;
            out.data[idx] = (a.data[idx] + e.data[i] * b.data[idx]) + product;
        }
    }
}

pub inline fn matAddEsmul(n: usize, a: *const Mat, e: *const Vec, b: *const Mat) Mat {
    if (n == 12) return matAddEsmul12(a, e, b);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        var idx = j;
        for (0..n) |i| {
            result.data[idx] = a.data[idx] + e.data[i] * b.data[idx];
            idx += n;
        }
    }
    return result;
}

pub inline fn matAddEsmulInto(noalias out: *Mat, n: usize, a: *const Mat, e: *const Vec, b: *const Mat) void {
    if (n == 12) return matAddEsmul12Into(out, a, e, b);
    out.* = matAddEsmul(n, a, e, b);
}

pub inline fn semulAdd(n: usize, a: *const Mat, e: *const Vec, b: *const Mat) Mat {
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

pub inline fn semulAddProductKnownNonzeroInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    a: *const Mat,
    e: *const Vec,
    b: *const Mat,
) void {
    if (n == 12 and n_gauss == 10) return semulAddProductKnownNonzero12x10Into(out, a, e, b);

    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        for (0..n) |i| {
            var product: f64 = 0.0;
            for (0..n_gauss) |k| product += a.data[i * n + k] * b.data[k * n + j];
            const idx = i * n + j;
            out.data[idx] = a.data[idx] * ej + product;
        }
    }
}

pub inline fn semulInto(noalias out: *Mat, n: usize, a: *const Mat, e: *const Vec) void {
    if (n == 12) return semul12Into(out, a, e);
    out.* = semul(n, a, e);
}

pub inline fn esmulSemul(n: usize, e: *const Vec, a: *const Mat, b: *const Mat) Mat {
    if (n == 12) return esmulSemul12(e, a, b);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |i| {
            result.data[idx] = e.data[i] * a.data[idx] + b.data[idx] * ej;
            idx += n;
        }
    }
    return result;
}

pub inline fn esmulSemulInto(noalias out: *Mat, n: usize, e: *const Vec, a: *const Mat, b: *const Mat) void {
    if (n == 12) return esmulSemul12Into(out, e, a, b);
    out.* = esmulSemul(n, e, a, b);
}

pub inline fn esmulSemulSelfInto(noalias out: *Mat, n: usize, e: *const Vec, a: *const Mat) void {
    if (n == 12) return esmulSemulSelf12Into(out, e, a);
    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |i| {
            out.data[idx] = a.data[idx] * (e.data[i] + ej);
            idx += n;
        }
    }
}

pub inline fn esmulSemulAdd(n: usize, e: *const Vec, a: *const Mat, b: *const Mat, c: *const Mat) Mat {
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

pub inline fn esmulSemulAddProductKnownNonzeroInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    e: *const Vec,
    a: *const Mat,
    b: *const Mat,
) void {
    if (n == 12 and n_gauss == 10) return esmulSemulAddProductKnownNonzero12x10Into(out, e, a, b);

    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        for (0..n) |i| {
            var product: f64 = 0.0;
            for (0..n_gauss) |k| product += b.data[i * n + k] * a.data[k * n + j];
            const idx = i * n + j;
            out.data[idx] = (e.data[i] * a.data[idx] + b.data[idx] * ej) + product;
        }
    }
}

pub inline fn esmulSemulSelfAddProductKnownNonzeroInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    e: *const Vec,
    a: *const Mat,
) void {
    if (n == 12 and n_gauss == 10) return esmulSemulSelfAddProductKnownNonzero12x10Into(out, e, a);

    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        for (0..n) |i| {
            var product: f64 = 0.0;
            for (0..n_gauss) |k| product += a.data[i * n + k] * a.data[k * n + j];
            const idx = i * n + j;
            out.data[idx] = a.data[idx] * (e.data[i] + ej) + product;
        }
    }
}

fn esmul12(e: *const Vec, a: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    inline for (0..12) |j| {
        var idx = j;
        inline for (0..12) |i| {
            result.data[idx] = e.data[i] * a.data[idx];
            idx += 12;
        }
    }
    return result;
}

fn semul12(a: *const Mat, e: *const Vec) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    semul12Into(&result, a, e);
    return result;
}

fn semul12Into(noalias result: *Mat, a: *const Mat, e: *const Vec) void {
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |j| {
        const ej = e.data[j];
        var idx = j;
        inline for (0..12) |_| {
            result.data[idx] = a.data[idx] * ej;
            idx += 12;
        }
    }
}

fn matAddSemul3_12(noalias a: *const Mat, noalias b: *const Mat, noalias e: *const Vec, noalias c: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        inline for (0..12) |j| {
            const idx = row + j;
            const ej = e.data[j];
            result.data[idx] = (a.data[idx] + b.data[idx] * ej) + c.data[idx];
        }
    }
    return result;
}

fn smulAddSemul3_12(threshold_mul: f64, a: *const Mat, e: *const Vec, c: *const Mat) Mat {
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
    var trc = c.data[0];
    trc += c.data[13];
    trc += c.data[26];
    trc += c.data[39];
    trc += c.data[52];
    trc += c.data[65];
    trc += c.data[78];
    trc += c.data[91];
    trc += c.data[104];
    trc += c.data[117];

    return smulAddSemul3_12KnownTraces(threshold_mul, a, e, c, tra, trc);
}

fn smulAddSemul3_12KnownRightTrace(threshold_mul: f64, a: *const Mat, e: *const Vec, c: *const Mat, trc: f64) Mat {
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

    return smulAddSemul3_12KnownTraces(threshold_mul, a, e, c, tra, trc);
}

fn smulAddSemul3_12KnownRightTraceInto(noalias result: *Mat, threshold_mul: f64, a: *const Mat, e: *const Vec, c: *const Mat, trc: f64) void {
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

    smulAddSemul3_12KnownTracesInto(result, threshold_mul, a, e, c, tra, trc);
}

fn smulAddSemul3_12KnownTraces(threshold_mul: f64, a: *const Mat, e: *const Vec, c: *const Mat, tra: f64, trc: f64) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    smulAddSemul3_12KnownTracesInto(&result, threshold_mul, a, e, c, tra, trc);
    return result;
}

fn smulAddSemul3_12KnownTracesInto(noalias result: *Mat, threshold_mul: f64, a: *const Mat, e: *const Vec, c: *const Mat, tra: f64, trc: f64) void {
    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    if (@abs(tra * trc) <= threshold_mul) {
        inline for (0..12) |i| {
            const row = i * 12;
            const a_row = a.data[row .. row + 12];
            const c_row = c.data[row .. row + 12];
            const result_row = result.data[row .. row + 12];
            inline for (0..6) |pair_index| {
                const j = pair_index * 2;
                const value = loadPair(c_row, j) + loadPair(a_row, j) * loadPair(e.data[0..], j);
                storePair(result_row, j, value);
            }
        }
        return;
    }

    inline for (0..12) |i| {
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
        const c0 = c.data[0..12];
        const c1 = c.data[12..24];
        const c2 = c.data[24..36];
        const c3 = c.data[36..48];
        const c4 = c.data[48..60];
        const c5 = c.data[60..72];
        const c6 = c.data[72..84];
        const c7 = c.data[84..96];
        const c8 = c.data[96..108];
        const c9 = c.data[108..120];
        const a_row = a.data[row .. row + 12];
        const c_row = c.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        const a0v: @Vector(2, f64) = @splat(a0);
        const a1v: @Vector(2, f64) = @splat(a1);
        const a2v: @Vector(2, f64) = @splat(a2);
        const a3v: @Vector(2, f64) = @splat(a3);
        const a4v: @Vector(2, f64) = @splat(a4);
        const a5v: @Vector(2, f64) = @splat(a5);
        const a6v: @Vector(2, f64) = @splat(a6);
        const a7v: @Vector(2, f64) = @splat(a7);
        const a8v: @Vector(2, f64) = @splat(a8);
        const a9v: @Vector(2, f64) = @splat(a9);
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;
            var product = a0v * loadPair(c0, j);
            product += a1v * loadPair(c1, j);
            product += a2v * loadPair(c2, j);
            product += a3v * loadPair(c3, j);
            product += a4v * loadPair(c4, j);
            product += a5v * loadPair(c5, j);
            product += a6v * loadPair(c6, j);
            product += a7v * loadPair(c7, j);
            product += a8v * loadPair(c8, j);
            product += a9v * loadPair(c9, j);
            const base = loadPair(c_row, j) + loadPair(a_row, j) * loadPair(e.data[0..], j);
            storePair(result_row, j, base + product);
        }
    }
}

fn matAddEsmul3_12(noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat, noalias c: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    matAddEsmul3_12Into(&result, a, e, b, c);
    return result;
}

fn matAddEsmul3_12Into(noalias result: *Mat, noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat, noalias c: *const Mat) void {
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            result.data[idx] = (a.data[idx] + ei * b.data[idx]) + c.data[idx];
        }
    }
}

fn matAddEsmul12(noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    matAddEsmul12Into(&result, a, e, b);
    return result;
}

fn matAddEsmul12Into(noalias result: *Mat, noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat) void {
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            result.data[idx] = a.data[idx] + ei * b.data[idx];
        }
    }
}

fn matAddEsmul3ProductKnownNonzero12x10Into(noalias result: *Mat, noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat, noalias c: *const Mat) void {
    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const c0 = c.data[row];
        const c1 = c.data[row + 1];
        const c2 = c.data[row + 2];
        const c3 = c.data[row + 3];
        const c4 = c.data[row + 4];
        const c5 = c.data[row + 5];
        const c6 = c.data[row + 6];
        const c7 = c.data[row + 7];
        const c8 = c.data[row + 8];
        const c9 = c.data[row + 9];
        const b0 = b.data[0..12];
        const b1 = b.data[12..24];
        const b2 = b.data[24..36];
        const b3 = b.data[36..48];
        const b4 = b.data[48..60];
        const b5 = b.data[60..72];
        const b6 = b.data[72..84];
        const b7 = b.data[84..96];
        const b8 = b.data[96..108];
        const b9 = b.data[108..120];
        const a_row = a.data[row .. row + 12];
        const b_row = b.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        const ei: @Vector(2, f64) = @splat(e.data[i]);
        const c0v: @Vector(2, f64) = @splat(c0);
        const c1v: @Vector(2, f64) = @splat(c1);
        const c2v: @Vector(2, f64) = @splat(c2);
        const c3v: @Vector(2, f64) = @splat(c3);
        const c4v: @Vector(2, f64) = @splat(c4);
        const c5v: @Vector(2, f64) = @splat(c5);
        const c6v: @Vector(2, f64) = @splat(c6);
        const c7v: @Vector(2, f64) = @splat(c7);
        const c8v: @Vector(2, f64) = @splat(c8);
        const c9v: @Vector(2, f64) = @splat(c9);
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;
            var product = c0v * loadPair(b0, j);
            product += c1v * loadPair(b1, j);
            product += c2v * loadPair(b2, j);
            product += c3v * loadPair(b3, j);
            product += c4v * loadPair(b4, j);
            product += c5v * loadPair(b5, j);
            product += c6v * loadPair(b6, j);
            product += c7v * loadPair(b7, j);
            product += c8v * loadPair(b8, j);
            product += c9v * loadPair(b9, j);
            const value = (loadPair(a_row, j) + ei * loadPair(b_row, j)) + product;
            storePair(result_row, j, value);
        }
    }
}

fn semulAdd12(noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    semulAdd12Into(&result, a, e, b);
    return result;
}

fn semulAdd12Into(noalias result: *Mat, noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat) void {
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |j| {
        const ej = e.data[j];
        var idx = j;
        inline for (0..12) |_| {
            result.data[idx] = a.data[idx] * ej + b.data[idx];
            idx += 12;
        }
    }
}

fn semulAddProductKnownNonzero12x10Into(noalias result: *Mat, noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat) void {
    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
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
        const b0 = b.data[0..12];
        const b1 = b.data[12..24];
        const b2 = b.data[24..36];
        const b3 = b.data[36..48];
        const b4 = b.data[48..60];
        const b5 = b.data[60..72];
        const b6 = b.data[72..84];
        const b7 = b.data[84..96];
        const b8 = b.data[96..108];
        const b9 = b.data[108..120];
        const a_row = a.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        const a0v: @Vector(2, f64) = @splat(a0);
        const a1v: @Vector(2, f64) = @splat(a1);
        const a2v: @Vector(2, f64) = @splat(a2);
        const a3v: @Vector(2, f64) = @splat(a3);
        const a4v: @Vector(2, f64) = @splat(a4);
        const a5v: @Vector(2, f64) = @splat(a5);
        const a6v: @Vector(2, f64) = @splat(a6);
        const a7v: @Vector(2, f64) = @splat(a7);
        const a8v: @Vector(2, f64) = @splat(a8);
        const a9v: @Vector(2, f64) = @splat(a9);
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;
            var product = a0v * loadPair(b0, j);
            product += a1v * loadPair(b1, j);
            product += a2v * loadPair(b2, j);
            product += a3v * loadPair(b3, j);
            product += a4v * loadPair(b4, j);
            product += a5v * loadPair(b5, j);
            product += a6v * loadPair(b6, j);
            product += a7v * loadPair(b7, j);
            product += a8v * loadPair(b8, j);
            product += a9v * loadPair(b9, j);
            const value = loadPair(a_row, j) * loadPair(e.data[0..], j) + product;
            storePair(result_row, j, value);
        }
    }
}

fn esmulSemul12(noalias e: *const Vec, noalias a: *const Mat, noalias b: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    esmulSemul12Into(&result, e, a, b);
    return result;
}

fn esmulSemul12Into(noalias result: *Mat, noalias e: *const Vec, noalias a: *const Mat, noalias b: *const Mat) void {
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            const ej = e.data[j];
            result.data[idx] = ei * a.data[idx] + b.data[idx] * ej;
        }
    }
}

fn esmulSemulSelf12Into(noalias result: *Mat, noalias e: *const Vec, noalias a: *const Mat) void {
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            result.data[idx] = a.data[idx] * (ei + e.data[j]);
        }
    }
}

fn esmulSemulAdd12(noalias e: *const Vec, noalias a: *const Mat, noalias b: *const Mat, noalias c: *const Mat) Mat {
    var result = Mat{ .data = undefined, .n = 12 };
    esmulSemulAdd12Into(&result, e, a, b, c);
    return result;
}

fn esmulSemulAdd12Into(noalias result: *Mat, noalias e: *const Vec, noalias a: *const Mat, noalias b: *const Mat, noalias c: *const Mat) void {
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            const ej = e.data[j];
            result.data[idx] = (ei * a.data[idx] + b.data[idx] * ej) + c.data[idx];
        }
    }
}

fn esmulSemulAddProductKnownNonzero12x10Into(noalias result: *Mat, noalias e: *const Vec, noalias a: *const Mat, noalias b: *const Mat) void {
    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const b0 = b.data[row];
        const b1 = b.data[row + 1];
        const b2 = b.data[row + 2];
        const b3 = b.data[row + 3];
        const b4 = b.data[row + 4];
        const b5 = b.data[row + 5];
        const b6 = b.data[row + 6];
        const b7 = b.data[row + 7];
        const b8 = b.data[row + 8];
        const b9 = b.data[row + 9];
        const a0 = a.data[0..12];
        const a1 = a.data[12..24];
        const a2 = a.data[24..36];
        const a3 = a.data[36..48];
        const a4 = a.data[48..60];
        const a5 = a.data[60..72];
        const a6 = a.data[72..84];
        const a7 = a.data[84..96];
        const a8 = a.data[96..108];
        const a9 = a.data[108..120];
        const a_row = a.data[row .. row + 12];
        const b_row = b.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        const ei: @Vector(2, f64) = @splat(e.data[i]);
        const b0v: @Vector(2, f64) = @splat(b0);
        const b1v: @Vector(2, f64) = @splat(b1);
        const b2v: @Vector(2, f64) = @splat(b2);
        const b3v: @Vector(2, f64) = @splat(b3);
        const b4v: @Vector(2, f64) = @splat(b4);
        const b5v: @Vector(2, f64) = @splat(b5);
        const b6v: @Vector(2, f64) = @splat(b6);
        const b7v: @Vector(2, f64) = @splat(b7);
        const b8v: @Vector(2, f64) = @splat(b8);
        const b9v: @Vector(2, f64) = @splat(b9);
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;
            var product = b0v * loadPair(a0, j);
            product += b1v * loadPair(a1, j);
            product += b2v * loadPair(a2, j);
            product += b3v * loadPair(a3, j);
            product += b4v * loadPair(a4, j);
            product += b5v * loadPair(a5, j);
            product += b6v * loadPair(a6, j);
            product += b7v * loadPair(a7, j);
            product += b8v * loadPair(a8, j);
            product += b9v * loadPair(a9, j);
            const value = (ei * loadPair(a_row, j) + loadPair(b_row, j) * loadPair(e.data[0..], j)) + product;
            storePair(result_row, j, value);
        }
    }
}

fn esmulSemulSelfAddProductKnownNonzero12x10Into(noalias result: *Mat, noalias e: *const Vec, noalias a: *const Mat) void {
    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
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
        const c0 = a.data[0..12];
        const c1 = a.data[12..24];
        const c2 = a.data[24..36];
        const c3 = a.data[36..48];
        const c4 = a.data[48..60];
        const c5 = a.data[60..72];
        const c6 = a.data[72..84];
        const c7 = a.data[84..96];
        const c8 = a.data[96..108];
        const c9 = a.data[108..120];
        const a_row = a.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        const ei: @Vector(2, f64) = @splat(e.data[i]);
        const a0v: @Vector(2, f64) = @splat(a0);
        const a1v: @Vector(2, f64) = @splat(a1);
        const a2v: @Vector(2, f64) = @splat(a2);
        const a3v: @Vector(2, f64) = @splat(a3);
        const a4v: @Vector(2, f64) = @splat(a4);
        const a5v: @Vector(2, f64) = @splat(a5);
        const a6v: @Vector(2, f64) = @splat(a6);
        const a7v: @Vector(2, f64) = @splat(a7);
        const a8v: @Vector(2, f64) = @splat(a8);
        const a9v: @Vector(2, f64) = @splat(a9);
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;
            var product = a0v * loadPair(c0, j);
            product += a1v * loadPair(c1, j);
            product += a2v * loadPair(c2, j);
            product += a3v * loadPair(c3, j);
            product += a4v * loadPair(c4, j);
            product += a5v * loadPair(c5, j);
            product += a6v * loadPair(c6, j);
            product += a7v * loadPair(c7, j);
            product += a8v * loadPair(c8, j);
            product += a9v * loadPair(c9, j);
            const value = loadPair(a_row, j) * (ei + loadPair(e.data[0..], j)) + product;
            storePair(result_row, j, value);
        }
    }
}

pub fn qseries(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    const ab = smul(n, n_gauss, threshold_mul, a, b);
    return qseriesFromProduct(n, n_gauss, &ab);
}

pub inline fn qseriesKnownNonzeroProduct(n: usize, n_gauss: usize, a: *const Mat, b: *const Mat) Mat {
    const ab = smulNonzeroProduct(n, n_gauss, a, b);
    return qseriesFromProduct(n, n_gauss, &ab);
}

// hot path:
//   when: LABOS layer doubling computes q-series from a known-nonzero product
//   work: forms and factorizes the q-series matrix for reflection/transmission updates
//   data: input product matrices, q-series output, stream dimensions, known-nonzero shape
//   follow: dynamic doDouble and qseriesFromProductInto
pub inline fn qseriesKnownNonzeroProductInto(noalias out: *Mat, n: usize, n_gauss: usize, a: *const Mat, b: *const Mat) void {
    @setEvalBranchQuota(20_000);
    var ab: Mat = undefined;
    if (n == 12 and n_gauss == 10) {
        smul12x10Into(&ab, a, b);
    } else {
        ab = smulNonzeroProduct(n, n_gauss, a, b);
    }
    qseriesFromProductInto(out, n, n_gauss, &ab);
}

inline fn qseriesFromProductInto(noalias out: *Mat, n: usize, n_gauss: usize, noalias ab: *const Mat) void {
    if (n == 12 and n_gauss == 10) {
        qseriesFromProduct12x10Into(out, ab);
        return;
    }
    out.* = qseriesFromProduct(n, n_gauss, ab);
}

inline fn qseriesFromProduct(n: usize, n_gauss: usize, noalias ab: *const Mat) Mat {
    if (n == 12 and n_gauss == 10) return qseriesFromProduct12x10(ab);

    const trab: f64 = if (n == 12 and n_gauss == 10) blk: {
        var trace = ab.data[0];
        trace += ab.data[13];
        trace += ab.data[26];
        trace += ab.data[39];
        trace += ab.data[52];
        trace += ab.data[65];
        trace += ab.data[78];
        trace += ab.data[91];
        trace += ab.data[104];
        trace += ab.data[117];
        break :blk trace;
    } else blk: {
        var trace: f64 = 0.0;
        for (0..n_gauss) |k| trace += ab.data[k * n + k];
        break :blk trace;
    };
    if (@abs(trab) < threshold_q) return ab.*;

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
    var inverse_diag: [types.max_gauss]f64 = undefined;
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
        if (@abs(diag) < 1.0e-30) return ab.*;
        const inv_diag = 1.0 / diag;
        inverse_diag[col] = inv_diag;
        for (col + 1..n_gauss) |row| {
            const row_offset = pivot_offset[row];
            const col_offset = pivot_offset[col];
            const factor = one_minus_ab_gg[row_offset + col] * inv_diag;
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
            x[ii] = s * inverse_diag[ii];
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

fn qseriesFromProduct12x10(noalias ab: *const Mat) Mat {
    var result: Mat = undefined;
    qseriesFromProduct12x10Into(&result, ab);
    return result;
}

// hot path:
//   when: fixed 12x10 LABOS layer doubling computes the q-series matrix
//   work: factorizes the fixed-shape product used by doubling reflection/transmission updates
//   data: fixed Mat product, q-series result matrix, known fixed stream dimensions
//   follow: qseriesFromProduct12x10Into callers inside doDouble12x10Step
fn qseriesFromProduct12x10Into(noalias result: *Mat, noalias ab: *const Mat) void {
    result.* = .{ .data = undefined, .n = 12 };
    var trab = ab.data[0];
    trab += ab.data[13];
    trab += ab.data[26];
    trab += ab.data[39];
    trab += ab.data[52];
    trab += ab.data[65];
    trab += ab.data[78];
    trab += ab.data[91];
    trab += ab.data[104];
    trab += ab.data[117];
    if (@abs(trab) < threshold_q) {
        result.* = ab.*;
        return;
    }

    var one_minus_ab_gg: [types.max_gauss * types.max_gauss]f64 = undefined;
    inline for (0..10) |i| {
        inline for (0..10) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            one_minus_ab_gg[i * 10 + j] = delta - ab.data[i * 12 + j];
        }
    }

    var pivot: [types.max_gauss]usize = undefined;
    var inverse_diag: [types.max_gauss]f64 = undefined;
    inline for (0..10) |i| {
        pivot[i] = i;
    }

    for (0..10) |col| {
        var max_val: f64 = @abs(one_minus_ab_gg[col * 10 + col]);
        var max_row: usize = col;
        for (col + 1..10) |row| {
            const val = @abs(one_minus_ab_gg[row * 10 + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }
        if (max_row != col) {
            const tmp = pivot[col];
            pivot[col] = pivot[max_row];
            pivot[max_row] = tmp;
            // Previous-column LU factors belong to the pivoted row too.
            inline for (0..10) |k| {
                const lhs = col * 10 + k;
                const rhs = max_row * 10 + k;
                const matrix_tmp = one_minus_ab_gg[lhs];
                one_minus_ab_gg[lhs] = one_minus_ab_gg[rhs];
                one_minus_ab_gg[rhs] = matrix_tmp;
            }
        }
        const diag = one_minus_ab_gg[col * 10 + col];
        if (@abs(diag) < 1.0e-30) {
            result.* = ab.*;
            return;
        }
        const inv_diag = 1.0 / diag;
        inverse_diag[col] = inv_diag;
        const col_offset = col * 10;
        for (col + 1..10) |row| {
            const row_offset = row * 10;
            const factor = one_minus_ab_gg[row_offset + col] * inv_diag;
            one_minus_ab_gg[row_offset + col] = factor;
            for (col + 1..10) |k| {
                one_minus_ab_gg[row_offset + k] -=
                    factor * one_minus_ab_gg[col_offset + k];
            }
        }
    }

    var inverse: [types.max_gauss * types.max_gauss]f64 = undefined;
    for (0..10) |rhs_col| {
        var y: [types.max_gauss]f64 = undefined;
        for (0..10) |i| {
            var s: f64 = if (pivot[i] == rhs_col) 1.0 else 0.0;
            const row_offset = i * 10;
            for (0..i) |j| s -= one_minus_ab_gg[row_offset + j] * y[j];
            y[i] = s;
        }

        var x: [types.max_gauss]f64 = undefined;
        var ii: usize = 10;
        while (ii > 0) {
            ii -= 1;
            var s: f64 = y[ii];
            const row_offset = ii * 10;
            for (ii + 1..10) |j| s -= one_minus_ab_gg[row_offset + j] * x[j];
            x[ii] = s * inverse_diag[ii];
        }
        inline for (0..10) |i| inverse[i * 10 + rhs_col] = x[i];
    }

    inline for (0..10) |i| {
        inline for (0..10) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            result.data[i * 12 + j] = inverse[i * 10 + j] - delta;
        }
    }

    inline for (0..10) |i| {
        inline for (0..2) |ja| {
            const j = 10 + ja;
            var s: f64 = 0.0;
            inline for (0..10) |k| s += inverse[i * 10 + k] * ab.data[k * 12 + j];
            result.data[i * 12 + j] = s;
        }
    }

    inline for (0..2) |ia| {
        inline for (0..10) |j| {
            var s: f64 = 0.0;
            inline for (0..10) |k| s += ab.data[(10 + ia) * 12 + k] * inverse[k * 10 + j];
            result.data[(10 + ia) * 12 + j] = s;
        }
    }

    inline for (0..2) |ia| {
        const i = 10 + ia;
        inline for (0..2) |ja| {
            const j = 10 + ja;
            var s: f64 = 0.0;
            inline for (0..10) |k| s += result.data[i * 12 + k] * ab.data[k * 12 + j];
            result.data[i * 12 + j] = s + ab.data[i * 12 + j];
        }
    }
}

inline fn smulNonzeroProduct(n: usize, n_gauss: usize, a: *const Mat, b: *const Mat) Mat {
    if (n == 12 and n_gauss == 10) return smul12x10(a, b);

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
