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

const std = @import("std");
const Instrument = @import("../../model/Instrument.zig").Instrument;
const sampling = @import("sampling.zig");

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
///   Apply only the linear detector-response terms to a signal derivative.
pub fn applySignalDerivative(calibration: Calibration, signal: []const f64, output: []f64) !void {
    if (signal.len != output.len) return error.ShapeMismatch;
    if (signal.len == 0) return;

    var mean_signal: f64 = 0.0;
    for (signal) |sample| mean_signal += sample;
    mean_signal /= @as(f64, @floatFromInt(signal.len));

    for (signal, output) |sample, *slot| {
        const stray_mixed = sample + calibration.stray_light * (mean_signal - sample);
        slot.* = calibration.gain * stray_mixed;
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

/// Purpose:
///   Apply vendor-style simple multiplicative and additive offsets in-place.
pub fn applySimpleOffsets(offsets: Instrument.SimpleOffsets, signal: []f64) !void {
    if (signal.len == 0) return;
    const reference = signal[0];
    for (signal) |*sample| {
        sample.* = (1.0 + 0.01 * offsets.multiplicative_percent) * sample.*;
        sample.* += 0.01 * offsets.additive_percent_of_first * reference;
    }
}

/// Purpose:
///   Apply the simple-offset derivative, including the shared first-sample additive term.
pub fn applySimpleOffsetDerivatives(offsets: Instrument.SimpleOffsets, signal: []f64) !void {
    try applySimpleOffsets(offsets, signal);
}

/// Purpose:
///   Apply sinusoidal additive and multiplicative features relative to the first wavelength.
pub fn applySpectralFeatures(
    features: Instrument.SinusoidalFeatures,
    wavelengths_nm: []const f64,
    signal: []f64,
) !void {
    if (wavelengths_nm.len != signal.len) return error.ShapeMismatch;
    if (signal.len == 0) return;

    const first_wavelength = wavelengths_nm[0];
    const reference_signal = signal[0];
    for (wavelengths_nm, signal) |wavelength_nm, *sample| {
        const delta_nm = wavelength_nm - first_wavelength;
        var additive_term: f64 = 0.0;
        var multiplicative_term: f64 = 0.0;
        if (features.additive_amplitude_percent != 0.0) {
            additive_term = reference_signal * 0.01 * features.additive_amplitude_percent *
                @sin((delta_nm * 2.0 * std.math.pi / features.additive_period_nm) + std.math.degreesToRadians(features.additive_phase_deg));
        }
        if (features.multiplicative_amplitude_percent != 0.0) {
            multiplicative_term = 0.01 * features.multiplicative_amplitude_percent *
                @sin((delta_nm * 2.0 * std.math.pi / features.multiplicative_period_nm) + std.math.degreesToRadians(features.multiplicative_phase_deg));
        }
        sample.* = sample.* * (1.0 + multiplicative_term) + additive_term;
    }
}

/// Purpose:
///   Apply the sinusoidal-feature derivative, including any first-sample additive term.
pub fn applySpectralFeatureDerivatives(
    features: Instrument.SinusoidalFeatures,
    wavelengths_nm: []const f64,
    signal: []f64,
) !void {
    try applySpectralFeatures(features, wavelengths_nm, signal);
}

/// Purpose:
///   Apply the vendor-style smear model by moving a percentage of each sample to its neighbor.
pub fn applySmear(percent_smear: f64, signal: []f64, scratch: []f64) !void {
    if (signal.len != scratch.len) return error.ShapeMismatch;
    if (signal.len < 2) return;

    @memcpy(scratch, signal);
    const first = signal[0];
    for (0..signal.len - 1) |index| {
        const smear = 0.01 * percent_smear * scratch[index];
        scratch[index] -= smear;
        scratch[index + 1] += smear;
    }
    scratch[0] = first;
    @memcpy(signal, scratch);
}

/// Purpose:
///   Add a multiplicative offset spectrum defined by nodal percentages.
pub fn applyMultiplicativeNodes(
    correction: Instrument.NodalCorrection,
    wavelengths_nm: []const f64,
    signal: []f64,
    scratch: []f64,
) !void {
    if (wavelengths_nm.len != signal.len or signal.len != scratch.len) return error.ShapeMismatch;
    if (!correction.enabled()) return;

    for (wavelengths_nm, signal, scratch) |wavelength_nm, sample, *slot| {
        const percent = try sampleCorrection(correction, correction.values, wavelength_nm);
        slot.* = sample + (0.01 * percent * sample);
    }
    @memcpy(signal, scratch);
}

/// Purpose:
///   Add a wavelength-dependent stray-light spectrum defined by nodal percentages.
pub fn applyStrayLightNodes(
    correction: Instrument.NodalCorrection,
    wavelengths_nm: []const f64,
    source_signal: []const f64,
    signal: []f64,
    scratch: []f64,
) !void {
    if (wavelengths_nm.len != source_signal.len or source_signal.len != signal.len or signal.len != scratch.len) {
        return error.ShapeMismatch;
    }
    if (!correction.enabled()) return;

    var node_values: [64]f64 = undefined;
    if (correction.values.len > node_values.len) return error.ShapeMismatch;
    for (0..correction.values.len) |index| {
        const base = try sampleLinear(wavelengths_nm, source_signal, correction.wavelengths_nm[index]);
        const bias = if (index < correction.characteristic_bias.len) correction.characteristic_bias[index] else 1.0;
        node_values[index] = 0.01 * correction.values[index] * base * bias;
    }

    for (wavelengths_nm, signal, scratch) |wavelength_nm, sample, *slot| {
        const additive = try sampleCorrection(correction, node_values[0..correction.values.len], wavelength_nm);
        slot.* = sample + additive;
    }
    @memcpy(signal, scratch);
}

/// Purpose:
///   Add an explicit or synthesized Ring spectrum to the radiance.
pub fn applyRingSpectrum(
    ring: Instrument.RingControls,
    wavelengths_nm: []const f64,
    irradiance: []const f64,
    radiance: []f64,
    scratch: []f64,
) !void {
    if (wavelengths_nm.len != irradiance.len or irradiance.len != radiance.len or radiance.len != scratch.len) {
        return error.ShapeMismatch;
    }
    if (!ring.enabled or radiance.len == 0) return;

    if (ring.spectrum.len != 0 and ring.spectrum.len != radiance.len) return error.ShapeMismatch;
    const effective_coefficient = ring.coefficient * ring.fraction_raman_lines;
    const mean_irradiance = if (ring.spectrum.len == 0 and !ring.differential)
        spectralMean(irradiance)
    else
        0.0;
    for (0..radiance.len) |index| {
        const basis = if (ring.spectrum.len == radiance.len)
            ring.spectrum[index]
        else if (ring.differential)
            synthesizedDifferentialRing(irradiance, index)
        else
            synthesizedFullRing(mean_irradiance, irradiance[index]);
        scratch[index] = radiance[index] + effective_coefficient * basis * irradiance[index];
    }
    @memcpy(radiance, scratch);
}

/// Purpose:
///   Apply a scalar radiance bias when the polarization scrambler is disabled.
///
/// Physics:
///   The vendor path adds a wavelength-dependent leakage term proportional to
///   the polarized component of the measured radiance. The current Zig forward
///   engine is scalar, so it does not materialize Stokes `Q/U`. This helper
///   therefore applies a small deterministic leakage profile whose amplitude is
///   bounded by the prepared depolarization factor.
///
/// Vendor:
///   `radianceIrradianceModule::ignorePolarizationScrambler`
///
/// Decisions:
///   Use an explicit scalar approximation instead of silently ignoring the
///   control. The leakage profile is zero-mean across the band and only applies
///   when the caller explicitly disables the scrambler.
pub fn applyPolarizationScramblerBias(
    use_polarization_scrambler: bool,
    depolarization_factor: f64,
    wavelengths_nm: []const f64,
    signal: []f64,
) !void {
    if (wavelengths_nm.len != signal.len) return error.ShapeMismatch;
    if (use_polarization_scrambler or signal.len == 0) return;
    if (!std.math.isFinite(depolarization_factor) or depolarization_factor <= 0.0 or signal.len == 1) return;

    const start_nm = wavelengths_nm[0];
    const end_nm = wavelengths_nm[wavelengths_nm.len - 1];
    const center_nm = 0.5 * (start_nm + end_nm);
    const half_span_nm = @max(0.5 * (end_nm - start_nm), 1.0e-9);
    const leakage_scale = 0.35 * depolarization_factor;

    for (wavelengths_nm, signal) |wavelength_nm, *sample| {
        const normalized_offset = (wavelength_nm - center_nm) / half_span_nm;
        sample.* *= 1.0 + (leakage_scale * normalized_offset);
    }
}

/// Purpose:
///   Fold reflectance calibration-error nodes into the reflectance sigma in quadrature.
pub fn applyReflectanceCalibrationErrorSigma(
    calibration_error: Instrument.ReflectanceCalibration,
    wavelengths_nm: []const f64,
    reflectance: []const f64,
    sigma: []f64,
    scratch: []f64,
) !void {
    if (wavelengths_nm.len != reflectance.len or reflectance.len != sigma.len or sigma.len != scratch.len) {
        return error.ShapeMismatch;
    }
    if (!calibration_error.multiplicative_error.enabled() and !calibration_error.additive_error.enabled()) {
        return;
    }

    @memset(scratch, 0.0);
    if (calibration_error.multiplicative_error.enabled()) {
        for (wavelengths_nm, reflectance, scratch) |wavelength_nm, reflectance_value, *slot| {
            const percent = try sampleCorrection(calibration_error.multiplicative_error, calibration_error.multiplicative_error.values, wavelength_nm);
            slot.* += std.math.pow(f64, reflectance_value * percent / 100.0, 2.0);
        }
    }
    if (calibration_error.additive_error.enabled()) {
        var node_values: [64]f64 = undefined;
        if (calibration_error.additive_error.values.len > node_values.len) return error.ShapeMismatch;
        for (0..calibration_error.additive_error.values.len) |index| {
            const reflectance_at_node = try sampleLinear(wavelengths_nm, reflectance, calibration_error.additive_error.wavelengths_nm[index]);
            node_values[index] = reflectance_at_node * calibration_error.additive_error.values[index] / 100.0;
        }
        for (wavelengths_nm, scratch) |wavelength_nm, *slot| {
            const additive_sigma = try sampleCorrection(calibration_error.additive_error, node_values[0..calibration_error.additive_error.values.len], wavelength_nm);
            slot.* += additive_sigma * additive_sigma;
        }
    }

    for (sigma, scratch) |*sigma_value, systematic_variance| {
        sigma_value.* = std.math.sqrt(sigma_value.* * sigma_value.* + systematic_variance);
    }
}

fn sampleCorrection(
    correction: Instrument.NodalCorrection,
    values: []const f64,
    wavelength_nm: f64,
) !f64 {
    if (correction.wavelengths_nm.len == 0 or values.len == 0) return 0.0;
    if (correction.wavelengths_nm.len != values.len) return error.ShapeMismatch;
    if (values.len == 1) return values[0];
    if (correction.use_linear_interpolation) {
        return sampleLinear(correction.wavelengths_nm, values, wavelength_nm);
    }
    return samplePolynomial(correction.wavelengths_nm, values, wavelength_nm);
}

fn sampleLinear(x: []const f64, y: []const f64, target_x: f64) !f64 {
    return sampling.sampleLinearClamped(x, y, target_x);
}

fn samplePolynomial(x: []const f64, y: []const f64, target_x: f64) !f64 {
    if (x.len != y.len) return error.ShapeMismatch;
    if (x.len == 0) return error.ShapeMismatch;
    if (x.len == 1) return y[0];

    var total: f64 = 0.0;
    for (x, y, 0..) |xi, yi, i| {
        var basis: f64 = 1.0;
        for (x, 0..) |xj, j| {
            if (i == j) continue;
            basis *= (target_x - xj) / (xi - xj);
        }
        total += yi * basis;
    }
    return total;
}

fn synthesizedDifferentialRing(irradiance: []const f64, index: usize) f64 {
    if (irradiance.len == 1) return 0.0;
    const left = if (index == 0) irradiance[0] else irradiance[index - 1];
    const right = if (index + 1 >= irradiance.len) irradiance[irradiance.len - 1] else irradiance[index + 1];
    return (left - right) / @max(irradiance[index], 1.0e-12);
}

fn synthesizedFullRing(mean_irradiance: f64, irradiance: f64) f64 {
    return (mean_irradiance - irradiance) / @max(mean_irradiance, 1.0e-12);
}

fn spectralMean(values: []const f64) f64 {
    var mean_value: f64 = 0.0;
    for (values) |value| mean_value += value;
    return mean_value / @as(f64, @floatFromInt(values.len));
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

test "calibration applies only the linear response to signal derivatives" {
    const calibration: Calibration = .{
        .gain = 2.0,
        .offset = -1.0,
        .stray_light = 0.25,
    };
    const signal = [_]f64{ 1.0, 2.0, 3.0 };
    var output: [3]f64 = undefined;

    try applySignalDerivative(calibration, &signal, &output);
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
