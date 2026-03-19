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

pub fn copy(src: []const f64, dst: []f64) Error!void {
    if (src.len != dst.len) return Error.ShapeMismatch;
    @memcpy(dst, src);
}

pub fn subtract(lhs: []const f64, rhs: []const f64, out: []f64) Error!void {
    if (lhs.len != rhs.len or lhs.len != out.len) return Error.ShapeMismatch;
    for (lhs, rhs, out) |left, right, *slot| {
        slot.* = left - right;
    }
}

pub fn normL2(x: []const f64) f64 {
    var acc: f64 = 0.0;
    for (x) |value| {
        acc += value * value;
    }
    return std.math.sqrt(acc);
}

pub fn relativeNorm(step: []const f64, state: []const f64) Error!f64 {
    if (step.len != state.len) return Error.ShapeMismatch;
    const denominator = @max(normL2(state), 1.0);
    return normL2(step) / denominator;
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

test "vector ops support subtract and relative norms" {
    const lhs = [_]f64{ 2.0, 4.0 };
    const rhs = [_]f64{ 1.0, 1.0 };
    var diff = [_]f64{ 0.0, 0.0 };

    try subtract(&lhs, &rhs, &diff);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), diff[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 3.0), diff[1], 1e-12);
    try std.testing.expect(try relativeNorm(&diff, &lhs) > 0.0);
}
