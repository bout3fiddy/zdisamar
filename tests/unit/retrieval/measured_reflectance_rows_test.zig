const std = @import("std");
const internal = @import("internal");

const retrieval = internal.retrieval.root;

test "measured reflectance rows copy sorted finite samples and invert variance" {
    var measurements = try retrieval.MeasuredReflectanceRows.init(
        std.testing.allocator,
        &.{ 758.0, 760.0, 765.0 },
        &.{ 0.10, 0.20, 0.30 },
        &.{ 4.0, 2.0, 0.5 },
    );
    defer measurements.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(f64, &.{ 758.0, 760.0, 765.0 }, measurements.wavelength_nm);
    try std.testing.expectEqualSlices(f64, &.{ 0.10, 0.20, 0.30 }, measurements.reflectance);
    try std.testing.expectEqualSlices(f64, &.{ 0.25, 0.5, 2.0 }, measurements.inv_variance);
}

test "measured reflectance rows reject unsorted or invalid samples" {
    try std.testing.expectError(
        error.InvalidMeasurement,
        retrieval.MeasuredReflectanceRows.init(
            std.testing.allocator,
            &.{ 758.0, 758.0 },
            &.{ 0.10, 0.20 },
            &.{ 1.0, 1.0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidMeasurement,
        retrieval.MeasuredReflectanceRows.init(
            std.testing.allocator,
            &.{ 758.0, 760.0 },
            &.{ 0.10, 0.20 },
            &.{ 1.0, 0.0 },
        ),
    );
}
