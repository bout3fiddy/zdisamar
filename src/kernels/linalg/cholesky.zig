pub const Error = error{
    NotPositiveDefinite,
};

pub fn factor2x2(matrix: [2][2]f64) Error![2][2]f64 {
    if (matrix[0][0] <= 0.0) return Error.NotPositiveDefinite;
    const l00 = std.math.sqrt(matrix[0][0]);
    const l10 = matrix[1][0] / l00;
    const diag = matrix[1][1] - l10 * l10;
    if (diag <= 0.0) return Error.NotPositiveDefinite;

    return .{
        .{ l00, 0.0 },
        .{ l10, std.math.sqrt(diag) },
    };
}

test "cholesky factorization reproduces a positive-definite 2x2 matrix" {
    const factor = try factor2x2(.{
        .{ 4.0, 2.0 },
        .{ 2.0, 3.0 },
    });
    try std.testing.expectApproxEqRel(@as(f64, 2.0), factor[0][0], 1e-12);
    try std.testing.expect(factor[1][1] > 0.0);
}

const std = @import("std");
