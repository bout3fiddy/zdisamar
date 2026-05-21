const std = @import("std");
const internal = @import("internal");

const Surface = internal.forward_model.implementations.Surface;

test "lambertian surface provider exposes a unit BRDF factor" {
    const provider = Surface.resolve("builtin.lambertian_surface").?;
    const factor = provider.brdfFactor(.{
        .scene = &.{
            .surface = .{
                .albedo = 0.07,
            },
        },
        .prepared = undefined,
        .wavelength_nm = 760.0,
        .safe_span = 1.0,
        .phase = 0.0,
        .forward = .{
            .family = .labos,
            .regime = .nadir,
            .execution_mode = .scalar,
            .derivative_mode = .none,
            .toa_reflectance_factor = 0.05,
            .jacobian = null,
        },
    });
    try std.testing.expectEqual(@as(f64, 1.0), factor);
}
