const std = @import("std");

pub const Error = error{
    ShapeMismatch,
};

pub fn dot(lhs: []const f64, rhs: []const f64) Error!f64 {
    if (lhs.len != rhs.len) return Error.ShapeMismatch;

    var acc: f64 = 0.0;
    for (lhs, rhs) |l, r| {
        acc += l * r;
    }
    return acc;
}

pub fn axpy(alpha: f64, x: []const f64, y: []f64) Error!void {
    if (x.len != y.len) return Error.ShapeMismatch;
    for (x, y) |xv, *yv| {
        yv.* += alpha * xv;
    }
}

pub fn normL2(x: []const f64) f64 {
    var acc: f64 = 0.0;
    for (x) |value| {
        acc += value * value;
    }
    return std.math.sqrt(acc);
}

test "vector ops support dot, axpy, and l2 norm on small dense vectors" {
    const lhs = [_]f64{ 1.0, 2.0, 3.0 };
    const rhs = [_]f64{ 4.0, 5.0, 6.0 };
    var y = [_]f64{ 10.0, 20.0, 30.0 };

    const d = try dot(&lhs, &rhs);
    try std.testing.expectApproxEqRel(@as(f64, 32.0), d, 1e-12);

    try axpy(0.5, &lhs, &y);
    try std.testing.expectApproxEqRel(@as(f64, 10.5), y[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 21.0), y[1], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 31.5), y[2], 1e-12);

    const n = normL2(&rhs);
    try std.testing.expectApproxEqRel(@as(f64, std.math.sqrt(77.0)), n, 1e-12);
}
