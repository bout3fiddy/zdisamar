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
