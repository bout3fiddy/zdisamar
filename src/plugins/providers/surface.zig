const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const PreparedOpticalState = @import("../../kernels/optics/prepare.zig").PreparedOpticalState;
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
    responseGain: *const fn (context: EvaluationContext) f64,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.lambertian_surface")) {
        return .{
            .id = provider_id,
            .responseGain = lambertianResponseGain,
        };
    }
    return null;
}

fn lambertianResponseGain(context: EvaluationContext) f64 {
    _ = context.prepared;
    _ = context.wavelength_nm;
    _ = context.safe_span;
    _ = context.phase;
    _ = context.forward;
    _ = context.scene;
    return 1.0;
}
