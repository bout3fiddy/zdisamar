const std = @import("std");
const noise = @import("../../kernels/spectra/noise.zig");
const Scene = @import("../../model/Scene.zig").Scene;

pub const Error = noise.Error;

pub const Provider = struct {
    id: []const u8,
    materializesSigma: *const fn (scene: *const Scene) bool,
    materializeSigma: *const fn (scene: *const Scene, signal: []const f64, output: []f64) Error!void,
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

fn neverEnabled(_: *const Scene) bool {
    return false;
}

fn alwaysEnabled(_: *const Scene) bool {
    return true;
}

fn sceneNoiseEnabled(scene: *const Scene) bool {
    return switch (scene.observation_model.resolvedNoiseModel() catch return false) {
        .none => false,
        else => true,
    };
}

fn sceneNoiseSigma(scene: *const Scene, signal: []const f64, output: []f64) Error!void {
    return switch (scene.observation_model.resolvedNoiseModel() catch .none) {
        .shot_noise => shotNoiseSigma(scene, signal, output),
        .s5p_operational => s5pOperationalSigma(scene, signal, output),
        .snr_from_input => ingestedSigma(scene, signal, output),
        .none => zeroSigma(scene, signal, output),
    };
}

fn zeroSigma(_: *const Scene, signal: []const f64, output: []f64) Error!void {
    if (signal.len != output.len) return error.ShapeMismatch;
    @memset(output, 0.0);
}

fn shotNoiseSigma(_: *const Scene, signal: []const f64, output: []f64) Error!void {
    try noise.shotNoiseStd(signal, 2.0, output);
}

fn s5pOperationalSigma(_: *const Scene, signal: []const f64, output: []f64) Error!void {
    try noise.shotNoiseStd(signal, 3.5, output);
}

fn ingestedSigma(scene: *const Scene, signal: []const f64, output: []f64) Error!void {
    _ = signal;
    try noise.copyInputSigma(scene.observation_model.ingested_noise_sigma, output);
}
