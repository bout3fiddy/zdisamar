const spectral_calibration = @import("../../instrument_grid/spectral_math/calibration.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

// calibration.zig -------------------------------------------------------------------------------------------|
// Translates resolved scene channel controls into the 32 B instrument-grid Calibration row.                  |
//                                                                                                            |
// called by                                                                                                  |
//   grid_calculation/simulate.zig calls calibrationForScene while building SimulationSetup for radiance and  |
//   irradiance. wavelength_sampling.zig receives the same two Calibration rows so shifted channel centers    |
//   are retained next to the integration kernels for each nominal wavelength.                                |
//                                                                                                            |
// adapter boundary                                                                                           |
//   This file reads resolved ObservationModel channel controls and copies four scalar fields into            |
//   spectral_math/calibration.Calibration. It does not apply gain/offset, perform stray-light mixing, or     |
//   shift any wavelength itself; spectral_math/calibration.zig owns that streaming math.                     |
//                                                                                                            |
// channel contract                                                                                           |
//   Radiance and irradiance can use different controls. Each returned row carries wavelength_shift_nm, gain, |
//   offset, and stray_light so simulation setup can pass one compact value through sampling and postprocess  |
//   loops without repeatedly reading the Scene.                                                              |
//                                                                                                            |
// memory                                                                                                     |
//   Calibration owns no referenced storage. This adapter runs during setup; repeated sampling loops read the |
//   copied scalar row from SimulationSetup and WavelengthSampling rows.                                      |
// -----------------------------------------------------------------------------------------------------------|

pub fn calibrationForScene(scene: *const Scene, channel: SpectralChannel) spectral_calibration.Calibration {
    // calibrationForScene -----------------------------------------------------------------------------------|
    // Copy one resolved channel-control row into the scalar calibration layout used by sampling code.        |
    //                                                                                                        |
    // field map                                                                                              |
    //   multiplicative_offset -> gain                                                                        |
    //   additive_offset       -> offset                                                                      |
    //   wavelength_shift_nm   -> wavelength_shift_nm                                                         |
    //   stray_light           -> stray_light                                                                 |
    // -------------------------------------------------------------------------------------------------------|

    const controls = scene.observation_model.resolvedChannelControls(channel);
    return .{
        .gain = controls.multiplicative_offset,
        .offset = controls.additive_offset,
        .wavelength_shift_nm = controls.wavelength_shift_nm,
        .stray_light = controls.stray_light,
    };
}
