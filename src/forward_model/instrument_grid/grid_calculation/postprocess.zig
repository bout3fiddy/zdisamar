const calibration = @import("../spectral_math/calibration.zig");

// hot path:
//   when: radiance and irradiance channels are postprocessed after convolution
//   work: applies the scene-level calibration gain/offset and stray-light scalar
//   data: signal array and calibration scalar fields
//   follow: spectral_math.calibration applySignal
pub fn applyChannelCorrections(
    calibration_config: calibration.Calibration,
    signal: []f64,
) !void {
    try calibration.applySignal(calibration_config, signal, signal);
}

// hot path:
//   when: active Jacobian columns are postprocessed after radiance integration
//   work: applies derivative-compatible gain/stray-light calibration column by column
//   data: one Jacobian column and calibration scalar fields
//   follow: simulate.processJacobianSamples and calibration.applySignalDerivative
pub fn applyChannelJacobianCorrections(
    calibration_config: calibration.Calibration,
    jacobian: []f64,
) !void {
    try calibration.applySignalDerivative(calibration_config, jacobian, jacobian);
}
