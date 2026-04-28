const calibration = @import("../../instrument_grid/spectral_math/calibration.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

pub const Calibration = calibration.Calibration;

pub fn calibrationForScene(scene: *const Scene, channel: SpectralChannel) calibration.Calibration {
    const controls = scene.observation_model.resolvedChannelControls(channel);
    return .{
        .gain = controls.multiplicative_offset,
        .offset = controls.additive_offset,
        .wavelength_shift_nm = controls.wavelength_shift_nm,
        .stray_light = controls.stray_light,
    };
}
