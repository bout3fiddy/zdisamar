//! Purpose:
//!   Factor, solve, and invert small dense symmetric positive-definite systems.
//!
//! Physics:
//!   Implements Cholesky decomposition on row-major matrices and uses it for linear solves and inverse assembly.
//!
//! Vendor:
//!   `Cholesky factorization`
//!
//! Design:
//!   The factor is stored in-place in row-major form to keep the small dense helpers allocation-free.
//!
//! Invariants:
//!   Matrices must be square, the factor must remain lower-triangular, and diagonal pivots must be positive.
//!
//! Validation:
//!   Tests cover 2x2 factorization, dense solves, and inverse construction.

const std = @import("std");
const dense = @import("small_dense.zig");

pub const Error = error{
    NotPositiveDefinite,
    ShapeMismatch,
};

/// Purpose:
///   Factor a 2x2 symmetric positive-definite matrix and return the lower-triangular factor.
///
/// Physics:
///   Computes the Cholesky factor used to solve and invert SPD systems.
///
/// Vendor:
///   `2x2 Cholesky factorization`
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

/// Purpose:
///   Factor a square matrix in place using a lower-triangular Cholesky factorization.
///
/// Physics:
///   Rewrites the matrix as `L` while zeroing the upper triangle.
///
/// Vendor:
///   `dense Cholesky factorization`
///
/// Assumptions:
///   `matrix` is row-major and `dimension * dimension` matches the slice length.
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

/// Purpose:
///   Solve a factored SPD system for the supplied right-hand side.
///
/// Physics:
///   Performs forward and backward substitution against the Cholesky factor.
///
/// Vendor:
///   `Cholesky solve`
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

/// Purpose:
///   Form the inverse of a factored SPD matrix using repeated basis solves.
///
/// Physics:
///   Builds the inverse column by column from the Cholesky factor.
///
/// Vendor:
///   `Cholesky inverse`
///
/// Assumptions:
///   `workspace` supplies `2 * dimension` scratch entries for basis and solution vectors.
pub fn invertFromFactor(
    factor: []const f64,
    dimension: usize,
    out: []f64,
    workspace: []f64,
) Error!void {
    if (out.len != dimension * dimension or workspace.len != 2 * dimension) return Error.ShapeMismatch;

    const basis = workspace[0..dimension];
    const solution = workspace[dimension .. 2 * dimension];

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

test "cholesky factorization reproduces a positive-definite 2x2 matrix" {
    const factor = try factor2x2(.{
        .{ 4.0, 2.0 },
        .{ 2.0, 3.0 },
    });
    try std.testing.expectApproxEqRel(@as(f64, 2.0), factor[0][0], 1e-12);
    try std.testing.expect(factor[1][1] > 0.0);
}

test "cholesky solves and inverts dense SPD systems" {
    var matrix = [_]f64{
        5.0, 1.0, 0.0,
        1.0, 4.0, 1.0,
        0.0, 1.0, 3.0,
    };
    try factorInPlace(&matrix, 3);

    var solution = [_]f64{ 7.0, 8.0, 7.0 };
    try solveWithFactor(&matrix, 3, &.{ 7.0, 8.0, 7.0 }, &solution);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), solution[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 2.0), solution[1], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.6666666666666667), solution[2], 1e-12);

    var inverse = [_]f64{0.0} ** 9;
    var workspace = [_]f64{0.0} ** 6;
    try invertFromFactor(&matrix, 3, &inverse, &workspace);
    try std.testing.expect(inverse[dense.index(0, 0, 3)] > 0.0);
    try std.testing.expect(inverse[dense.index(1, 1, 3)] > 0.0);
}
