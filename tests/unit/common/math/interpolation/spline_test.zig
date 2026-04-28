const std = @import("std");
const internal = @import("internal");

const spline = internal.kernels.interpolation.spline;
const sampleNatural = spline.sampleNatural;
const sampleEndpointSecant = spline.sampleEndpointSecant;

test "natural cubic spline reproduces a quadratic profile at midpoints" {
    const x = [_]f64{ 0.0, 1.0, 2.0, 3.0 };
    const y = [_]f64{ 0.0, 1.0, 4.0, 9.0 };
    const value = try sampleNatural(&x, &y, 1.5);
    try std.testing.expectApproxEqRel(@as(f64, 2.2), value, 0.05);
}

test "endpoint-secant spline preserves linear endpoint slopes" {
    const x = [_]f64{ 0.0, 1.0, 2.0, 3.0 };
    const y = [_]f64{ 0.0, 1.0, 4.0, 9.0 };
    const value = try sampleEndpointSecant(&x, &y, 1.5);
    try std.testing.expect(value > 2.0 and value < 3.0);
}
