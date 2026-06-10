const spectral_calibration = @import("../../instrument_grid/spectral_math/calibration.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

// calibration.zig -------------------------------------------------------------------------------------------|
// Adapter from resolved observation-model channel controls to instrument-grid calibration math.              |
//                                                                                                            |
// called by                                                                                                  |
//   grid_calculation/simulate.zig calls this while building SimulationSetup for radiance and irradiance.     |
//   wavelength_sampling.zig receives the same Calibration rows so shifted channel centers can be retained    |
//   beside integration kernels.                                                                              |
//                                                                                                            |
// output contract                                                                                            |
//   The returned Calibration row carries wavelength shift, multiplicative gain, additive offset, and         |
//   stray-light mixing. Simulation applies it after high-resolution gather and optional slit convolution.    |
//                                                                                                            |
// math                                                                                                       |
//   y' = gain * (y + stray_light * (mean(y) - y)) + offset                                                   |
//                                                                                                            |
// memory                                                                                                     |
//   Calibration is a 32 B value with no referenced storage. This adapter reads resolved controls once during |
//   setup; repeated sampling loops use the copied scalar row.                                                |
// -----------------------------------------------------------------------------------------------------------|

pub fn calibrationForScene(scene: *const Scene, channel: SpectralChannel) spectral_calibration.Calibration {
    const controls = scene.observation_model.resolvedChannelControls(channel);

    // Channel correction applies shifted wavelengths and gain/offset after
    // stray-light mixing: y' = gain * (y + s * (mean(y) - y)) + offset.
    return .{
        .gain = controls.multiplicative_offset,
        .offset = controls.additive_offset,
        .wavelength_shift_nm = controls.wavelength_shift_nm,
        .stray_light = controls.stray_light,
    };
}
