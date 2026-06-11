const std = @import("std");
const internal = @import("internal");

const spline = internal.common.math.spline;
const sampleEndpointSecant = spline.sampleEndpointSecant;

test "endpoint-secant spline preserves linear endpoint slopes" {
    const x = [_]f64{ 0.0, 1.0, 2.0, 3.0 };
    const y = [_]f64{ 0.0, 1.0, 4.0, 9.0 };
    const value = try sampleEndpointSecant(&x, &y, 1.5);
    try std.testing.expect(value > 2.0 and value < 3.0);
}

test "batched endpoint-secant spline derivatives match individual solves" {
    const x = [_]f64{ 0.0, 0.6, 1.7, 2.4, 4.0 };
    const y0 = [_]f64{ 0.1, 0.3, 1.1, 0.9, 2.2 };
    const y1 = [_]f64{ 1.0, 0.7, 0.4, 0.8, 1.5 };
    const y2 = [_]f64{ 2.0, 2.2, 2.1, 2.7, 3.0 };

    var expected0: [x.len]f64 = undefined;
    var expected1: [x.len]f64 = undefined;
    var expected2: [x.len]f64 = undefined;
    try spline.endpointSecantSecondDerivatives(&x, &y0, &expected0);
    try spline.endpointSecantSecondDerivatives(&x, &y1, &expected1);
    try spline.endpointSecantSecondDerivatives(&x, &y2, &expected2);

    var actual0: [x.len]f64 = undefined;
    var actual1: [x.len]f64 = undefined;
    var actual2: [x.len]f64 = undefined;
    try spline.endpointSecantSecondDerivatives3(
        &x,
        &y0,
        &y1,
        &y2,
        &actual0,
        &actual1,
        &actual2,
    );

    inline for (.{ .{ expected0, actual0 }, .{ expected1, actual1 }, .{ expected2, actual2 } }) |pair| {
        for (pair[0], pair[1]) |expected, actual| {
            try std.testing.expectEqual(expected, actual);
        }
    }
}
