const std = @import("std");

pub const Error = error{
    ShapeMismatch,
};

pub fn sampleLinearClamped(x: []const f64, y: []const f64, target_x: f64) Error!f64 {
    if (x.len != y.len) return error.ShapeMismatch;
    if (x.len == 0) return error.ShapeMismatch;
    return sampleLinearClampedAssumeValid(x, y, target_x);
}

pub fn sampleLinearClampedAssumeValid(x: []const f64, y: []const f64, target_x: f64) f64 {
    std.debug.assert(x.len == y.len);
    std.debug.assert(x.len != 0);

    if (x.len == 1) return y[0];
    if (target_x <= x[0]) return y[0];
    if (target_x >= x[x.len - 1]) return y[y.len - 1];
    for (x[0 .. x.len - 1], x[1..], y[0 .. y.len - 1], y[1..]) |left_x, right_x, left_y, right_y| {
        if (target_x < left_x or target_x > right_x) continue;
        const alpha = (target_x - left_x) / (right_x - left_x);
        return (1.0 - alpha) * left_y + alpha * right_y;
    }
    return y[y.len - 1];
}

test "sampling clamps linearly on sparse wavelength nodes" {
    const wavelengths = [_]f64{ 760.0, 760.2, 760.4 };
    const values = [_]f64{ 1.0, 3.0, 5.0 };

    try std.testing.expectApproxEqRel(
        @as(f64, 2.0),
        try sampleLinearClamped(&wavelengths, &values, 760.1),
        1.0e-12,
    );
    try std.testing.expectEqual(@as(f64, 1.0), try sampleLinearClamped(&wavelengths, &values, 759.9));
    try std.testing.expectEqual(@as(f64, 5.0), try sampleLinearClamped(&wavelengths, &values, 760.5));
}
