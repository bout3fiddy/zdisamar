pub const Calibration = struct {
    gain: f64 = 1.0,
    offset: f64 = 0.0,
    wavelength_shift_nm: f64 = 0.0,
};

pub fn applySignal(calibration: Calibration, signal: []const f64, output: []f64) !void {
    if (signal.len != output.len) return error.ShapeMismatch;
    for (signal, output) |sample, *slot| {
        slot.* = calibration.gain * sample + calibration.offset;
    }
}

pub fn shiftedWavelength(calibration: Calibration, wavelength_nm: f64) f64 {
    return wavelength_nm + calibration.wavelength_shift_nm;
}

test "calibration applies gain, offset, and wavelength shift" {
    const calibration: Calibration = .{
        .gain = 2.0,
        .offset = -1.0,
        .wavelength_shift_nm = 0.2,
    };
    const signal = [_]f64{ 1.0, 2.0, 3.0 };
    var output: [3]f64 = undefined;

    try applySignal(calibration, &signal, &output);
    try std.testing.expectEqual(@as(f64, 1.0), output[0]);
    try std.testing.expectApproxEqRel(@as(f64, 410.2), shiftedWavelength(calibration, 410.0), 1e-12);
}

const std = @import("std");
