const std = @import("std");

// calibration.zig -------------------------------------------------------------------------------------------------------|
// Scalar channel calibration for measurement-space arrays. The sampling path computes raw radiance, irradiance,          |
// and active Jacobian columns first; this file applies per-channel correction after integration/convolution.             |
//                                                                                                                        |
// called by                                                                                                              |
//   grid_calculation/simulate.zig after integrated sampling or slit convolution for radiance and irradiance.             |
//   The same simulation route applies applySignalDerivative to active state-major Jacobian columns.                      |
//   wavelength_sampling.zig uses shiftedWavelength while writing retained sampling rows for radiance/irradiance.         |
//                                                                                                                        |
// main paths                                                                                                             |
//   applySignal           -> gain/offset plus stray-light mixing for measured signal arrays                              |
//   applySignalDerivative -> derivative-column calibration without additive offset                                       |
//   shiftedWavelength     -> channel-specific wavelength shift before integration planning                               |
//                                                                                                                        |
// hot path                                                                                                               |
//   applySignal walks one output channel array after each spectrum is gathered. applySignalDerivative walks each         |
//   active Jacobian column after optional convolution. Both helpers compute a channel mean first, then write the         |
//   corrected samples in place when caller input and output slices are the same.                                         |
//                                                                                                                        |
// memory                                                                                                                 |
//   Calibration is a 32 B value copied into simulation setup and wavelength-sampling setup rows. It owns no              |
//   storage, so repeated loops read four scalar f64 controls and stream caller-owned slices.                             |
// -----------------------------------------------------------------------------------------------------------------------|

// Calibration -----------------------------------------------------------------------------------------------------------|
// Four scalar channel corrections kept together so radiance and irradiance paths can pass one small value.               |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 32 B (0.031 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] gain                : f64                                                                                     |
// [ 8..15] offset              : f64                                                                                     |
// [16..23] wavelength_shift_nm : f64                                                                                     |
// [24..31] stray_light         : f64                                                                                     |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count                                 |
pub const Calibration = struct {
    gain: f64 = 1.0,
    offset: f64 = 0.0,
    wavelength_shift_nm: f64 = 0.0,
    stray_light: f64 = 0.0,
};
// -----------------------------------------------------------------------------------------------------------------------|

pub fn applySignal(calibration: Calibration, signal: []const f64, output: []f64) !void {
    // applySignal -------------------------------------------------------------------------------------------------------|
    // Apply channel calibration to one signal array. The signal and output slices may be the same slice.                 |
    //                                                                                                                    |
    // math                                                                                                               |
    //   mean     = sum(signal) / N                                                                                       |
    //   mixed_i  = signal_i + stray_light * (mean - signal_i)                                                            |
    //   output_i = gain * mixed_i + offset                                                                               |
    //                                                                                                                    |
    // equivalent form                                                                                                    |
    //   output_i = gain * ((1 - stray_light) * signal_i + stray_light * mean) + offset                                   |
    //                                                                                                                    |
    // why                                                                                                                |
    //   Stray light pulls each sample toward the channel mean. stray_light = 0 keeps the original signal;                |
    //   stray_light = 1 replaces every sample with the channel mean before gain and offset are applied.                  |
    // -------------------------------------------------------------------------------------------------------------------|

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
    // applySignalDerivative ---------------------------------------------------------------------------------------------|
    // Apply the linear part of channel calibration to one derivative column. The derivative column is already            |
    // d(signal_i)/dx for one state x.                                                                                    |
    //                                                                                                                    |
    // math                                                                                                               |
    //   mean_dx      = sum(dsignal_i/dx) / N                                                                             |
    //   doutput_i/dx = gain * (dsignal_i/dx + stray_light * (mean_dx - dsignal_i/dx))                                    |
    //                                                                                                                    |
    // why                                                                                                                |
    //   The additive offset drops out because d(offset)/dx = 0. Stray light still couples each derivative                |
    //   row to the mean derivative across the channel.                                                                   |
    // -------------------------------------------------------------------------------------------------------------------|

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
    // shiftedWavelength -------------------------------------------------------------------------------------------------|
    // Apply the channel wavelength shift used before instrument integration kernels are built.                           |
    //                                                                                                                    |
    // math                                                                                                               |
    //   lambda' = lambda + wavelength_shift_nm                                                                           |
    // -------------------------------------------------------------------------------------------------------------------|

    return wavelength_nm + calibration.wavelength_shift_nm;
}
