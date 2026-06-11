const std = @import("std");

const internal = @import("internal");

const matrix_12x10 = internal.transport.matrix_12x10;
const rows = internal.transport.rows;

test "smul generic path matches scalar Gaussian product" {
    var a = rows.Mat.zero(6);
    var b = rows.Mat.zero(6);
    fillPattern(&a, 6, 0.03, 0.07);
    fillPattern(&b, 6, 0.11, -0.02);

    const result = matrix_12x10.smul(6, 4, 1.0e-30, &a, &b);
    const expected = scalarGaussianProduct(6, 4, &a, &b);

    try expectMatrixClose(expected, result, 6, 1.0e-13);
}

test "smul fixed 12x10 path matches scalar Gaussian product" {
    var a = rows.Mat.zero(12);
    var b = rows.Mat.zero(12);
    fillPattern(&a, 12, 0.017, 0.031);
    fillPattern(&b, 12, -0.013, 0.021);

    const result = matrix_12x10.smul(12, 10, 1.0e-30, &a, &b);
    const expected = scalarGaussianProduct(12, 10, &a, &b);

    try expectMatrixClose(expected, result, 12, 1.0e-13);
}

test "smul trace gate returns zero matrix on negligible product" {
    var a = rows.Mat.zero(12);
    var b = rows.Mat.zero(12);
    fillPattern(&a, 12, 0.017, 0.031);
    fillPattern(&b, 12, -0.013, 0.021);

    const result = matrix_12x10.smul(12, 10, 1.0e9, &a, &b);
    try std.testing.expectEqual(@as(usize, 12), result.n);
    for (result.data) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }
}

test "smulInto writes caller-owned output for retained and skipped products" {
    var a = rows.Mat.zero(12);
    var b = rows.Mat.zero(12);
    fillPattern(&a, 12, 0.017, 0.031);
    fillPattern(&b, 12, -0.013, 0.021);
    const n: usize = 12;
    const n_gauss: usize = 10;
    const retained_threshold: f64 = 1.0e-30;
    const skipped_threshold: f64 = 1.0e9;

    var out = rows.Mat.zero(12);
    matrix_12x10.smulInto(&out, n, n_gauss, retained_threshold, &a, &b);
    const expected = scalarGaussianProduct(12, 10, &a, &b);
    try expectMatrixClose(expected, out, 12, 1.0e-13);

    matrix_12x10.smulInto(&out, n, n_gauss, skipped_threshold, &a, &b);
    for (out.data) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }
}

test "smulIntoKnownTraces uses caller traces for retained and skipped products" {
    var a = rows.Mat.zero(12);
    var b = rows.Mat.zero(12);
    fillPattern(&a, 12, 0.017, 0.031);
    fillPattern(&b, 12, -0.013, 0.021);

    const trace_a = scalarGaussianTrace(12, 10, &a);
    const trace_b = scalarGaussianTrace(12, 10, &b);
    const expected = scalarGaussianProduct(12, 10, &a, &b);
    var out = rows.Mat.zero(12);

    matrix_12x10.smulIntoKnownTraces(&out, 12, 10, 1.0e-30, trace_a, trace_b, &a, &b);
    try expectMatrixClose(expected, out, 12, 1.0e-13);

    matrix_12x10.smulIntoKnownTraces(&out, 12, 10, 1.0e9, trace_a, trace_b, &a, &b);
    for (out.data) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }
}

test "smulIntoKnownTracesIfNonzero reports whether product was retained" {
    var a = rows.Mat.zero(6);
    var b = rows.Mat.zero(6);
    fillPattern(&a, 6, 0.03, 0.07);
    fillPattern(&b, 6, 0.11, -0.02);

    const trace_a = scalarGaussianTrace(6, 4, &a);
    const trace_b = scalarGaussianTrace(6, 4, &b);
    const expected = scalarGaussianProduct(6, 4, &a, &b);
    var out = rows.Mat.zero(6);

    const retained = matrix_12x10.smulIntoKnownTracesIfNonzero(
        &out,
        6,
        4,
        1.0e-30,
        trace_a,
        trace_b,
        &a,
        &b,
    );
    try std.testing.expect(retained);
    try expectMatrixClose(expected, out, 6, 1.0e-13);

    const skipped = matrix_12x10.smulIntoKnownTracesIfNonzero(
        &out,
        6,
        4,
        1.0e9,
        trace_a,
        trace_b,
        &a,
        &b,
    );
    try std.testing.expect(!skipped);
}

test "diagonal scale helpers match scalar references for generic path" {
    var a = rows.Mat.zero(6);
    var b = rows.Mat.zero(6);
    var c = rows.Mat.zero(6);
    var e = rows.Vec.zero(6);
    fillPattern(&a, 6, 0.03, 0.07);
    fillPattern(&b, 6, 0.11, -0.02);
    fillPattern(&c, 6, -0.04, 0.09);
    fillVector(&e, 6, 0.5, 0.125);

    try expectMatrixClose(scalarEsmul(6, &e, &a), matrix_12x10.esmul(6, &e, &a), 6, 1.0e-13);
    try expectMatrixClose(scalarSemul(6, &a, &e), matrix_12x10.semul(6, &a, &e), 6, 1.0e-13);
    try expectMatrixClose(scalarMatAdd(6, &a, &b), matrix_12x10.matAdd(6, &a, &b), 6, 1.0e-13);
    try expectMatrixClose(
        scalarMatAddSemul3(6, &a, &b, &e, &c),
        matrix_12x10.matAddSemul3(6, &a, &b, &e, &c),
        6,
        1.0e-13,
    );
}

