pub const Error = error{
    InvalidDamping,
    SingularMatrix,
};

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

test "damped inverse regularizes a nearly singular 2x2 matrix" {
    const inverse = try dampedInverse2x2(.{
        .{ 1.0, 0.99 },
        .{ 0.99, 0.98 },
    }, 0.1);
    try std.testing.expect(inverse[0][0] > 0.0);
    try std.testing.expect(inverse[1][1] > 0.0);
}

test "damped inverse rejects singular determinants and invalid damping" {
    try std.testing.expectError(error.InvalidDamping, dampedInverse2x2(.{
        .{ 1.0, 0.0 },
        .{ 0.0, 1.0 },
    }, -0.1));
    try std.testing.expectError(error.SingularMatrix, dampedInverse2x2(.{
        .{ 0.0, 0.0 },
        .{ 0.0, 0.0 },
    }, 0.0));
}

const std = @import("std");
