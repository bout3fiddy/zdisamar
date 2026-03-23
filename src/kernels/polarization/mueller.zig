//! Purpose:
//!   Apply Mueller matrices to Stokes vectors.
//!
//! Physics:
//!   Transforms a polarized state through a 4x4 linear optical operator.
//!
//! Vendor:
//!   `Mueller matrix application`
//!
//! Design:
//!   The matrix multiplication is explicit so the component ordering stays obvious.
//!
//! Invariants:
//!   The matrix is always 4x4 and the input/output state order is `I, Q, U, V`.
//!
//! Validation:
//!   Tests cover a simple basis swap through the matrix.

const StokesVector = @import("stokes.zig").StokesVector;

/// Purpose:
///   Represent a Mueller matrix in row-major form.
pub const Matrix = [4][4]f64;

/// Purpose:
///   Apply a Mueller matrix to a Stokes vector.
///
/// Physics:
///   Computes the transformed polarized state after an optical element.
///
/// Vendor:
///   `Mueller transform`
pub fn apply(matrix: Matrix, vector: StokesVector) StokesVector {
    const input = [_]f64{ vector.i, vector.q, vector.u, vector.v };
    var output = [_]f64{ 0.0, 0.0, 0.0, 0.0 };

    for (matrix, 0..) |row, row_index| {
        for (row, 0..) |value, column_index| {
            output[row_index] += value * input[column_index];
        }
    }

    return .{
        .i = output[0],
        .q = output[1],
        .u = output[2],
        .v = output[3],
    };
}

test "mueller matrix application rotates stokes state" {
    const matrix: Matrix = .{
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };
    const out = apply(matrix, .{ .i = 10.0, .q = 2.0, .u = 3.0, .v = 1.0 });
    try std.testing.expectEqual(@as(f64, 10.0), out.i);
    try std.testing.expectEqual(@as(f64, 3.0), out.q);
    try std.testing.expectEqual(@as(f64, 2.0), out.u);
}

const std = @import("std");
