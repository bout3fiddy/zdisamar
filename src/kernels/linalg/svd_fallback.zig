//! Purpose:
//!   Provide damped inverse and solve fallbacks for tiny dense systems.
//!
//! Physics:
//!   Applies diagonal regularization and Gaussian elimination when a direct factorization is too fragile.
//!
//! Vendor:
//!   `damped inverse / solve fallback`
//!
//! Design:
//!   The fallback is intentionally small and explicit so singularity handling stays predictable.
//!
//! Invariants:
//!   Damping must be finite and non-negative; workspace sizes must match the augmented-system layout.
//!
//! Validation:
//!   Tests cover regularization of nearly singular 2x2 systems and damped solve behavior.

const std = @import("std");
const dense = @import("small_dense.zig");

pub const Error = error{
    InvalidDamping,
    ShapeMismatch,
    SingularMatrix,
};

/// Purpose:
///   Compute the inverse of a damped 2x2 matrix.
///
/// Physics:
///   Adds diagonal regularization before inverting the matrix analytically.
///
/// Vendor:
///   `damped 2x2 inverse`
pub fn dampedInverse2x2(matrix: [2][2]f64, damping: f64) Error![2][2]f64 {
    if (!std.math.isFinite(damping) or damping < 0.0) return error.InvalidDamping;
    const a = matrix[0][0] + damping;
    const b = matrix[0][1];
    const c = matrix[1][0];
    const d = matrix[1][1] + damping;
    const det = a * d - b * c;
    if (@abs(det) <= 1.0e-12) return error.SingularMatrix;

    return .{
        .{ d / det, -b / det },
        .{ -c / det, a / det },
    };
}

/// Purpose:
///   Solve a small dense linear system with diagonal damping and partial pivoting.
///
/// Physics:
///   Regularizes near-singular systems before elimination to stabilize retrieval fallbacks.
///
/// Vendor:
///   `damped dense solve`
///
/// Assumptions:
///   `workspace` stores the augmented matrix with `dimension * (dimension + 1)` entries.
pub fn dampedSolve(
    matrix: []const f64,
    dimension: usize,
    rhs: []const f64,
    damping: f64,
    out: []f64,
    workspace: []f64,
) Error!void {
    if (!std.math.isFinite(damping) or damping < 0.0) return error.InvalidDamping;
    if (matrix.len != dimension * dimension or rhs.len != dimension or out.len != dimension or
        workspace.len != dimension * (dimension + 1))
    {
        return error.ShapeMismatch;
    }
    const augmented = workspace;

    for (0..dimension) |row| {
        for (0..dimension) |column| {
            augmented[row * (dimension + 1) + column] = matrix[dense.index(row, column, dimension)] +
                (if (row == column) damping else 0.0);
        }
        augmented[row * (dimension + 1) + dimension] = rhs[row];
    }

    for (0..dimension) |pivot| {
        var best_row = pivot;
        var best_value = @abs(augmented[pivot * (dimension + 1) + pivot]);
        for (pivot + 1..dimension) |row| {
            const candidate = @abs(augmented[row * (dimension + 1) + pivot]);
            if (candidate > best_value) {
                best_row = row;
                best_value = candidate;
            }
        }
        if (best_value <= 1.0e-12) return error.SingularMatrix;

        if (best_row != pivot) {
            for (0..dimension + 1) |column| {
                const left_index = pivot * (dimension + 1) + column;
                const right_index = best_row * (dimension + 1) + column;
                const tmp = augmented[left_index];
                augmented[left_index] = augmented[right_index];
                augmented[right_index] = tmp;
            }
        }

        const pivot_value = augmented[pivot * (dimension + 1) + pivot];
        for (pivot..dimension + 1) |column| {
            augmented[pivot * (dimension + 1) + column] /= pivot_value;
        }

        for (0..dimension) |row| {
            if (row == pivot) continue;
            const factor = augmented[row * (dimension + 1) + pivot];
            for (pivot..dimension + 1) |column| {
                augmented[row * (dimension + 1) + column] -= factor *
                    augmented[pivot * (dimension + 1) + column];
            }
        }
    }

    for (0..dimension) |row| {
        out[row] = augmented[row * (dimension + 1) + dimension];
    }
}

test "damped inverse regularizes a nearly singular 2x2 matrix" {
    const inverse = try dampedInverse2x2(.{
        .{ 1.0, 0.99 },
        .{ 0.99, 0.98 },
    }, 0.1);
    try std.testing.expect(inverse[0][0] > 0.0);
    try std.testing.expect(inverse[1][1] > 0.0);
}

test "damped solve regularizes small singular systems" {
    var out = [_]f64{ 0.0, 0.0 };
    var workspace = [_]f64{0.0} ** 6;
    try dampedSolve(&.{
        1.0,  0.99,
        0.99, 0.98,
    }, 2, &.{ 1.0, 1.0 }, 0.1, &out, &workspace);
    try std.testing.expect(out[0] != 0.0);
    try std.testing.expect(out[1] != 0.0);
}
