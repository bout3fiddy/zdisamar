const std = @import("std");
const internal = @import("internal");

const cross_sections = internal.reference.cross_sections;
const differentialVector = cross_sections.differentialVector;
const weightedMeanSamples = cross_sections.weightedMeanSamples;

test "cross-section helpers remove weighted polynomial baselines" {
    const wavelengths = [_]f64{ 759.0, 760.0, 761.0, 762.0 };
    const values = [_]f64{ 1.0, 1.4, 1.8, 2.2 };
    const weights = [_]f64{ 1.0, 1.0, 1.0, 1.0 };
    const differential = try differentialVector(std.testing.allocator, &wavelengths, &values, &weights, 1);
    defer std.testing.allocator.free(differential);

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), weightedMeanSamples(differential, &weights), 1.0e-9);
}
