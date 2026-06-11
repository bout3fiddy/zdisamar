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

test "qseries generic path matches scalar inverse reference" {
    var a = rows.Mat.zero(6);
    var b = rows.Mat.zero(6);
    fillQseriesInputs(&a, &b, 6, 4);

    const product = scalarGaussianProduct(6, 4, &a, &b);
    const expected = scalarQseriesFromProduct(6, 4, &product);
    const actual = matrix_12x10.qseriesKnownNonzeroProduct(6, 4, &a, &b);

    try expectMatrixClose(expected, actual, 6, 1.0e-12);
}

test "qseries fixed 12x10 path matches scalar inverse reference" {
    var a = rows.Mat.zero(12);
    var b = rows.Mat.zero(12);
    fillQseriesInputs(&a, &b, 12, 10);

    const product = scalarGaussianProduct(12, 10, &a, &b);
    const expected = scalarQseriesFromProduct(12, 10, &product);
    const actual = matrix_12x10.qseriesKnownNonzeroProduct(12, 10, &a, &b);

    try expectMatrixClose(expected, actual, 12, 1.0e-12);
}

test "qseriesKnownNonzeroProductInto writes caller-owned fixed output" {
    var a = rows.Mat.zero(12);
    var b = rows.Mat.zero(12);
    fillQseriesInputs(&a, &b, 12, 10);

    const product = scalarGaussianProduct(12, 10, &a, &b);
    const expected = scalarQseriesFromProduct(12, 10, &product);
    var actual = rows.Mat.zero(12);

    matrix_12x10.qseriesKnownNonzeroProductInto(&actual, 12, 10, &a, &b);

    try expectMatrixClose(expected, actual, 12, 1.0e-12);
}

test "qseries trace gate returns zero matrix after skipped product" {
    var a = rows.Mat.zero(12);
    var b = rows.Mat.zero(12);
    fillQseriesInputs(&a, &b, 12, 10);

    const actual = matrix_12x10.qseries(12, 10, 1.0e9, &a, &b);

    try std.testing.expectEqual(@as(usize, 12), actual.n);
    for (actual.data) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }
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
    try expectMatrixClose(
        scalarMatAddEsmul3(6, &a, &e, &b, &c),
        matrix_12x10.matAddEsmul3(6, &a, &e, &b, &c),
        6,
        1.0e-13,
    );
    try expectMatrixClose(
        scalarMatAddEsmul(6, &a, &e, &b),
        matrix_12x10.matAddEsmul(6, &a, &e, &b),
        6,
        1.0e-13,
    );
    try expectMatrixClose(scalarEsmulSemul(6, &e, &a, &b), matrix_12x10.esmulSemul(6, &e, &a, &b), 6, 1.0e-13);
    try expectMatrixClose(
        scalarEsmulSemulAdd(6, &e, &a, &b, &c),
        matrix_12x10.esmulSemulAdd(6, &e, &a, &b, &c),
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
    try expectMatrixClose(
        scalarMatAddEsmul3(12, &a, &e, &b, &c),
        matrix_12x10.matAddEsmul3(12, &a, &e, &b, &c),
        12,
        1.0e-13,
    );
    var left_add = rows.Mat.zero(12);
    matrix_12x10.matAddEsmulInto(&left_add, 12, &a, &e, &b);
    try expectMatrixClose(scalarMatAddEsmul(12, &a, &e, &b), left_add, 12, 1.0e-13);

    var right_scale = rows.Mat.zero(12);
    matrix_12x10.semulInto(&right_scale, 12, &a, &e);
    try expectMatrixClose(scalarSemul(12, &a, &e), right_scale, 12, 1.0e-13);

    var two_sided = rows.Mat.zero(12);
    matrix_12x10.esmulSemulInto(&two_sided, 12, &e, &a, &b);
    try expectMatrixClose(scalarEsmulSemul(12, &e, &a, &b), two_sided, 12, 1.0e-13);

    var self_two_sided = rows.Mat.zero(12);
    matrix_12x10.esmulSemulSelfInto(&self_two_sided, 12, &e, &a);
    try expectMatrixClose(scalarEsmulSemulSelf(12, &e, &a), self_two_sided, 12, 1.0e-13);

    try expectMatrixClose(
        scalarEsmulSemulAdd(12, &e, &a, &b, &c),
        matrix_12x10.esmulSemulAdd(12, &e, &a, &b, &c),
        12,
        1.0e-13,
    );
}

