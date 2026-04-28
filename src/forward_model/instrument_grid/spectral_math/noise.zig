const std = @import("std");
const sampling = @import("sampling.zig");

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

pub fn whitenResiduals(residual: []const f64, sigma: []const f64, output: []f64) Error!void {
    if (residual.len != sigma.len or residual.len != output.len) return error.ShapeMismatch;
    for (residual, sigma, output) |value, sigma_value, *slot| {
        if (!std.math.isFinite(sigma_value) or sigma_value <= 0.0) {
            return error.SingularWhiteningWeight;
        }
        slot.* = value / sigma_value;
    }
}

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
        const snr_value = snr_values[0];
        if (!std.math.isFinite(snr_value) or snr_value <= 0.0) return error.InvalidNoiseScaleFactor;
        for (signal, output) |signal_value, *slot| {
            if (!std.math.isFinite(signal_value) or signal_value < 0.0) return error.InvalidReferenceSignal;
            slot.* = signal_value / snr_value;
        }
        return;
    }
    for (wavelengths_nm, signal, output) |wavelength_nm, signal_value, *slot| {
        if (!std.math.isFinite(signal_value) or signal_value < 0.0) return error.InvalidReferenceSignal;
        const snr_value = sampling.sampleLinearClampedAssumeValid(snr_wavelengths_nm, snr_values, wavelength_nm);
        if (!std.math.isFinite(snr_value) or snr_value <= 0.0) return error.InvalidNoiseScaleFactor;
        slot.* = signal_value / snr_value;
    }
}

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
