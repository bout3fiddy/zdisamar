const std = @import("std");
const noise = @import("../../kernels/spectra/noise.zig");
const Scene = @import("../../model/Scene.zig").Scene;

pub const Error = error{ShapeMismatch};

pub const Provider = struct {
    id: []const u8,
    materializesSigma: *const fn (scene: Scene) bool,
    materializeSigma: *const fn (scene: Scene, signal: []const f64, output: []f64) Error!void,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.scene_noise")) {
        return .{
            .id = provider_id,
            .materializesSigma = sceneNoiseEnabled,
            .materializeSigma = sceneNoiseSigma,
        };
    }
    if (std.mem.eql(u8, provider_id, "builtin.none_noise")) {
        return .{
            .id = provider_id,
            .materializesSigma = neverEnabled,
            .materializeSigma = zeroSigma,
        };
    }
    if (std.mem.eql(u8, provider_id, "builtin.shot_noise")) {
        return .{
            .id = provider_id,
            .materializesSigma = alwaysEnabled,
            .materializeSigma = shotNoiseSigma,
        };
    }
    if (std.mem.eql(u8, provider_id, "builtin.s5p_operational_noise")) {
        return .{
            .id = provider_id,
            .materializesSigma = alwaysEnabled,
            .materializeSigma = s5pOperationalSigma,
        };
    }
    return null;
}

fn neverEnabled(_: Scene) bool {
    return false;
}

fn alwaysEnabled(_: Scene) bool {
    return true;
}

fn sceneNoiseEnabled(scene: Scene) bool {
    return !std.mem.eql(u8, scene.observation_model.noise_model, "none");
}

fn sceneNoiseSigma(scene: Scene, signal: []const f64, output: []f64) Error!void {
    if (std.mem.eql(u8, scene.observation_model.noise_model, "shot_noise")) {
        return shotNoiseSigma(scene, signal, output);
    }
    if (std.mem.eql(u8, scene.observation_model.noise_model, "s5p_operational")) {
        return s5pOperationalSigma(scene, signal, output);
    }
    return zeroSigma(scene, signal, output);
}

fn zeroSigma(_: Scene, signal: []const f64, output: []f64) Error!void {
    if (signal.len != output.len) return error.ShapeMismatch;
    @memset(output, 0.0);
}

fn shotNoiseSigma(_: Scene, signal: []const f64, output: []f64) Error!void {
    try noise.shotNoiseStd(signal, 2.0, output);
}

fn s5pOperationalSigma(_: Scene, signal: []const f64, output: []f64) Error!void {
    try noise.shotNoiseStd(signal, 3.5, output);
}
