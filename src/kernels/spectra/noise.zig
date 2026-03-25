//! Purpose:
//!   Estimate, scale, and whiten spectral noise vectors for forward and retrieval workflows.
//!
//! Physics:
//!   Tracks photon shot noise and sigma propagation between reference and current spectral bins.
//!
//! Vendor:
//!   `noise / whitening helpers`
//!
//! Design:
//!   The helpers are intentionally explicit about reference-vs-current sigma propagation and input-noise paths.
//!
//! Invariants:
//!   Shapes must match, sigma values must be positive, and scale factors must be finite and positive.
//!
//! Validation:
//!   Tests cover shot-noise estimation, whitening, sigma copying, and reference-bin correction.

const std = @import("std");

pub const Error = error{
    ShapeMismatch,
    InvalidNoiseScaleFactor,
    InvalidInputNoiseSigma,
    MissingInputNoiseSigma,
    MissingReferenceSignal,
    InvalidReferenceSignal,
    SingularWhiteningWeight,
    UnsupportedS5OperationalRange,
};

/// Purpose:
///   Estimate shot-noise standard deviation from a signal expressed in detector counts.
///
/// Physics:
///   Converts counts to electrons, applies Poisson scaling, then maps back to count units.
///
/// Vendor:
///   `shot noise standard deviation`
///
/// Units:
///   `electrons_per_count` is electrons per recorded count.
pub fn shotNoiseStd(signal: []const f64, electrons_per_count: f64, output: []f64) Error!void {
    if (signal.len != output.len) return error.ShapeMismatch;
    if (!std.math.isFinite(electrons_per_count) or electrons_per_count <= 0.0) {
        return error.InvalidNoiseScaleFactor;
    }
    for (signal, output) |sample, *slot| {
        const electrons = @max(sample * electrons_per_count, 0.0);
        slot.* = std.math.sqrt(electrons) / electrons_per_count;
    }
}

/// Purpose:
///   Whiten residuals by dividing them by per-channel sigma.
///
/// Physics:
///   Produces a unitless residual vector suitable for least-squares objectives.
///
/// Vendor:
///   `residual whitening`
pub fn whitenResiduals(residual: []const f64, sigma: []const f64, output: []f64) Error!void {
    if (residual.len != sigma.len or residual.len != output.len) return error.ShapeMismatch;
    for (residual, sigma, output) |value, sigma_value, *slot| {
        if (!std.math.isFinite(sigma_value) or sigma_value <= 0.0) {
            return error.SingularWhiteningWeight;
        }
        slot.* = value / sigma_value;
    }
}

/// Purpose:
///   Copy explicit input sigmas into an output buffer after validating positivity.
///
/// Physics:
///   Preserves user-supplied noise estimates for sigma-driven retrieval paths.
///
/// Vendor:
///   `input sigma propagation`
pub fn copyInputSigma(input_sigma: []const f64, output: []f64) Error!void {
    if (input_sigma.len == 0) return error.MissingInputNoiseSigma;
    if (input_sigma.len != output.len) return error.ShapeMismatch;
    for (input_sigma, output) |sigma_value, *slot| {
        if (!std.math.isFinite(sigma_value) or sigma_value <= 0.0) {
            return error.InvalidInputNoiseSigma;
        }
        slot.* = sigma_value;
    }
}

/// Purpose:
///   Scale a reference sigma vector to a current spectrum with bin-width correction.
///
/// Physics:
///   Propagates sigma proportionally to signal intensity and spectral bin width.
///
/// Vendor:
///   `reference sigma scaling`
///
/// Units:
///   `reference_bin_width_nm` and `current_bin_width_nm` are bin widths in nanometers.
pub fn scaleSigmaFromReference(
    reference_signal: []const f64,
    reference_sigma: []const f64,
    current_signal: []const f64,
    reference_bin_width_nm: f64,
    current_bin_width_nm: f64,
    output: []f64,
) Error!void {
    if (reference_signal.len == 0) return error.MissingReferenceSignal;
    if (reference_signal.len != reference_sigma.len or
        reference_signal.len != current_signal.len or
        reference_signal.len != output.len)
    {
        return error.ShapeMismatch;
    }
    if (!std.math.isFinite(reference_bin_width_nm) or reference_bin_width_nm <= 0.0 or
        !std.math.isFinite(current_bin_width_nm) or current_bin_width_nm <= 0.0)
    {
        return error.InvalidNoiseScaleFactor;
    }

    const bin_width_scale = std.math.sqrt(reference_bin_width_nm / current_bin_width_nm);
    for (reference_signal, reference_sigma, current_signal, output) |reference_value, sigma_value, signal_value, *slot| {
        if (!std.math.isFinite(reference_value) or reference_value <= 0.0) return error.InvalidReferenceSignal;
        if (!std.math.isFinite(signal_value) or signal_value < 0.0) return error.InvalidReferenceSignal;
        if (!std.math.isFinite(sigma_value) or sigma_value <= 0.0) return error.InvalidInputNoiseSigma;

        slot.* = sigma_value *
            std.math.sqrt(signal_value / reference_value) *
            bin_width_scale;
    }
}

