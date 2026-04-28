const std = @import("std");
const internal = @import("internal");

const band_means = internal.forward_model.optical_properties.shared.band_means;
const computeWeightedWindowMean = band_means.computeWeightedWindowMean;

test "band means support generic weighted fit windows" {
    const values = [_]f64{ 1.0, 3.0, 5.0 };
    const weights = [_]f64{ 1.0, 2.0, 1.0 };
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), computeWeightedWindowMean(&values, &weights), 1.0e-12);
}
