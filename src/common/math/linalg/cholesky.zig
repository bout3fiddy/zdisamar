const std = @import("std");
const dense = @import("small_dense.zig");

pub const Error = error{
    NotPositiveDefinite,
    ShapeMismatch,
};

pub fn factor2x2(matrix: [2][2]f64) Error![2][2]f64 {
    var flat = [_]f64{
        matrix[0][0], matrix[0][1],
        matrix[1][0], matrix[1][1],
    };
    try factorInPlace(&flat, 2);
    return .{
        .{ flat[0], flat[1] },
        .{ flat[2], flat[3] },
    };
}

pub fn factorInPlace(matrix: []f64, dimension: usize) Error!void {
    if (matrix.len != dimension * dimension) return Error.ShapeMismatch;

    for (0..dimension) |row| {
        for (0..row + 1) |column| {
            var sum = matrix[dense.index(row, column, dimension)];
            var inner: usize = 0;
            while (inner < column) : (inner += 1) {
                sum -= matrix[dense.index(row, inner, dimension)] *
                    matrix[dense.index(column, inner, dimension)];
            }

            if (row == column) {
                if (sum <= 0.0 or !std.math.isFinite(sum)) return Error.NotPositiveDefinite;
                matrix[dense.index(row, column, dimension)] = std.math.sqrt(sum);
            } else {
                matrix[dense.index(row, column, dimension)] = sum /
                    matrix[dense.index(column, column, dimension)];
            }
        }

        for (row + 1..dimension) |column| {
            matrix[dense.index(row, column, dimension)] = 0.0;
        }
    }
}

pub fn solveWithFactor(
    factor: []const f64,
    dimension: usize,
    rhs: []const f64,
    out: []f64,
) Error!void {
    if (factor.len != dimension * dimension or rhs.len != dimension or out.len != dimension) {
        return Error.ShapeMismatch;
    }

    var y_index: usize = 0;
    while (y_index < dimension) : (y_index += 1) {
        var value = rhs[y_index];
        var inner: usize = 0;
        while (inner < y_index) : (inner += 1) {
            value -= factor[dense.index(y_index, inner, dimension)] * out[inner];
        }
        out[y_index] = value / factor[dense.index(y_index, y_index, dimension)];
    }

    var x_index: usize = dimension;
    while (x_index > 0) {
        x_index -= 1;
        var value = out[x_index];
        var inner = x_index + 1;
        while (inner < dimension) : (inner += 1) {
            value -= factor[dense.index(inner, x_index, dimension)] * out[inner];
        }
        out[x_index] = value / factor[dense.index(x_index, x_index, dimension)];
    }
}

pub fn invertFromFactor(
    factor: []const f64,
    dimension: usize,
    out: []f64,
    storage: []f64,
) Error!void {
    if (out.len != dimension * dimension or storage.len != 2 * dimension) return Error.ShapeMismatch;

    const basis = storage[0..dimension];
    const solution = storage[dimension .. 2 * dimension];

    @memset(out, 0.0);
    for (0..dimension) |column| {
        @memset(basis, 0.0);
        basis[column] = 1.0;
        @memcpy(solution, basis);
        try solveWithFactor(factor, dimension, basis, solution);
        for (0..dimension) |row| {
            out[dense.index(row, column, dimension)] = solution[row];
        }
    }
}
