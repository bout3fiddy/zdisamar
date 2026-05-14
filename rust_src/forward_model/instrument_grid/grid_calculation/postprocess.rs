use crate::{
    forward_model::{
        implementations::{self, noise},
        instrument_grid::spectral_math::calibration,
    },
    input::{Scene, SpectralChannel},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ShapeMismatch,
    Noise,
}

pub type Result<T> = std::result::Result<T, Error>;

impl From<calibration::Error> for Error {
    fn from(_: calibration::Error) -> Self {
        Self::ShapeMismatch
    }
}

impl From<noise::Error> for Error {
    fn from(_: noise::Error) -> Self {
        Self::Noise
    }
}

pub fn materialize_channel_sigma(
    implementations: implementations::Bindings,
    scene: &Scene,
    channel: SpectralChannel,
    wavelengths_nm: &[f64],
    signal: &[f64],
    output: &mut [f64],
) -> Result<()> {
    if (implementations.noise.materializes_sigma)(scene, channel) {
        (implementations.noise.materialize_sigma)(scene, channel, wavelengths_nm, signal, output)?;
    } else {
        output.fill(0.0);
    }
    Ok(())
}

pub fn apply_channel_corrections(
    scene: &Scene,
    channel: SpectralChannel,
    calibration_config: calibration::Calibration,
    depolarization_factor: f64,
    wavelengths_nm: &[f64],
    signal: &mut [f64],
    scratch: &mut [f64],
) -> Result<()> {
    let controls = scene.observation_model.resolved_channel_controls(channel);
    let original_signal = signal.to_vec();
    calibration::apply_signal(calibration_config, &original_signal, signal)?;
    calibration::apply_simple_offsets(controls.simple_offsets, signal)?;
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
    let stray_reference = if controls.stray_light_nodes.use_reference_spectrum {
        correction_reference_signal(scene, channel, signal.len())
            .map(<[f64]>::to_vec)
            .unwrap_or_else(|| signal.to_vec())
    } else {
        signal.to_vec()
    };
    calibration::apply_stray_light_nodes(
        &controls.stray_light_nodes,
        wavelengths_nm,
        &stray_reference,
        signal,
        scratch,
    )?;
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
    calibration_config: calibration::Calibration,
    depolarization_factor: f64,
    wavelengths_nm: &[f64],
    jacobian: &mut [f64],
    scratch: &mut [f64],
) -> Result<()> {
    let controls = scene.observation_model.resolved_channel_controls(channel);
    let original_jacobian = jacobian.to_vec();
    calibration::apply_signal_derivative(calibration_config, &original_jacobian, jacobian)?;
    calibration::apply_simple_offset_derivatives(controls.simple_offsets, jacobian)?;
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

    if !controls.stray_light_nodes.use_reference_spectrum
        || correction_reference_signal(scene, channel, jacobian.len()).is_none()
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

pub fn correction_reference_signal(
    scene: &Scene,
    channel: SpectralChannel,
    sample_count: usize,
) -> Option<&[f64]> {
    let explicit_signal = match channel {
        SpectralChannel::Radiance => {
            &scene
                .observation_model
                .measurement_pipeline
                .radiance
                .noise
                .reference_signal
        }
        SpectralChannel::Irradiance => {
            &scene
                .observation_model
                .measurement_pipeline
                .irradiance
                .noise
                .reference_signal
        }
    };
    if explicit_signal.len() == sample_count {
        return Some(explicit_signal);
    }
    if channel == SpectralChannel::Radiance
        && scene.observation_model.reference_radiance.len() == sample_count
    {
        return Some(&scene.observation_model.reference_radiance);
    }
    None
}
