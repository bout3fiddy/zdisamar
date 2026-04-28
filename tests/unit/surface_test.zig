const std = @import("std");
const internal = @import("internal");

const surface = internal.surface;
const Surface = surface.Surface;
const Parameter = surface.Parameter;
const errors = internal.common.errors;

test "surface accepts named parameters" {
    const value: Surface = .{
        .kind = .lambertian,
        .parameters = &[_]Parameter{
            .{ .name = "roughness_hint", .value = 0.03 },
            .{ .name = "slope_hint", .value = 0.02 },
        },
    };
    try std.testing.expectEqual(Surface.Kind.lambertian, value.kind);
    try value.validate();
    try std.testing.expectEqual(Surface.Kind.lambertian, try Surface.Kind.parse("lambertian"));
    try std.testing.expectEqual(Surface.Kind.wavel_dependent, try Surface.Kind.parse("wavel_dependent"));
    try std.testing.expectError(errors.Error.InvalidRequest, Surface.Kind.parse("unknown_surface"));
}
