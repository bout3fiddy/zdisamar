const calibration = @import("../spectral_math/calibration.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;
const Types = @import("types.zig");
const Workspace = @import("workspace.zig");

pub fn materializeChannelSigma(
    providers: Types.ProviderBindings,
    scene: *const Scene,
    channel: SpectralChannel,
    wavelengths_nm: []const f64,
    signal: []const f64,
    output: []f64,
) Workspace.Error!void {
    if (providers.noise.materializesSigma(scene, channel)) {
        try providers.noise.materializeSigma(scene, channel, wavelengths_nm, signal, output);
    } else {
        @memset(output, 0.0);
    }
}

pub fn applyChannelCorrections(
    scene: *const Scene,
    channel: SpectralChannel,
    calibration_config: calibration.Calibration,
    depolarization_factor: f64,
    wavelengths_nm: []const f64,
    signal: []f64,
    scratch: []f64,
) !void {
    const controls = scene.observation_model.resolvedChannelControls(channel);
    try calibration.applySignal(calibration_config, signal, signal);
    try calibration.applySimpleOffsets(controls.simple_offsets, signal);
    try calibration.applySpectralFeatures(controls.spectral_features, wavelengths_nm, signal);
    if (controls.smear_percent != 0.0) {
        try calibration.applySmear(controls.smear_percent, signal, scratch);
    }
    try calibration.applyMultiplicativeNodes(controls.multiplicative_nodes, wavelengths_nm, signal, scratch);
    const stray_reference = if (controls.stray_light_nodes.use_reference_spectrum)
        correctionReferenceSignal(scene, channel, signal.len) orelse signal
    else
        signal;
    try calibration.applyStrayLightNodes(controls.stray_light_nodes, wavelengths_nm, stray_reference, signal, scratch);
    if (channel == .radiance) {
        try calibration.applyPolarizationScramblerBias(
            controls.use_polarization_scrambler,
            depolarization_factor,
            wavelengths_nm,
            signal,
        );
    }
}

pub fn applyChannelJacobianCorrections(
    scene: *const Scene,
    channel: SpectralChannel,
    calibration_config: calibration.Calibration,
    depolarization_factor: f64,
    wavelengths_nm: []const f64,
    jacobian: []f64,
    scratch: []f64,
) !void {
    const controls = scene.observation_model.resolvedChannelControls(channel);
    try calibration.applySignalDerivative(calibration_config, jacobian, jacobian);
    try calibration.applySimpleOffsetDerivatives(controls.simple_offsets, jacobian);
    try calibration.applySpectralFeatureDerivatives(controls.spectral_features, wavelengths_nm, jacobian);
    if (controls.smear_percent != 0.0) {
        try calibration.applySmear(controls.smear_percent, jacobian, scratch);
    }
    try calibration.applyMultiplicativeNodes(controls.multiplicative_nodes, wavelengths_nm, jacobian, scratch);

    const external_reference = correctionReferenceSignal(scene, channel, jacobian.len);
    if (!controls.stray_light_nodes.use_reference_spectrum or external_reference == null) {
        try calibration.applyStrayLightNodes(
            controls.stray_light_nodes,
            wavelengths_nm,
            jacobian,
            jacobian,
            scratch,
        );
    }
    if (channel == .radiance) {
        try calibration.applyPolarizationScramblerBias(
            controls.use_polarization_scrambler,
            depolarization_factor,
            wavelengths_nm,
            jacobian,
        );
    }
}

pub fn correctionReferenceSignal(
    scene: *const Scene,
    channel: SpectralChannel,
    sample_count: usize,
) ?[]const f64 {
    const controls = scene.observation_model.resolvedChannelControls(channel);
    if (controls.noise.reference_signal.len == sample_count) {
        return controls.noise.reference_signal;
    }
    if (channel == .radiance and scene.observation_model.reference_radiance.len == sample_count) {
        return scene.observation_model.reference_radiance;
    }
    return null;
}
