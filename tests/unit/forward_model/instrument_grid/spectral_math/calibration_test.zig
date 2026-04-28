const std = @import("std");
const internal = @import("internal");

const calibration = internal.forward_model.instrument_grid.spectral_math.calibration;
const Instrument = internal.instrument.Instrument;
const Calibration = calibration.Calibration;

const applySignal = calibration.applySignal;
const applySignalDerivative = calibration.applySignalDerivative;
const shiftedWavelength = calibration.shiftedWavelength;
const applySimpleOffsets = calibration.applySimpleOffsets;
const applySimpleOffsetDerivatives = calibration.applySimpleOffsetDerivatives;
const applySpectralFeatures = calibration.applySpectralFeatures;
const applySpectralFeatureDerivatives = calibration.applySpectralFeatureDerivatives;
const applySmear = calibration.applySmear;
const applyMultiplicativeNodes = calibration.applyMultiplicativeNodes;
const applyPolarizationScramblerBias = calibration.applyPolarizationScramblerBias;

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

test "calibration derivative helpers carry first-sample additive dependence" {
    const wavelengths = [_]f64{ 760.8, 760.9, 761.0 };
    var signal = [_]f64{ 10.0, 11.0, 12.0 };

    try applySimpleOffsetDerivatives(.{
        .multiplicative_percent = 2.0,
        .additive_percent_of_first = 5.0,
    }, &signal);
    try applySpectralFeatureDerivatives(.{
        .additive_amplitude_percent = 3.0,
        .additive_period_nm = 0.4,
        .multiplicative_amplitude_percent = 1.0,
        .multiplicative_period_nm = 0.4,
    }, &wavelengths, &signal);

    try std.testing.expectApproxEqRel(@as(f64, 10.7), signal[0], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 12.1582), signal[1], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 12.74), signal[2], 1.0e-12);
}

test "calibration helpers apply explicit correction families in sequence" {
    const wavelengths = [_]f64{ 760.8, 761.0, 761.2 };
    var signal = [_]f64{ 10.0, 11.0, 12.0 };
    var scratch: [3]f64 = undefined;

    try applySimpleOffsets(.{ .multiplicative_percent = 2.0, .additive_percent_of_first = 1.0 }, &signal);
    try applySpectralFeatures(.{
        .multiplicative_amplitude_percent = 1.0,
        .multiplicative_period_nm = 0.4,
        .additive_amplitude_percent = 0.5,
        .additive_period_nm = 0.4,
    }, &wavelengths, &signal);
    try applySmear(2.0, &signal, &scratch);
    try applyMultiplicativeNodes(.{
        .wavelengths_nm = &wavelengths,
        .values = &.{ 1.0, 0.0, -1.0 },
        .use_linear_interpolation = true,
    }, &wavelengths, &signal, &scratch);

    try std.testing.expect(signal[0] > 10.0);
    try std.testing.expect(signal[2] > signal[0]);
    _ = Instrument; // keep alias used to ensure the import resolves under -Dno-unused
}

test "smear preserves the leading boundary while cascading into later samples" {
    var signal = [_]f64{ 10.0, 20.0, 30.0 };
    var scratch: [3]f64 = undefined;

    try applySmear(10.0, &signal, &scratch);

    try std.testing.expectApproxEqRel(@as(f64, 10.0), signal[0], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 18.9), signal[1], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 32.1), signal[2], 1.0e-12);
}

test "polarization scrambler bias only perturbs radiance when the scrambler is disabled" {
    const wavelengths = [_]f64{ 760.8, 761.0, 761.2 };
    var disabled_signal = [_]f64{ 10.0, 10.0, 10.0 };
    var enabled_signal = [_]f64{ 10.0, 10.0, 10.0 };

    try applyPolarizationScramblerBias(false, 0.03, &wavelengths, &disabled_signal);
    try applyPolarizationScramblerBias(true, 0.03, &wavelengths, &enabled_signal);

    try std.testing.expect(disabled_signal[0] < 10.0);
    try std.testing.expectApproxEqRel(@as(f64, 10.0), disabled_signal[1], 1.0e-12);
    try std.testing.expect(disabled_signal[2] > 10.0);
    try std.testing.expectEqualSlices(f64, &enabled_signal, &.{ 10.0, 10.0, 10.0 });
}
