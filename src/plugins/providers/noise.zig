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
    return switch (scene.observation_model.noise_model) {
        .none => false,
        else => true,
    };
}

fn sceneNoiseSigma(scene: *const Scene, signal: []const f64, output: []f64) Error!void {
    return switch (scene.observation_model.noise_model) {
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

fn s5pOperationalSigma(scene: *const Scene, signal: []const f64, output: []f64) Error!void {
    return noise.scaleSigmaFromReference(
        scene.observation_model.reference_radiance,
        scene.observation_model.ingested_noise_sigma,
        signal,
        referenceBinWidthNm(scene),
        currentBinWidthNm(scene, signal.len),
        output,
    );
}

fn ingestedSigma(scene: *const Scene, signal: []const f64, output: []f64) Error!void {
    _ = signal;
    try noise.copyInputSigma(scene.observation_model.ingested_noise_sigma, output);
}

fn currentBinWidthNm(scene: *const Scene, sample_count: usize) f64 {
    if (scene.observation_model.measured_wavelengths_nm.len == sample_count and sample_count > 1) {
        return averageSpacingNm(scene.observation_model.measured_wavelengths_nm);
    }
    if (scene.spectral_grid.sample_count > 1) {
        return (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) /
            @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    }
    return referenceBinWidthNm(scene);
}

fn referenceBinWidthNm(scene: *const Scene) f64 {
    if (scene.observation_model.operational_refspec_grid.enabled()) {
        return scene.observation_model.operational_refspec_grid.effectiveSpacingNm();
    }
    if (scene.observation_model.measured_wavelengths_nm.len > 1) {
        return averageSpacingNm(scene.observation_model.measured_wavelengths_nm);
    }
    if (scene.spectral_grid.sample_count > 1) {
        return (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) /
            @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    }
    return 1.0;
}

fn averageSpacingNm(wavelengths_nm: []const f64) f64 {
    if (wavelengths_nm.len < 2) return 1.0;

    var spacing_sum: f64 = 0.0;
    for (wavelengths_nm[0 .. wavelengths_nm.len - 1], wavelengths_nm[1..]) |left_nm, right_nm| {
        spacing_sum += right_nm - left_nm;
    }
    return spacing_sum / @as(f64, @floatFromInt(wavelengths_nm.len - 1));
}

test "s5p operational noise reuses ingested sigma semantics instead of a toy scale factor" {
    const scene: Scene = .{
        .observation_model = .{
            .instrument = "tropomi",
            .noise_model = .s5p_operational,
            .measured_wavelengths_nm = &.{ 760.8, 761.0 },
            .reference_radiance = &.{ 10.0, 20.0 },
            .ingested_noise_sigma = &.{ 0.02, 0.03 },
        },
    };
    const signal = [_]f64{ 40.0, 5.0 };
    var sigma: [2]f64 = undefined;
    try s5pOperationalSigma(&scene, &signal, &sigma);
    try std.testing.expectApproxEqRel(@as(f64, 0.04), sigma[0], 1.0e-9);
    try std.testing.expectApproxEqRel(@as(f64, 0.015), sigma[1], 1.0e-9);
}

test "s5p operational noise uses the operational reference grid as the reference spectral bin width" {
    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 5,
        },
        .observation_model = .{
            .instrument = "tropomi",
            .noise_model = .s5p_operational,
            .reference_radiance = &.{ 10.0, 10.0, 10.0, 10.0, 10.0 },
            .ingested_noise_sigma = &.{ 0.02, 0.02, 0.02, 0.02, 0.02 },
            .operational_refspec_grid = .{
                .wavelengths_nm = &.{ 760.8, 761.0, 761.2 },
                .weights = &.{ 0.15, 0.70, 0.15 },
            },
        },
    };

    const signal = [_]f64{ 10.0, 10.0, 10.0, 10.0, 10.0 };
    var sigma: [5]f64 = undefined;
    try s5pOperationalSigma(&scene, &signal, &sigma);

    try std.testing.expectApproxEqRel(@as(f64, 0.028284271), sigma[0], 1.0e-9);
    try std.testing.expectApproxEqRel(@as(f64, 0.028284271), sigma[4], 1.0e-9);
}
