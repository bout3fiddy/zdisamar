const std = @import("std");
const Scene = @import("../../input/Scene.zig").Scene;
const PreparedOpticalState = @import("../optical_properties/root.zig").PreparedOpticalState;
const ForwardResult = @import("../radiative_transfer/root.zig").ForwardResult;

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
