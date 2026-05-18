const std = @import("std");
const Instrument = @import("../../../input/Instrument.zig").Instrument;
const sampling = @import("sampling.zig");

pub const Calibration = struct {
    gain: f64 = 1.0,
    offset: f64 = 0.0,
    wavelength_shift_nm: f64 = 0.0,
    stray_light: f64 = 0.0,
};

// hot path:
//   when: every radiance/irradiance channel applies basic calibration
//   work: computes channel mean for stray-light mixing and applies gain/offset per sample
//   data: signal array, output array, calibration scalar fields
//   follow: postprocess.applyChannelCorrections and applySignalDerivative
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

pub fn shiftedWavelength(calibration: Calibration, wavelength_nm: f64) f64 {
    return wavelength_nm + calibration.wavelength_shift_nm;
}

pub fn applySimpleOffsets(offsets: Instrument.SimpleOffsets, signal: []f64) !void {
    if (signal.len == 0) return;
    const reference = signal[0];
    for (signal) |*sample| {
        sample.* = (1.0 + 0.01 * offsets.multiplicative_percent) * sample.*;
        sample.* += 0.01 * offsets.additive_percent_of_first * reference;
    }
}

pub fn applySimpleOffsetDerivatives(offsets: Instrument.SimpleOffsets, signal: []f64) !void {
    try applySimpleOffsets(offsets, signal);
}

// hot path:
//   when: channel controls request sinusoidal spectral features
//   work: applies additive and multiplicative sinusoidal terms across wavelengths
//   data: wavelength array, signal array, feature amplitudes/periods/phases
//   follow: derivative mirror path and channel postprocess ordering
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

pub fn applySpectralFeatureDerivatives(
    features: Instrument.SinusoidalFeatures,
    wavelengths_nm: []const f64,
    signal: []f64,
) !void {
    try applySpectralFeatures(features, wavelengths_nm, signal);
}

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

// hot path:
//   when: nodal multiplicative calibration is enabled for a channel
//   work: samples node corrections and writes adjusted signal through scratch
//   data: wavelength array, signal array, correction nodes, scratch array
//   follow: sampleCorrection/sampleLinear access pattern
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

// hot path:
//   when: nodal stray-light calibration is enabled for a channel
//   work: samples source signal at correction nodes and adds interpolated stray-light contribution
//   data: wavelength array, source signal, signal array, node values, scratch array
//   follow: sampleLinear and sampleCorrection interpolation loops
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

// hot path:
//   when: ring correction is enabled after radiance/irradiance postprocess
//   work: synthesizes or reads ring basis values and updates radiance per wavelength
//   data: wavelength array, irradiance array, radiance array, ring controls, scratch array
//   follow: synthesizedDifferentialRing and synthesizedFullRing paths
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

// hot path:
//   when: reflectance noise sigma includes calibration-error terms
//   work: samples multiplicative/additive calibration nodes and combines variance into sigma
//   data: wavelength array, reflectance array, sigma array, node values, scratch array
//   follow: materializeNoiseSamples and sampleCorrection interpolation
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
