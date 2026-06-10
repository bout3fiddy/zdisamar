const spectral_calibration = @import("../../instrument_grid/spectral_math/calibration.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

// calibration.zig -------------------------------------------------------------------------------------------|
// Scene-to-simulation adapter for instrument channel calibration controls. The public input model stores     |
// these controls as resolved radiance/irradiance channel settings; instrument-grid code wants the compact    |
// 32 B Calibration row defined by spectral_math/calibration.zig. This file is the only bridge between those  |
// two shapes.                                                                                                |
//                                                                                                            |
// route                                                                                                      |
//   Scene.observation_model.resolvedChannelControls(channel)                                                 |
//     -> calibrationForScene                                                                                 |
//     -> simulate.buildSimulationSetup radiance_calibration / irradiance_calibration                         |
//     -> wavelength_sampling.buildWavelengthSampling, where shiftedWavelength moves channel centers before   |
//        integration kernels and forward-cache misses are planned                                            |
//     -> simulate.fillRadianceSamples / fillIrradianceSamples, where applySignal runs after integrated       |
//        sampling or slit convolution                                                                        |
//     -> simulate radiance-Jacobian postprocess, where applySignalDerivative runs on active state columns    |
//                                                                                                            |
// adapter boundary                                                                                           |
//   This file reads Scene once per channel while setup is being built and returns a value. It does not apply |
//   gain/offset, perform stray-light mixing, shift wavelengths, allocate storage, validate controls, or read |
//   spectral samples. spectral_math/calibration.zig owns the streaming signal math and Calibration row       |
//   layout. input/instrument/pipeline.zig and ObservationModel own request validation and defaults.          |
//                                                                                                            |
// field map                                                                                                  |
//   ObservationModel controls                 Calibration row                                                |
//   multiplicative_offset              ->     gain                                                           |
//   additive_offset                    ->     offset                                                         |
//   wavelength_shift_nm                ->     wavelength_shift_nm                                            |
//   stray_light                        ->     stray_light                                                    |
//                                                                                                            |
// channel contract                                                                                           |
//   Radiance and irradiance can use different controls. The caller asks for one SpectralChannel at a time so |
//   SimulationSetup can keep two copied rows. Wavelength planning reads only wavelength_shift_nm; signal     |
//   postprocess reads gain, offset, and stray_light; derivative postprocess reads gain and stray_light only. |
//                                                                                                            |
// memory and hot path                                                                                        |
//   The returned Calibration is four f64 fields, 32 B, no referenced storage. It is copied by value into     |
//   SimulationSetup and then into WavelengthSamplingWorker rows. This adapter is setup code, outside         |
//   per-sample loops; the hot loops read the copied scalar row and never re-enter Scene resolution.          |
// -----------------------------------------------------------------------------------------------------------|

pub fn calibrationForScene(scene: *const Scene, channel: SpectralChannel) spectral_calibration.Calibration {
    // calibrationForScene -----------------------------------------------------------------------------------|
    // Copy one resolved channel-control row into the scalar calibration layout used by sampling and signal   |
    // postprocess code. No unit conversion happens here: wavelength_shift_nm is already nm, while gain,      |
    // offset, and stray_light are already product-signal controls.                                           |
    //                                                                                                        |
    // call shape                                                                                             |
    //   scene.observation_model.resolvedChannelControls chooses radiance or irradiance controls after input  |
    //   defaults and per-channel overrides have already been resolved.                                       |
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
