pub fn applyDiagonal(left: []const f64, jacobian: []const f64, right: []const f64, output: []f64) !void {
    if (left.len != jacobian.len or right.len != jacobian.len or output.len != jacobian.len) {
        return error.ShapeMismatch;
    }

    for (left, jacobian, right, output) |lhs, value, rhs, *slot| {
        slot.* = lhs * value * rhs;
    }
}

test "jacobian chain applies diagonal left and right scales" {
    const left = [_]f64{ 1.0, 2.0 };
    const jacobian = [_]f64{ 3.0, 4.0 };
    const right = [_]f64{ 5.0, 6.0 };
    var out: [2]f64 = undefined;
    try applyDiagonal(&left, &jacobian, &right, &out);
    try std.testing.expectEqual(@as(f64, 15.0), out[0]);
    try std.testing.expectEqual(@as(f64, 48.0), out[1]);
}

const std = @import("std");
