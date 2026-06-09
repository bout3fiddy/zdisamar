const spectral_calibration = @import("../../instrument_grid/spectral_math/calibration.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

// calibration.zig -------------------------------------------------------------------------------------------|
// Adapter from observation-model channel controls to instrument-grid calibration math.                       |
//                                                                                                            |
// called by                                                                                                  |
//   grid_calculation/simulate.zig while building the product simulation setup for radiance and irradiance    |
//   wavelength_sampling.zig when shifted channel centers are stored in retained sampling rows                |
//                                                                                                            |
// output contract                                                                                            |
//   The returned Calibration row carries wavelength shift, multiplicative gain, additive offset, and         |
//   stray-light mixing. Simulation applies it after high-resolution gather and optional slit convolution.    |
//                                                                                                            |
// math                                                                                                       |
//   y' = gain * (y + stray_light * (mean(y) - y)) + offset                                                   |
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