test "diagonal scale helpers match scalar references for fixed n12 path" {
    var a = rows.Mat.zero(12);
    var b = rows.Mat.zero(12);
    var c = rows.Mat.zero(12);
    var e = rows.Vec.zero(12);
    fillPattern(&a, 12, 0.017, 0.031);
    fillPattern(&b, 12, -0.013, 0.021);
    fillPattern(&c, 12, 0.019, -0.027);
    fillVector(&e, 12, 0.5, 0.0625);

    try expectMatrixClose(scalarEsmul(12, &e, &a), matrix_12x10.esmul(12, &e, &a), 12, 1.0e-13);
    try expectMatrixClose(scalarSemul(12, &a, &e), matrix_12x10.semul(12, &a, &e), 12, 1.0e-13);
    try expectMatrixClose(
        scalarMatAddSemul3(12, &a, &b, &e, &c),
        matrix_12x10.matAddSemul3(12, &a, &b, &e, &c),
        12,
        1.0e-13,
    );
}

fn fillPattern(matrix: *rows.Mat, n: usize, row_factor: f64, col_factor: f64) void {
    // fillPattern ------------------------------------------------------------------------------------------- |
    // Build deterministic dense test input with nonzero Gaussian traces.                                      |
    // --------------------------------------------------------------------------------------------------------|
    matrix.* = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            const row_term = @as(f64, @floatFromInt(row + 1)) * row_factor;
            const col_term = @as(f64, @floatFromInt(col + 2)) * col_factor;
            matrix.set(row, col, 1.0 + row_term + col_term);
        }
    }
}

fn fillVector(vector: *rows.Vec, n: usize, base: f64, step: f64) void {
    // fillVector -------------------------------------------------------------------------------------------- |
    // Build deterministic vector input for diagonal scale tests.                                              |
    // --------------------------------------------------------------------------------------------------------|
    vector.* = rows.Vec.zero(n);
    for (0..n) |index| {
        vector.set(index, base + @as(f64, @floatFromInt(index)) * step);
    }
}

fn scalarGaussianTrace(n: usize, n_gauss: usize, matrix: *const rows.Mat) f64 {
    // scalarGaussianTrace ----------------------------------------------------------------------------------- |
    // Independent test reference for trace(M_gg).                                                             |
    // --------------------------------------------------------------------------------------------------------|
    var trace: f64 = 0.0;
    for (0..n_gauss) |gauss_index| {
        trace += matrix.get(gauss_index, gauss_index);
    }
    _ = n;
    return trace;
}

fn scalarEsmul(n: usize, e: *const rows.Vec, a: *const rows.Mat) rows.Mat {
    // scalarEsmul ------------------------------------------------------------------------------------------- |
    // Independent test reference for diag(e) * A.                                                             |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            result.set(row, col, e.get(row) * a.get(row, col));
        }
    }
    return result;
}

fn scalarSemul(n: usize, a: *const rows.Mat, e: *const rows.Vec) rows.Mat {
    // scalarSemul ------------------------------------------------------------------------------------------- |
    // Independent test reference for A * diag(e).                                                             |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            result.set(row, col, a.get(row, col) * e.get(col));
        }
    }
    return result;
}

fn scalarMatAdd(n: usize, a: *const rows.Mat, b: *const rows.Mat) rows.Mat {
    // scalarMatAdd ------------------------------------------------------------------------------------------ |
    // Independent test reference for elementwise A + B.                                                       |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            result.set(row, col, a.get(row, col) + b.get(row, col));
        }
    }
    return result;
}

fn scalarMatAddSemul3(
    n: usize,
    a: *const rows.Mat,
    b: *const rows.Mat,
    e: *const rows.Vec,
    c: *const rows.Mat,
) rows.Mat {
    // scalarMatAddSemul3 ------------------------------------------------------------------------------------ |
    // Independent test reference for A + B * diag(e) + C.                                                     |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            result.set(row, col, (a.get(row, col) + b.get(row, col) * e.get(col)) + c.get(row, col));
        }
    }
    return result;
}

fn scalarGaussianProduct(n: usize, n_gauss: usize, a: *const rows.Mat, b: *const rows.Mat) rows.Mat {
    // scalarGaussianProduct --------------------------------------------------------------------------------- |
    // Independent test reference for C[i,j] = sum_k A[i,k] * B[k,j].                                          |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            var sum: f64 = 0.0;
            for (0..n_gauss) |gauss_index| {
                sum += a.get(row, gauss_index) * b.get(gauss_index, col);
            }
            result.set(row, col, sum);
        }
    }
    return result;
}

fn expectMatrixClose(expected: rows.Mat, actual: rows.Mat, n: usize, tolerance: f64) !void {
    // expectMatrixClose ------------------------------------------------------------------------------------  |
    // Compare only the active n by n block; inactive fixed storage is outside the matrix contract.            |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectEqual(n, actual.n);
    for (0..n) |row| {
        for (0..n) |col| {
            try std.testing.expectApproxEqAbs(expected.get(row, col), actual.get(row, col), tolerance);
        }
    }
}