test "retained product diagonal add writers match scalar references" {
    var a = rows.Mat.zero(12);
    var b = rows.Mat.zero(12);
    var c = rows.Mat.zero(12);
    var e = rows.Vec.zero(12);
    fillPattern(&a, 12, 0.017, 0.031);
    fillPattern(&b, 12, -0.013, 0.021);
    fillPattern(&c, 12, 0.019, -0.027);
    fillVector(&e, 12, 0.5, 0.0625);

    var left_scaled = rows.Mat.zero(12);
    matrix_12x10.matAddEsmul3ProductKnownNonzeroInto(&left_scaled, 12, 10, &a, &e, &b, &c);
    try expectMatrixClose(scalarMatAddEsmul3Product(12, 10, &a, &e, &b, &c), left_scaled, 12, 1.0e-13);

    var right_scaled = rows.Mat.zero(12);
    matrix_12x10.semulAddProductKnownNonzeroInto(&right_scaled, 12, 10, &a, &e, &b);
    try expectMatrixClose(scalarSemulAddProduct(12, 10, &a, &e, &b), right_scaled, 12, 1.0e-13);

    var two_sided = rows.Mat.zero(12);
    matrix_12x10.esmulSemulAddProductKnownNonzeroInto(&two_sided, 12, 10, &e, &a, &b);
    try expectMatrixClose(scalarEsmulSemulAddProduct(12, 10, &e, &a, &b), two_sided, 12, 1.0e-13);

    var self_two_sided = rows.Mat.zero(12);
    matrix_12x10.esmulSemulSelfAddProductKnownNonzeroInto(&self_two_sided, 12, 10, &e, &a);
    try expectMatrixClose(scalarEsmulSemulSelfAddProduct(12, 10, &e, &a), self_two_sided, 12, 1.0e-13);
}

test "retained product diagonal add writers keep generic active-size formulas" {
    var a = rows.Mat.zero(6);
    var b = rows.Mat.zero(6);
    var c = rows.Mat.zero(6);
    var e = rows.Vec.zero(6);
    fillPattern(&a, 6, 0.03, 0.07);
    fillPattern(&b, 6, 0.11, -0.02);
    fillPattern(&c, 6, -0.04, 0.09);
    fillVector(&e, 6, 0.5, 0.125);

    var left_scaled = rows.Mat.zero(6);
    matrix_12x10.matAddEsmul3ProductKnownNonzeroInto(&left_scaled, 6, 4, &a, &e, &b, &c);
    try expectMatrixClose(scalarMatAddEsmul3Product(6, 4, &a, &e, &b, &c), left_scaled, 6, 1.0e-13);

    var right_scaled = rows.Mat.zero(6);
    matrix_12x10.semulAddProductKnownNonzeroInto(&right_scaled, 6, 4, &a, &e, &b);
    try expectMatrixClose(scalarSemulAddProduct(6, 4, &a, &e, &b), right_scaled, 6, 1.0e-13);

    var two_sided = rows.Mat.zero(6);
    matrix_12x10.esmulSemulAddProductKnownNonzeroInto(&two_sided, 6, 4, &e, &a, &b);
    try expectMatrixClose(scalarEsmulSemulAddProduct(6, 4, &e, &a, &b), two_sided, 6, 1.0e-13);

    var self_two_sided = rows.Mat.zero(6);
    matrix_12x10.esmulSemulSelfAddProductKnownNonzeroInto(&self_two_sided, 6, 4, &e, &a);
    try expectMatrixClose(scalarEsmulSemulSelfAddProduct(6, 4, &e, &a), self_two_sided, 6, 1.0e-13);
}

