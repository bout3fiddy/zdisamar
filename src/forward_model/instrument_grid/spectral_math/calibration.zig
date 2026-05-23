const std = @import("std");

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: gain=8 B, offset=8 B, wavelength_shift_nm=8 B, stray_light=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count
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
//   math: mean = sum(signal) / N; mixed_i = signal_i + stray_light * (mean - signal_i); output_i = gain * mixed_i + offset
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

    // math: d(output_i)/d(signal_i) uses the same stray-light mixture but drops additive offset.
    for (signal, output) |sample, *slot| {
        const stray_mixed = sample + calibration.stray_light * (mean_signal - sample);
        slot.* = calibration.gain * stray_mixed;
    }
}

pub fn shiftedWavelength(calibration: Calibration, wavelength_nm: f64) f64 {
    // math: lambda' = lambda + wavelength_shift_nm
    return wavelength_nm + calibration.wavelength_shift_nm;
}
