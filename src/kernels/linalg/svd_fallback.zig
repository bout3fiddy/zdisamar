pub fn dampedInverse2x2(matrix: [2][2]f64, damping: f64) [2][2]f64 {
    const a = matrix[0][0] + damping;
    const b = matrix[0][1];
    const c = matrix[1][0];
    const d = matrix[1][1] + damping;
    const det = a * d - b * c;

    return .{
        .{ d / det, -b / det },
        .{ -c / det, a / det },
    };
}

test "damped inverse regularizes a nearly singular 2x2 matrix" {
    const inverse = dampedInverse2x2(.{
        .{ 1.0, 0.99 },
        .{ 0.99, 0.98 },
    }, 0.1);
    try std.testing.expect(inverse[0][0] > 0.0);
    try std.testing.expect(inverse[1][1] > 0.0);
}

const std = @import("std");