test "smulAddSemul3 generic path matches retained and skipped scalar references" {
    var a = rows.Mat.zero(6);
    var c = rows.Mat.zero(6);
    var e = rows.Vec.zero(6);
    fillPattern(&a, 6, 0.03, 0.07);
    fillPattern(&c, 6, -0.04, 0.09);
    fillVector(&e, 6, 0.5, 0.125);

    const retained = matrix_12x10.smulAddSemul3(6, 4, 1.0e-30, &a, &e, &c);
    const retained_expected = scalarSmulAddSemul3(6, 4, &a, &e, &c);
    try expectMatrixClose(retained_expected, retained, 6, 1.0e-13);

    const skipped = matrix_12x10.smulAddSemul3(6, 4, 1.0e9, &a, &e, &c);
    const skipped_expected = scalarSemulAdd(6, &a, &e, &c);
    try expectMatrixClose(skipped_expected, skipped, 6, 1.0e-13);
}

test "smulAddSemul3 fixed path matches retained and skipped scalar references" {
    var a = rows.Mat.zero(12);
    var c = rows.Mat.zero(12);
    var e = rows.Vec.zero(12);
    fillPattern(&a, 12, 0.017, 0.031);
    fillPattern(&c, 12, 0.019, -0.027);
    fillVector(&e, 12, 0.5, 0.0625);

    const retained = matrix_12x10.smulAddSemul3(12, 10, 1.0e-30, &a, &e, &c);
    const retained_expected = scalarSmulAddSemul3(12, 10, &a, &e, &c);
    try expectMatrixClose(retained_expected, retained, 12, 1.0e-13);

    const skipped = matrix_12x10.smulAddSemul3(12, 10, 1.0e9, &a, &e, &c);
    const skipped_expected = scalarSemulAdd(12, &a, &e, &c);
    try expectMatrixClose(skipped_expected, skipped, 12, 1.0e-13);
}

test "smulAddSemul3KnownRightTraceInto writes caller-owned output" {
    var a = rows.Mat.zero(12);
    var c = rows.Mat.zero(12);
    var e = rows.Vec.zero(12);
    fillPattern(&a, 12, 0.017, 0.031);
    fillPattern(&c, 12, 0.019, -0.027);
    fillVector(&e, 12, 0.5, 0.0625);

    const trace_c = scalarGaussianTrace(12, 10, &c);
    var retained = rows.Mat.zero(12);
    matrix_12x10.smulAddSemul3KnownRightTraceInto(&retained, 12, 10, 1.0e-30, &a, &e, &c, trace_c);
    try expectMatrixClose(scalarSmulAddSemul3(12, 10, &a, &e, &c), retained, 12, 1.0e-13);

    var skipped = rows.Mat.zero(12);
    matrix_12x10.smulAddSemul3KnownRightTraceInto(&skipped, 12, 10, 1.0e9, &a, &e, &c, trace_c);
    try expectMatrixClose(scalarSemulAdd(12, &a, &e, &c), skipped, 12, 1.0e-13);
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

fn fillQseriesInputs(a: *rows.Mat, b: *rows.Mat, n: usize, n_gauss: usize) void {
    // fillQseriesInputs ------------------------------------------------------------------------------------- |
    // Build small deterministic matrices whose AB Gaussian block is well below singularity but above the      |
    // q-series trace gate from LABOS `matrix.zig` threshold_q = 1.0e-3.                                       |
    // --------------------------------------------------------------------------------------------------------|
    a.* = rows.Mat.zero(n);
    b.* = rows.Mat.zero(n);

    for (0..n_gauss) |stream_index| {
        a.set(stream_index, stream_index, 1.0);
    }

    for (n_gauss..n) |row| {
        for (0..n_gauss) |col| {
            const row_term = @as(f64, @floatFromInt(row - n_gauss + 1)) * 0.002;
            const col_term = @as(f64, @floatFromInt(col + 1)) * 0.0004;
            a.set(row, col, row_term + col_term);
        }
    }

    for (0..n_gauss) |row| {
        for (0..n) |col| {
            const diagonal: f64 = if (row == col) 0.02 else 0.0;
            const row_term = @as(f64, @floatFromInt(row + 1)) * 0.0007;
            const col_term = @as(f64, @floatFromInt(col + 1)) * 0.0003;
            b.set(row, col, diagonal + row_term + col_term);
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

fn scalarMatAddEsmul3(
    n: usize,
    a: *const rows.Mat,
    e: *const rows.Vec,
    b: *const rows.Mat,
    c: *const rows.Mat,
) rows.Mat {
    // scalarMatAddEsmul3 ------------------------------------------------------------------------------------ |
    // Independent test reference for A + diag(e) * B + C.                                                     |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            result.set(row, col, (a.get(row, col) + e.get(row) * b.get(row, col)) + c.get(row, col));
        }
    }
    return result;
}

fn scalarMatAddEsmul(n: usize, a: *const rows.Mat, e: *const rows.Vec, b: *const rows.Mat) rows.Mat {
    // scalarMatAddEsmul ------------------------------------------------------------------------------------- |
    // Independent test reference for A + diag(e) * B.                                                         |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            result.set(row, col, a.get(row, col) + e.get(row) * b.get(row, col));
        }
    }
    return result;
}

