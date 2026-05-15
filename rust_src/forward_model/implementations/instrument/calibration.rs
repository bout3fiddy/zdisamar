use crate::{
    forward_model::instrument_grid::spectral_math::calibration::Calibration,
    input::{instrument::SpectralChannel, scene::Scene},
};

pub fn calibration_for_scene(scene: &Scene, channel: SpectralChannel) -> Calibration {
    let controls = scene.observation_model.resolved_channel_controls(channel);
    Calibration {
        gain: controls.multiplicative_offset,
        offset: controls.additive_offset,
        wavelength_shift_nm: controls.wavelength_shift_nm,
        stray_light: controls.stray_light,
    }
}
