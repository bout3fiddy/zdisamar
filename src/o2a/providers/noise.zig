const std = @import("std");
const noise = @import("../../kernels/spectra/noise.zig");
const SpectralChannel = @import("../../model/Instrument.zig").SpectralChannel;
const Scene = @import("../../model/Scene.zig").Scene;

pub const Error = noise.Error;

pub const Provider = struct {
    id: []const u8,
    materializesSigma: *const fn (scene: *const Scene, channel: SpectralChannel) bool,
    materializeSigma: *const fn (scene: *const Scene, channel: SpectralChannel, wavelengths_nm: []const f64, signal: []const f64, output: []f64) Error!void,
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

fn neverEnabled(_: *const Scene, _: SpectralChannel) bool {
    return false;
}

fn alwaysEnabled(_: *const Scene, _: SpectralChannel) bool {
    return true;
}

fn sceneNoiseEnabled(scene: *const Scene, channel: SpectralChannel) bool {
    return scene.observation_model.resolvedChannelControls(channel).noise.enabled;
}

fn sceneNoiseSigma(
    scene: *const Scene,
    channel: SpectralChannel,
    wavelengths_nm: []const f64,
    signal: []const f64,
    output: []f64,
) Error!void {
    const controls = scene.observation_model.resolvedChannelControls(channel).noise;
    if (controls.snr_values.len != 0) {
        return noise.sigmaFromInterpolatedSignalToNoise(
            wavelengths_nm,
            controls.snr_wavelengths_nm,
            controls.snr_values,
            signal,
            output,
        );
    }
    return switch (controls.model) {
        .shot_noise => shotNoiseSigma(scene, channel, wavelengths_nm, signal, output),
        .s5p_operational => s5pOperationalSigma(scene, channel, wavelengths_nm, signal, output),
        .lab_operational => labOperationalSigma(scene, channel, wavelengths_nm, signal, output),
        .snr_from_input => ingestedSigma(scene, channel, signal, output),
        .none => zeroSigma(scene, channel, wavelengths_nm, signal, output),
    };
}

fn zeroSigma(_: *const Scene, _: SpectralChannel, _: []const f64, signal: []const f64, output: []f64) Error!void {
    if (signal.len != output.len) return error.ShapeMismatch;
    @memset(output, 0.0);
}

fn shotNoiseSigma(
    scene: *const Scene,
    channel: SpectralChannel,
    _: []const f64,
    signal: []const f64,
    output: []f64,
) Error!void {
    const controls = scene.observation_model.resolvedChannelControls(channel).noise;
    try noise.shotNoiseStd(signal, controls.electrons_per_count, output);
}

// PUB FOR TEST: re-exported via Noise module surface for tests in tests/unit/.
pub fn s5pOperationalSigma(
    scene: *const Scene,
    channel: SpectralChannel,
    wavelengths_nm: []const f64,
    signal: []const f64,
    output: []f64,
) Error!void {
    const controls = scene.observation_model.resolvedChannelControls(channel).noise;
    if (controls.reference_signal.len != 0 and controls.reference_sigma.len != 0) {
        return noise.scaleSigmaFromReference(
            controls.reference_signal,
            controls.reference_sigma,
            signal,
            referenceBinWidthNm(scene, channel, controls.reference_signal.len),
            currentBinWidthNm(scene, wavelengths_nm),
            output,
        );
    }
    return noise.sigmaFromS5Operational(wavelengths_nm, signal, output);
}

// PUB FOR TEST: re-exported via Noise module surface for tests in tests/unit/.
pub fn labOperationalSigma(
    scene: *const Scene,
    channel: SpectralChannel,
    _: []const f64,
    signal: []const f64,
    output: []f64,
) Error!void {
    const controls = scene.observation_model.resolvedChannelControls(channel).noise;
    return noise.sigmaFromLabOperational(signal, controls.lab_a, controls.lab_b, output);
}

fn ingestedSigma(scene: *const Scene, channel: SpectralChannel, signal: []const f64, output: []f64) Error!void {
    const controls = scene.observation_model.resolvedChannelControls(channel).noise;
    _ = signal;
    if (controls.reference_sigma.len != 0) {
        return noise.copyInputSigma(controls.reference_sigma, output);
    }
    try noise.copyInputSigma(scene.observation_model.ingested_noise_sigma, output);
}

fn currentBinWidthNm(scene: *const Scene, wavelengths_nm: []const f64) f64 {
    if (wavelengths_nm.len > 1) {
        return averageSpacingNm(wavelengths_nm);
    }
    if (scene.spectral_grid.sample_count > 1) {
        return (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) /
            @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    }
    return referenceBinWidthNm(scene, .radiance, 0);
}

fn referenceBinWidthNm(scene: *const Scene, channel: SpectralChannel, sample_count: usize) f64 {
    const controls = scene.observation_model.resolvedChannelControls(channel).noise;
    const operational_band_support = scene.observation_model.primaryOperationalBandSupport();
    if (controls.reference_bin_width_nm > 0.0) return controls.reference_bin_width_nm;
    if (operational_band_support.operational_refspec_grid.enabled()) {
        return operational_band_support.operational_refspec_grid.effectiveSpacingNm();
    }
    if (sample_count > 1 and
        channel == .radiance and
        scene.observation_model.reference_radiance.len == sample_count and
        scene.observation_model.measured_wavelengths_nm.len == sample_count)
    {
        return averageSpacingNm(scene.observation_model.measured_wavelengths_nm);
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
