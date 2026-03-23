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