/// Purpose:
///   Interpolate a sparse SNR specification onto the current wavelengths and convert it to sigma.
pub fn sigmaFromInterpolatedSignalToNoise(
    wavelengths_nm: []const f64,
    snr_wavelengths_nm: []const f64,
    snr_values: []const f64,
    signal: []const f64,
    output: []f64,
) Error!void {
    if (wavelengths_nm.len != signal.len or signal.len != output.len) return error.ShapeMismatch;
    if (snr_wavelengths_nm.len == 0 or snr_wavelengths_nm.len != snr_values.len) return error.InvalidNoiseScaleFactor;
    if (snr_wavelengths_nm.len == 1) {
        for (signal, output) |signal_value, *slot| {
            if (!std.math.isFinite(signal_value) or signal_value < 0.0) return error.InvalidReferenceSignal;
            slot.* = signal_value / snr_values[0];
        }
        return;
    }
    for (wavelengths_nm, signal, output) |wavelength_nm, signal_value, *slot| {
        if (!std.math.isFinite(signal_value) or signal_value < 0.0) return error.InvalidReferenceSignal;
        const snr_value = interpolateLinearClamped(snr_wavelengths_nm, snr_values, wavelength_nm);
        if (!std.math.isFinite(snr_value) or snr_value <= 0.0) return error.InvalidNoiseScaleFactor;
        slot.* = signal_value / snr_value;
    }
}

/// Purpose:
///   Evaluate the vendor-style LAB SNR parameterization and convert it to sigma.
pub fn sigmaFromLabOperational(signal: []const f64, a: f64, b: f64, output: []f64) Error!void {
    if (signal.len != output.len) return error.ShapeMismatch;
    if (!std.math.isFinite(a) or a <= 0.0 or !std.math.isFinite(b) or b < 0.0) {
        return error.InvalidNoiseScaleFactor;
    }
    for (signal, output) |signal_value, *slot| {
        if (!std.math.isFinite(signal_value) or signal_value < 0.0) return error.InvalidReferenceSignal;
        slot.* = std.math.sqrt(a * signal_value + b * b) / a;
    }
}

/// Purpose:
///   Evaluate the legacy Sentinel-5 SNR parameterization and convert it to sigma.
pub fn sigmaFromS5Operational(
    wavelengths_nm: []const f64,
    signal: []const f64,
    output: []f64,
) Error!void {
    if (wavelengths_nm.len != signal.len or signal.len != output.len) return error.ShapeMismatch;

    for (wavelengths_nm, signal, output) |wavelength_nm, signal_value, *slot| {
        if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(signal_value) or signal_value < 0.0) {
            return error.InvalidReferenceSignal;
        }
        const coefficients = try s5OperationalCoefficients(wavelength_nm);
        slot.* = std.math.sqrt(coefficients.a * signal_value + coefficients.b) / coefficients.a;
    }
}

const S5Coefficients = struct {
    a: f64,
    b: f64,
};

fn s5OperationalCoefficients(wavelength_nm: f64) Error!S5Coefficients {
    const a_1 = 4.70194461239e-05;
    const b_1 = 3449239.8849;
    const a0_4 = 4.67913725e-06;
    const a1_4 = -1.26105546e-05;
    const a2_4 = 1.39147643e-05;
    const a3_4 = -5.39067088e-06;
    const b0_4 = -407188.40771951;
    const b1_4 = 1161526.66109376;
    const a0_2 = 3.03796420e-07;
    const a1_2 = -6.81549664e-07;
    const a2_2 = 6.78226603e-07;
    const a3_2 = -2.70807116e-07;
    const b0_2 = 131105.24706965;
    const b1_2 = 15500.79117382;
    const a_3 = 3.7839338322e-07;
    const b_3 = 787116.299872;

    if (wavelength_nm < 270.0 or wavelength_nm > 500.0 or (wavelength_nm > 300.0 and wavelength_nm < 303.0)) {
        return error.UnsupportedS5OperationalRange;
    }
    if (wavelength_nm <= 300.0) {
        return .{ .a = a_1, .b = b_1 };
    }
    if (wavelength_nm >= 303.0 and wavelength_nm <= 310.0) {
        const d = (wavelength_nm - 302.0) / 8.0;
        return .{
            .a = a0_4 + a1_4 * d + a2_4 * d * d + a3_4 * d * d * d,
            .b = b0_4 + b1_4 / d,
        };
    }
    if (wavelength_nm > 310.0 and wavelength_nm < 330.0) {
        const d = (wavelength_nm - 309.0) / 21.0;
        return .{
            .a = a0_2 + a1_2 * d + a2_2 * d * d + a3_2 * d * d * d,
            .b = b0_2 + b1_2 / d,
        };
    }
    return .{ .a = a_3, .b = b_3 };
}

fn interpolateLinearClamped(x: []const f64, y: []const f64, target_x: f64) f64 {
    if (target_x <= x[0]) return y[0];
    if (target_x >= x[x.len - 1]) return y[y.len - 1];
    for (x[0 .. x.len - 1], x[1..], y[0 .. y.len - 1], y[1..]) |left_x, right_x, left_y, right_y| {
        if (target_x < left_x or target_x > right_x) continue;
        const alpha = (target_x - left_x) / (right_x - left_x);
        return (1.0 - alpha) * left_y + alpha * right_y;
    }
    return y[y.len - 1];
}

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

    try std.testing.expectApproxEqRel(@as(f64, 0.282842712), sigma[0], 1.0e-9);
    try std.testing.expectApproxEqRel(@as(f64, 0.141421356), sigma[1], 1.0e-9);
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
