const std = @import("std");
const Scene = @import("../../input/Scene.zig").Scene;
const PreparedOpticalState = @import("../optical_properties/root.zig").PreparedOpticalState;
const ForwardResult = @import("../radiative_transfer/root.zig").ForwardResult;

// layout(64-bit):
//   size: 88 B, align: 8 B
//   field storage: 88 B across 6 fields; largest: forward=48 B, scene=8 B, prepared=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: scene, prepared carry references/descriptors; referenced storage is not included in size
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 88 B (0.086 KiB); total also includes referenced storage above
pub const EvaluationContext = struct {
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: ForwardResult,
};

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: id=16 B, brdfFactor=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: id, brdfFactor carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total also includes referenced storage above
pub const Implementation = struct {
    id: []const u8,
    brdfFactor: *const fn (context: EvaluationContext) f64,
};

pub fn resolve(provider_id: []const u8) ?Implementation {
    if (std.mem.eql(u8, provider_id, "builtin.lambertian_surface")) {
        return .{
            .id = provider_id,
            .brdfFactor = lambertianBrdfFactor,
        };
    }
    return null;
}

fn lambertianBrdfFactor(context: EvaluationContext) f64 {
    _ = context.scene;
    _ = context.prepared;
    _ = context.wavelength_nm;
    _ = context.safe_span;
    _ = context.phase;
    _ = context.forward;
    // Lambertian BRDF is isotropic, so the directional factor stays unity here.
    // Scalar surface albedo already enters transport through ForwardInput.surface_albedo.
    return 1.0;
}
