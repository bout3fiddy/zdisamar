const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const PreparedOpticalState = @import("../../kernels/optics/prepare.zig").PreparedOpticalState;
const ForwardResult = @import("../../kernels/transport/common.zig").ForwardResult;

pub const EvaluationContext = struct {
    scene: Scene,
    prepared: PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: ForwardResult,
};

pub const Provider = struct {
    id: []const u8,
    responseGain: *const fn (context: EvaluationContext) f64,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.lambertian_surface")) {
        return .{
            .id = provider_id,
            .responseGain = lambertianGain,
        };
    }
    if (std.mem.eql(u8, provider_id, "builtin.directional_lambertian_surface")) {
        return .{
            .id = provider_id,
            .responseGain = directionalLambertianGain,
        };
    }
    return null;
}

fn lambertianGain(context: EvaluationContext) f64 {
    _ = context.prepared;
    _ = context.wavelength_nm;
    _ = context.safe_span;
    _ = context.phase;
    _ = context.forward;
    return 0.75 + 0.50 * context.scene.surface.albedo;
}

fn directionalLambertianGain(context: EvaluationContext) f64 {
    const mu0 = @max(@cos(std.math.degreesToRadians(context.scene.geometry.solar_zenith_deg)), 0.05);
    const muv = @max(@cos(std.math.degreesToRadians(context.scene.geometry.viewing_zenith_deg)), 0.05);
    const azimuth = std.math.degreesToRadians(context.scene.geometry.relative_azimuth_deg);
    const anisotropy = 0.88 + 0.10 * @cos(azimuth) + 0.06 * (mu0 + muv);
    return (0.68 + 0.55 * context.scene.surface.albedo) * anisotropy;
}
