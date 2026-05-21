const std = @import("std");
const internal = @import("internal");

const calibration = internal.forward_model.instrument_grid.spectral_math.calibration;
const Calibration = calibration.Calibration;

const applySignal = calibration.applySignal;
const applySignalDerivative = calibration.applySignalDerivative;
const shiftedWavelength = calibration.shiftedWavelength;

test "calibration applies gain, offset, and wavelength shift" {
    const cal: Calibration = .{
        .gain = 2.0,
        .offset = -1.0,
        .wavelength_shift_nm = 0.2,
        .stray_light = 0.25,
    };
    const signal = [_]f64{ 1.0, 2.0, 3.0 };
    var output: [3]f64 = undefined;

    // applySignal mixes a fraction of (mean-sample) into each sample before
    // applying gain/offset. For signal [1,2,3] mean is 2; the resulting
    // outputs are gain*(sample + 0.25*(mean-sample)) + offset.
    try applySignal(cal, &signal, &output);
    try std.testing.expectApproxEqRel(@as(f64, 1.5), output[0], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 3.0), output[1], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 4.5), output[2], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 410.2), shiftedWavelength(cal, 410.0), 1e-12);
}

test "calibration applies only the linear response to signal derivatives" {
    const cal: Calibration = .{
        .gain = 2.0,
        .offset = -1.0,
        .stray_light = 0.25,
    };
    const signal = [_]f64{ 1.0, 2.0, 3.0 };
    var output: [3]f64 = undefined;

    try applySignalDerivative(cal, &signal, &output);
    try std.testing.expectApproxEqRel(@as(f64, 2.5), output[0], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 4.0), output[1], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 5.5), output[2], 1.0e-12);
}
