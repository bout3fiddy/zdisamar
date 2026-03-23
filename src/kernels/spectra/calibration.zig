//! Purpose:
//!   Apply simple spectral calibration adjustments to sampled signals and wavelength coordinates.
//!
//! Physics:
//!   Models gain, offset, stray-light mixing, and a constant wavelength shift.
//!
//! Vendor:
//!   `spectral calibration`
//!
//! Design:
//!   The calibration struct stays intentionally small so calibration state can be threaded explicitly.
//!
//! Invariants:
//!   Signal and output arrays must match, and wavelength shifts are treated as a constant offset in nanometers.
//!
//! Validation:
//!   Tests cover gain, offset, stray-light mixing, and shifted wavelength output.

/// Purpose:
///   Store simple calibration controls for detector response and wavelength shift.
pub const Calibration = struct {
    gain: f64 = 1.0,
    offset: f64 = 0.0,
    wavelength_shift_nm: f64 = 0.0,
    stray_light: f64 = 0.0,
};

/// Purpose:
///   Apply gain, offset, and stray-light mixing to a sampled spectral signal.
///
/// Physics:
///   Mixes each sample toward the mean before applying a linear detector calibration.
///
/// Vendor:
///   `signal calibration`
///
/// Units:
///   `wavelength_shift_nm` is a wavelength correction in nanometers.
pub fn applySignal(calibration: Calibration, signal: []const f64, output: []f64) !void {
    if (signal.len != output.len) return error.ShapeMismatch;
    if (signal.len == 0) return;

    var mean_signal: f64 = 0.0;
    for (signal) |sample| mean_signal += sample;
    mean_signal /= @as(f64, @floatFromInt(signal.len));

    for (signal, output) |sample, *slot| {
        const stray_mixed = sample + calibration.stray_light * (mean_signal - sample);
        slot.* = calibration.gain * stray_mixed + calibration.offset;
    }
}

/// Purpose:
///   Shift a wavelength by the configured calibration offset.
///
/// Physics:
///   Applies a constant detector wavelength correction in nanometers.
///
/// Vendor:
///   `wavelength shift`
pub fn shiftedWavelength(calibration: Calibration, wavelength_nm: f64) f64 {
    return wavelength_nm + calibration.wavelength_shift_nm;
}

test "calibration applies gain, offset, and wavelength shift" {
    const calibration: Calibration = .{
        .gain = 2.0,
        .offset = -1.0,
        .wavelength_shift_nm = 0.2,
        .stray_light = 0.25,
    };
    const signal = [_]f64{ 1.0, 2.0, 3.0 };
    var output: [3]f64 = undefined;

    try applySignal(calibration, &signal, &output);
    try std.testing.expectEqual(@as(f64, 2.0), output[0]);
    try std.testing.expectEqual(@as(f64, 3.0), output[1]);
    try std.testing.expectEqual(@as(f64, 4.0), output[2]);
    try std.testing.expectApproxEqRel(@as(f64, 410.2), shiftedWavelength(calibration, 410.0), 1e-12);
}

const std = @import("std");
