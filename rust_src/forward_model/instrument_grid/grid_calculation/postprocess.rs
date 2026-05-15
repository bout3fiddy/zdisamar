use crate::{
    forward_model::{
        implementations::noise,
        instrument_grid::spectral_math::calibration::{self, Calibration},
    },
    input::{instrument::SpectralChannel, scene::Scene},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    Calibration(calibration::Error),
    Noise(noise::Error),
}

impl From<calibration::Error> for Error {
    fn from(value: calibration::Error) -> Self {
        Self::Calibration(value)
    }
}

impl From<noise::Error> for Error {
    fn from(value: noise::Error) -> Self {
        Self::Noise(value)
    }
}

pub fn materialize_channel_sigma(
    noise: noise::Implementation,
    scene: &Scene,
    channel: SpectralChannel,
    wavelengths_nm: &[f64],
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    if (noise.materializes_sigma)(scene, channel) {
        (noise.materialize_sigma)(scene, channel, wavelengths_nm, signal, output)?;
    } else {
        output.fill(0.0);
    }
    Ok(())
}

pub fn apply_channel_corrections(
    scene: &Scene,
    channel: SpectralChannel,
    calibration_config: Calibration,
    depolarization_factor: f64,
    wavelengths_nm: &[f64],
    signal: &mut [f64],
    scratch: &mut [f64],
) -> Result<(), Error> {
    let controls = scene.observation_model.resolved_channel_controls(channel);
    calibration::apply_signal(calibration_config, signal, scratch)?;
    signal.copy_from_slice(scratch);
    calibration::apply_simple_offsets(controls.simple_offsets, signal);
    calibration::apply_spectral_features(controls.spectral_features, wavelengths_nm, signal)?;
    if controls.smear_percent != 0.0 {
        calibration::apply_smear(controls.smear_percent, signal, scratch)?;
    }
    calibration::apply_multiplicative_nodes(
        &controls.multiplicative_nodes,
        wavelengths_nm,
        signal,
        scratch,
    )?;
    if controls.stray_light_nodes.enabled() {
        let reference = if controls.stray_light_nodes.use_reference_spectrum {
            correction_reference_signal(
                scene,
                &controls.noise.reference_signal,
                channel,
                signal.len(),
            )
        } else {
            None
        };
        if let Some(reference_signal) = reference {
            calibration::apply_stray_light_nodes(
                &controls.stray_light_nodes,
                wavelengths_nm,
                reference_signal,
                signal,
                scratch,
            )?;
        } else {
            // The current signal can be its own stray-light reference in Zig.
            // Rust needs a snapshot so the correction can read old values while writing new ones.
            let source_signal = signal.to_vec();
            calibration::apply_stray_light_nodes(
                &controls.stray_light_nodes,
                wavelengths_nm,
                &source_signal,
                signal,
                scratch,
            )?;
        }
    }
    if channel == SpectralChannel::Radiance {
        calibration::apply_polarization_scrambler_bias(
            controls.use_polarization_scrambler,
            depolarization_factor,
            wavelengths_nm,
            signal,
        )?;
    }
    Ok(())
}

pub fn apply_channel_jacobian_corrections(
    scene: &Scene,
    channel: SpectralChannel,
    calibration_config: Calibration,
    depolarization_factor: f64,
    wavelengths_nm: &[f64],
    jacobian: &mut [f64],
    scratch: &mut [f64],
) -> Result<(), Error> {
    let controls = scene.observation_model.resolved_channel_controls(channel);
    calibration::apply_signal_derivative(calibration_config, jacobian, scratch)?;
    jacobian.copy_from_slice(scratch);
    calibration::apply_simple_offset_derivatives(controls.simple_offsets, jacobian);
    calibration::apply_spectral_feature_derivatives(
        controls.spectral_features,
        wavelengths_nm,
        jacobian,
    )?;
    if controls.smear_percent != 0.0 {
        calibration::apply_smear(controls.smear_percent, jacobian, scratch)?;
    }
    calibration::apply_multiplicative_nodes(
        &controls.multiplicative_nodes,
        wavelengths_nm,
        jacobian,
        scratch,
    )?;

    let external_reference = correction_reference_signal(
        scene,
        &controls.noise.reference_signal,
        channel,
        jacobian.len(),
    );
    if controls.stray_light_nodes.enabled()
        && (!controls.stray_light_nodes.use_reference_spectrum || external_reference.is_none())
    {
        let source_jacobian = jacobian.to_vec();
        calibration::apply_stray_light_nodes(
            &controls.stray_light_nodes,
            wavelengths_nm,
            &source_jacobian,
            jacobian,
            scratch,
        )?;
    }
    if channel == SpectralChannel::Radiance {
        calibration::apply_polarization_scrambler_bias(
            controls.use_polarization_scrambler,
            depolarization_factor,
            wavelengths_nm,
            jacobian,
        )?;
    }
    Ok(())
}

pub fn correction_reference_signal<'a>(
    scene: &'a Scene,
    channel_reference_signal: &'a [f64],
    channel: SpectralChannel,
    sample_count: usize,
) -> Option<&'a [f64]> {
    if channel_reference_signal.len() == sample_count {
        return Some(channel_reference_signal);
    }
    if channel == SpectralChannel::Radiance
        && scene.observation_model.reference_radiance.len() == sample_count
    {
        return Some(&scene.observation_model.reference_radiance);
    }
    None
}
