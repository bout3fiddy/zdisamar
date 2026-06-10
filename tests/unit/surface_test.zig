const std = @import("std");
const internal = @import("internal");

const surface = internal.surface;
const Surface = surface.Surface;
const errors = internal.common.errors;

test "surface validates scalar Lambertian metadata" {
    const value: Surface = .{
        .albedo = 0.2,
        .pressure_hpa = 1013.25,
    };
    try value.validate();
    try std.testing.expectError(errors.Error.InvalidRequest, (Surface{ .albedo = std.math.nan(f64) }).validate());
    try std.testing.expectError(errors.Error.InvalidRequest, (Surface{ .albedo = -0.1 }).validate());
    try std.testing.expectError(errors.Error.InvalidRequest, (Surface{ .pressure_hpa = -1.0 }).validate());
}