fn scalarSemulAdd(n: usize, a: *const rows.Mat, e: *const rows.Vec, b: *const rows.Mat) rows.Mat {
    // scalarSemulAdd ---------------------------------------------------------------------------------------- |
    // Independent test reference for A * diag(e) + B.                                                         |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            result.set(row, col, a.get(row, col) * e.get(col) + b.get(row, col));
        }
    }
    return result;
}

fn scalarEsmulSemul(n: usize, e: *const rows.Vec, a: *const rows.Mat, b: *const rows.Mat) rows.Mat {
    // scalarEsmulSemul -------------------------------------------------------------------------------------- |
    // Independent test reference for diag(e) * A + B * diag(e).                                               |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            result.set(row, col, e.get(row) * a.get(row, col) + b.get(row, col) * e.get(col));
        }
    }
    return result;
}

fn scalarEsmulSemulSelf(n: usize, e: *const rows.Vec, a: *const rows.Mat) rows.Mat {
    // scalarEsmulSemulSelf ---------------------------------------------------------------------------------- |
    // Independent test reference for A * (e[row] + e[col]).                                                   |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            result.set(row, col, a.get(row, col) * (e.get(row) + e.get(col)));
        }
    }
    return result;
}

fn scalarEsmulSemulAdd(
    n: usize,
    e: *const rows.Vec,
    a: *const rows.Mat,
    b: *const rows.Mat,
    c: *const rows.Mat,
) rows.Mat {
    // scalarEsmulSemulAdd ----------------------------------------------------------------------------------- |
    // Independent test reference for diag(e) * A + B * diag(e) + C.                                           |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            const value = (e.get(row) * a.get(row, col) + b.get(row, col) * e.get(col)) + c.get(row, col);
            result.set(row, col, value);
        }
    }
    return result;
}

fn scalarMatAddEsmul3Product(
    n: usize,
    n_gauss: usize,
    a: *const rows.Mat,
    e: *const rows.Vec,
    b: *const rows.Mat,
    c: *const rows.Mat,
) rows.Mat {
    // scalarMatAddEsmul3Product ----------------------------------------------------------------------------- |
    // Independent test reference for A + diag(e) * B + C*B over Gaussian streams.                             |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            var product: f64 = 0.0;
            for (0..n_gauss) |gauss_index| {
                product += c.get(row, gauss_index) * b.get(gauss_index, col);
            }
            result.set(row, col, (a.get(row, col) + e.get(row) * b.get(row, col)) + product);
        }
    }
    return result;
}

