const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const PreparedOpticalState = @import("../../kernels/optics/preparation.zig").PreparedOpticalState;
const ForwardResult = @import("../../kernels/transport/common.zig").ForwardResult;

pub const EvaluationContext = struct {
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: ForwardResult,
};

pub const Provider = struct {
    id: []const u8,
    brdfFactor: *const fn (context: EvaluationContext) f64,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.lambertian_surface")) {
        return .{
            .id = provider_id,
            .brdfFactor = lambertianBrdfFactor,
        };
    }
    return null;
}

fn lambertianBrdfFactor(context: EvaluationContext) f64 {
    _ = context.prepared;
    _ = context.wavelength_nm;
    _ = context.safe_span;
    _ = context.phase;
    _ = context.forward;
    return switch (context.scene.surface.kind) {
        // Lambertian BRDF is isotropic, so the directional factor stays unity here.
        // Scene albedo already enters the radiative transfer routine through ForwardInput.surface_albedo.
        .lambertian => 1.0,
        // Wavelength-dependent surfaces use the same isotropic directional factor;
        // spectral dependence is handled through the albedo schedule.
        .wavel_dependent => 1.0,
    };
}

test "lambertian surface provider exposes a unit BRDF factor" {
    const provider = resolve("builtin.lambertian_surface").?;
    const factor = provider.brdfFactor(.{
        .scene = &.{
            .surface = .{
                .kind = .lambertian,
                .albedo = 0.07,
            },
        },
        .prepared = undefined,
        .wavelength_nm = 760.0,
        .safe_span = 1.0,
        .phase = 0.0,
        .forward = .{
            .family = .adding,
            .regime = .nadir,
            .execution_mode = .scalar,
            .derivative_mode = .none,
            .toa_reflectance_factor = 0.05,
            .jacobian_column = null,
        },
    });
    try std.testing.expectEqual(@as(f64, 1.0), factor);
}
