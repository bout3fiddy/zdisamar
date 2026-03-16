pub const Error = error{
    SingularMatrix,
};

pub fn leastSquares2x2(matrix: [2][2]f64, rhs: [2]f64) Error![2]f64 {
    const a0_norm = std.math.sqrt(matrix[0][0] * matrix[0][0] + matrix[1][0] * matrix[1][0]);
    if (a0_norm <= 1.0e-12) return error.SingularMatrix;
    const q0 = [2]f64{ matrix[0][0] / a0_norm, matrix[1][0] / a0_norm };
    const r01 = q0[0] * matrix[0][1] + q0[1] * matrix[1][1];
    const column_1 = [2]f64{ matrix[0][1] - q0[0] * r01, matrix[1][1] - q0[1] * r01 };
    const a1_norm = std.math.sqrt(column_1[0] * column_1[0] + column_1[1] * column_1[1]);
    if (a1_norm <= 1.0e-12) return error.SingularMatrix;
    const q1 = [2]f64{ column_1[0] / a1_norm, column_1[1] / a1_norm };

    const qt_b = [2]f64{
        q0[0] * rhs[0] + q0[1] * rhs[1],
        q1[0] * rhs[0] + q1[1] * rhs[1],
    };

    return .{
        (qt_b[0] - r01 * (qt_b[1] / a1_norm)) / a0_norm,
        qt_b[1] / a1_norm,
    };
}

test "qr least squares solves a full-rank 2x2 system" {
    const solution = try leastSquares2x2(.{
        .{ 2.0, 1.0 },
        .{ 1.0, 3.0 },
    }, .{ 1.0, 2.0 });
    try std.testing.expectApproxEqRel(@as(f64, 0.2), solution[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.6), solution[1], 1e-12);
}

test "qr least squares rejects rank-deficient systems" {
    try std.testing.expectError(error.SingularMatrix, leastSquares2x2(.{
        .{ 1.0, 2.0 },
        .{ 2.0, 4.0 },
    }, .{ 1.0, 2.0 }));
}

const std = @import("std");