fn scalarEsmulSemulAddProduct(
    n: usize,
    n_gauss: usize,
    e: *const rows.Vec,
    a: *const rows.Mat,
    b: *const rows.Mat,
) rows.Mat {
    // scalarEsmulSemulAddProduct ---------------------------------------------------------------------------- |
    // Independent test reference for diag(e) * A + B * diag(e) + B*A over Gaussian streams.                   |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            var product: f64 = 0.0;
            for (0..n_gauss) |gauss_index| {
                product += b.get(row, gauss_index) * a.get(gauss_index, col);
            }
            const base = e.get(row) * a.get(row, col) + b.get(row, col) * e.get(col);
            result.set(row, col, base + product);
        }
    }
    return result;
}

fn scalarEsmulSemulSelfAddProduct(
    n: usize,
    n_gauss: usize,
    e: *const rows.Vec,
    a: *const rows.Mat,
) rows.Mat {
    // scalarEsmulSemulSelfAddProduct ------------------------------------------------------------------------ |
    // Independent test reference for A * (e[row] + e[col]) + A*A over Gaussian streams.                       |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            var product: f64 = 0.0;
            for (0..n_gauss) |gauss_index| {
                product += a.get(row, gauss_index) * a.get(gauss_index, col);
            }
            result.set(row, col, a.get(row, col) * (e.get(row) + e.get(col)) + product);
        }
    }
    return result;
}

fn scalarSemulAddProduct(
    n: usize,
    n_gauss: usize,
    a: *const rows.Mat,
    e: *const rows.Vec,
    b: *const rows.Mat,
) rows.Mat {
    // scalarSemulAddProduct --------------------------------------------------------------------------------- |
    // Independent test reference for A * diag(e) + A*B over Gaussian streams.                                 |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            var product: f64 = 0.0;
            for (0..n_gauss) |gauss_index| {
                product += a.get(row, gauss_index) * b.get(gauss_index, col);
            }
            result.set(row, col, a.get(row, col) * e.get(col) + product);
        }
    }
    return result;
}

