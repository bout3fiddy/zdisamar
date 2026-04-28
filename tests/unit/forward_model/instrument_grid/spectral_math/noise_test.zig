const std = @import("std");
const internal = @import("internal");

const noise = internal.kernels.spectra.noise;
const shotNoiseStd = noise.shotNoiseStd;
const whitenResiduals = noise.whitenResiduals;
const copyInputSigma = noise.copyInputSigma;
const scaleSigmaFromReference = noise.scaleSigmaFromReference;
const sigmaFromInterpolatedSignalToNoise = noise.sigmaFromInterpolatedSignalToNoise;
const sigmaFromLabOperational = noise.sigmaFromLabOperational;
const sigmaFromS5Operational = noise.sigmaFromS5Operational;

test "noise helpers estimate shot-noise sigma and whiten residuals" {
    const signal = [_]f64{ 100.0, 400.0 };
    var sigma: [2]f64 = undefined;
    try shotNoiseStd(&signal, 2.0, &sigma);

    const residual = [_]f64{ 5.0, 10.0 };
    var whitened: [2]f64 = undefined;
    try whitenResiduals(&residual, &sigma, &whitened);

    try std.testing.expect(sigma[1] > sigma[0]);
    try std.testing.expect(whitened[0] > 0.0);
}

test "noise helpers reject invalid scale factors and singular whitening weights" {
    const signal = [_]f64{100.0};
    var sigma: [1]f64 = undefined;
    try std.testing.expectError(error.InvalidNoiseScaleFactor, shotNoiseStd(&signal, 0.0, &sigma));

    const residual = [_]f64{5.0};
    const invalid_sigma = [_]f64{0.0};
    var whitened: [1]f64 = undefined;
    try std.testing.expectError(error.SingularWhiteningWeight, whitenResiduals(&residual, &invalid_sigma, &whitened));
}

test "noise helpers require explicit positive sigma input for snr-driven paths" {
    var sigma: [2]f64 = undefined;
    try std.testing.expectError(error.MissingInputNoiseSigma, copyInputSigma(&.{}, &sigma));
    try std.testing.expectError(error.InvalidInputNoiseSigma, copyInputSigma(&.{ 0.02, 0.0 }, &sigma));
    try copyInputSigma(&.{ 0.02, 0.03 }, &sigma);
    try std.testing.expectEqual(@as(f64, 0.02), sigma[0]);
    try std.testing.expectEqual(@as(f64, 0.03), sigma[1]);
}

test "noise helpers reject invalid single-point interpolated SNR inputs" {
    const wavelengths = [_]f64{ 310.0, 312.0 };
    const signal = [_]f64{ 100.0, 120.0 };
    const snr_wavelengths = [_]f64{311.0};
    var sigma: [2]f64 = undefined;

    try std.testing.expectError(
        error.InvalidNoiseScaleFactor,
        sigmaFromInterpolatedSignalToNoise(&wavelengths, &snr_wavelengths, &.{0.0}, &signal, &sigma),
    );
    try std.testing.expectError(
        error.InvalidNoiseScaleFactor,
        sigmaFromInterpolatedSignalToNoise(&wavelengths, &snr_wavelengths, &.{std.math.inf(f64)}, &signal, &sigma),
    );
}

test "noise helpers scale sigma from a reference radiance spectrum with spectral-bin correction" {
    const reference_signal = [_]f64{ 10.0, 20.0 };
    const reference_sigma = [_]f64{ 0.1, 0.2 };
    const current_signal = [_]f64{ 40.0, 5.0 };
    var sigma: [2]f64 = undefined;

    try scaleSigmaFromReference(
        &reference_signal,
        &reference_sigma,
        &current_signal,
        0.20,
        0.10,
        &sigma,
    );

    // Tolerance loosened from 1e-9: original inline test was never
    // discovered, so the expected values rounded to 9 decimals were never
    // checked against actual sqrt(2)/5 / sqrt(2/5)*scale outputs.
    try std.testing.expectApproxEqRel(@as(f64, 0.282842712), sigma[0], 1.0e-8);
    try std.testing.expectApproxEqRel(@as(f64, 0.141421356), sigma[1], 1.0e-8);
}

test "noise helpers evaluate LAB and Sentinel-5 operational sigma branches" {
    const wavelengths = [_]f64{ 290.0, 320.0, 450.0 };
    const signal = [_]f64{ 1.2e6, 1.5e6, 2.0e6 };
    var lab_sigma: [3]f64 = undefined;
    var s5_sigma: [3]f64 = undefined;

    try sigmaFromLabOperational(&signal, 3.5e-6, 1500.0, &lab_sigma);
    try sigmaFromS5Operational(&wavelengths, &signal, &s5_sigma);

    try std.testing.expect(lab_sigma[0] > 0.0);
    try std.testing.expect(s5_sigma[0] > 0.0);
    try std.testing.expect(s5_sigma[1] != s5_sigma[2]);
}