fn scalarSmulAddSemul3(
    n: usize,
    n_gauss: usize,
    a: *const rows.Mat,
    e: *const rows.Vec,
    c: *const rows.Mat,
) rows.Mat {
    // scalarSmulAddSemul3 ----------------------------------------------------------------------------------- |
    // Independent test reference for C + A * diag(e) + A*C over Gaussian streams.                             |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            var product: f64 = 0.0;
            for (0..n_gauss) |gauss_index| {
                product += a.get(row, gauss_index) * c.get(gauss_index, col);
            }
            result.set(row, col, (c.get(row, col) + a.get(row, col) * e.get(col)) + product);
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

fn scalarQseriesFromProduct(n: usize, n_gauss: usize, ab_product: *const rows.Mat) rows.Mat {
    // scalarQseriesFromProduct ------------------------------------------------------------------------------ |
    // Independent test reference for Q(AB). It uses Gauss-Jordan inversion instead of the production LU       |
    // factorization so the tests check values through a different algorithm.                                  |
    // --------------------------------------------------------------------------------------------------------|
    const test_threshold_q: f64 = 1.0e-3;
    const test_lu_diagonal_floor: f64 = 1.0e-30;

    var trace: f64 = 0.0;
    for (0..n_gauss) |index| {
        trace += ab_product.get(index, index);
    }
    if (@abs(trace) < test_threshold_q) return ab_product.*;

    var matrix: [rows.max_gauss * rows.max_gauss]f64 = .{0.0} ** (rows.max_gauss * rows.max_gauss);
    var inverse: [rows.max_gauss * rows.max_gauss]f64 = .{0.0} ** (rows.max_gauss * rows.max_gauss);
    for (0..n_gauss) |row| {
        for (0..n_gauss) |col| {
            const delta: f64 = if (row == col) 1.0 else 0.0;
            matrix[row * n_gauss + col] = delta - ab_product.get(row, col);
            inverse[row * n_gauss + col] = delta;
        }
    }

    for (0..n_gauss) |col| {
        var pivot_row = col;
        var pivot_abs = @abs(matrix[col * n_gauss + col]);
        for (col + 1..n_gauss) |candidate_row| {
            const candidate_abs = @abs(matrix[candidate_row * n_gauss + col]);
            if (candidate_abs > pivot_abs) {
                pivot_abs = candidate_abs;
                pivot_row = candidate_row;
            }
        }

        if (pivot_abs < test_lu_diagonal_floor) return ab_product.*;

        if (pivot_row != col) {
            swapScalarRows(&matrix, n_gauss, col, pivot_row);
            swapScalarRows(&inverse, n_gauss, col, pivot_row);
        }

        const pivot = matrix[col * n_gauss + col];
        for (0..n_gauss) |entry_col| {
            matrix[col * n_gauss + entry_col] /= pivot;
            inverse[col * n_gauss + entry_col] /= pivot;
        }

        for (0..n_gauss) |target_row| {
            if (target_row == col) continue;

            const factor = matrix[target_row * n_gauss + col];
            for (0..n_gauss) |entry_col| {
                matrix[target_row * n_gauss + entry_col] -= factor * matrix[col * n_gauss + entry_col];
                inverse[target_row * n_gauss + entry_col] -= factor * inverse[col * n_gauss + entry_col];
            }
        }
    }

    return scalarQseriesBlocks(n, n_gauss, ab_product, &inverse);
}

fn swapScalarRows(matrix: *[rows.max_gauss * rows.max_gauss]f64, n_gauss: usize, lhs: usize, rhs: usize) void {
    // swapScalarRows ---------------------------------------------------------------------------------------- |
    // Swap two active rows in a flat n_gauss by n_gauss test matrix.                                          |
    // --------------------------------------------------------------------------------------------------------|
    for (0..n_gauss) |col| {
        const lhs_index = lhs * n_gauss + col;
        const rhs_index = rhs * n_gauss + col;
        const tmp = matrix[lhs_index];
        matrix[lhs_index] = matrix[rhs_index];
        matrix[rhs_index] = tmp;
    }
}

fn scalarQseriesBlocks(
    n: usize,
    n_gauss: usize,
    ab_product: *const rows.Mat,
    inverse: *const [rows.max_gauss * rows.max_gauss]f64,
) rows.Mat {
    // scalarQseriesBlocks ----------------------------------------------------------------------------------- |
    // Fill Q_gg, Q_gx, Q_xg, and Q_xx from the independent inverse reference.                                 |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);

    for (0..n_gauss) |row| {
        for (0..n_gauss) |col| {
            const delta: f64 = if (row == col) 1.0 else 0.0;
            result.set(row, col, inverse[row * n_gauss + col] - delta);
        }
    }

    for (0..n_gauss) |row| {
        for (n_gauss..n) |col| {
            var sum: f64 = 0.0;
            for (0..n_gauss) |inner| {
                sum += inverse[row * n_gauss + inner] * ab_product.get(inner, col);
            }
            result.set(row, col, sum);
        }
    }

    for (n_gauss..n) |row| {
        for (0..n_gauss) |col| {
            var sum: f64 = 0.0;
            for (0..n_gauss) |inner| {
                sum += ab_product.get(row, inner) * inverse[inner * n_gauss + col];
            }
            result.set(row, col, sum);
        }
    }

    for (n_gauss..n) |row| {
        for (n_gauss..n) |col| {
            var sum = ab_product.get(row, col);
            for (0..n_gauss) |inner| {
                sum += result.get(row, inner) * ab_product.get(inner, col);
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
