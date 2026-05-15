use crate::{
    forward_model::instrument_grid::spectral_math::noise,
    input::{
        instrument::{NoiseModelKind, SpectralChannel},
        scene::Scene,
    },
};

pub type Error = noise::Error;

pub const SCENE_NOISE_ID: &str = "builtin.scene_noise";
pub const NONE_NOISE_ID: &str = "builtin.none_noise";
pub const SHOT_NOISE_ID: &str = "builtin.shot_noise";
pub const S5P_OPERATIONAL_NOISE_ID: &str = "builtin.s5p_operational_noise";

pub type MaterializeSigmaFn =
    fn(&Scene, SpectralChannel, &[f64], &[f64], &mut [f64]) -> Result<(), Error>;

#[derive(Debug, Clone, Copy)]
pub struct Implementation {
    pub id: &'static str,
    pub materializes_sigma: fn(&Scene, SpectralChannel) -> bool,
    pub materialize_sigma: MaterializeSigmaFn,
}

pub fn resolve(provider_id: &str) -> Option<Implementation> {
    match provider_id {
        SCENE_NOISE_ID => Some(Implementation {
            id: SCENE_NOISE_ID,
            materializes_sigma: scene_noise_enabled,
            materialize_sigma: scene_noise_sigma,
        }),
        NONE_NOISE_ID => Some(Implementation {
            id: NONE_NOISE_ID,
            materializes_sigma: never_enabled,
            materialize_sigma: zero_sigma,
        }),
        SHOT_NOISE_ID => Some(Implementation {
            id: SHOT_NOISE_ID,
            materializes_sigma: always_enabled,
            materialize_sigma: shot_noise_sigma,
        }),
        S5P_OPERATIONAL_NOISE_ID => Some(Implementation {
            id: S5P_OPERATIONAL_NOISE_ID,
            materializes_sigma: always_enabled,
            materialize_sigma: s5p_operational_sigma,
        }),
        _ => None,
    }
}

fn never_enabled(_: &Scene, _: SpectralChannel) -> bool {
    false
}

fn always_enabled(_: &Scene, _: SpectralChannel) -> bool {
    true
}

fn scene_noise_enabled(scene: &Scene, channel: SpectralChannel) -> bool {
    scene
        .observation_model
        .resolved_channel_controls(channel)
        .noise
        .enabled
}

fn scene_noise_sigma(
    scene: &Scene,
    channel: SpectralChannel,
    wavelengths_nm: &[f64],
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    let controls = scene
        .observation_model
        .resolved_channel_controls(channel)
        .noise;
    if !controls.snr_values.is_empty() {
        return noise::sigma_from_interpolated_signal_to_noise(
            wavelengths_nm,
            &controls.snr_wavelengths_nm,
            &controls.snr_values,
            signal,
            output,
        );
    }

    match controls.model {
        NoiseModelKind::ShotNoise => {
            shot_noise_sigma(scene, channel, wavelengths_nm, signal, output)
        }
        NoiseModelKind::S5pOperational => {
            s5p_operational_sigma(scene, channel, wavelengths_nm, signal, output)
        }
        NoiseModelKind::LabOperational => {
            lab_operational_sigma(scene, channel, wavelengths_nm, signal, output)
        }
        NoiseModelKind::SnrFromInput => ingested_sigma(scene, channel, signal, output),
        NoiseModelKind::None => zero_sigma(scene, channel, wavelengths_nm, signal, output),
    }
}

fn zero_sigma(
    _: &Scene,
    _: SpectralChannel,
    _: &[f64],
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    if signal.len() != output.len() {
        return Err(Error::ShapeMismatch);
    }
    output.fill(0.0);
    Ok(())
}

fn shot_noise_sigma(
    scene: &Scene,
    channel: SpectralChannel,
    _: &[f64],
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    let controls = scene
        .observation_model
        .resolved_channel_controls(channel)
        .noise;
    noise::shot_noise_std(signal, controls.electrons_per_count, output)
}

pub fn s5p_operational_sigma(
    scene: &Scene,
    channel: SpectralChannel,
    wavelengths_nm: &[f64],
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    let controls = scene
        .observation_model
        .resolved_channel_controls(channel)
        .noise;
    if !controls.reference_signal.is_empty() && !controls.reference_sigma.is_empty() {
        return noise::scale_sigma_from_reference(
            &controls.reference_signal,
            &controls.reference_sigma,
            signal,
            reference_bin_width_nm(scene, channel, controls.reference_signal.len()),
            current_bin_width_nm(scene, wavelengths_nm),
            output,
        );
    }
    noise::sigma_from_s5_operational(wavelengths_nm, signal, output)
}

pub fn lab_operational_sigma(
    scene: &Scene,
    channel: SpectralChannel,
    _: &[f64],
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    let controls = scene
        .observation_model
        .resolved_channel_controls(channel)
        .noise;
    noise::sigma_from_lab_operational(signal, controls.lab_a, controls.lab_b, output)
}

fn ingested_sigma(
    scene: &Scene,
    channel: SpectralChannel,
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    let controls = scene
        .observation_model
        .resolved_channel_controls(channel)
        .noise;
    let _ = signal;
    if !controls.reference_sigma.is_empty() {
        return noise::copy_input_sigma(&controls.reference_sigma, output);
    }
    noise::copy_input_sigma(&scene.observation_model.ingested_noise_sigma, output)
}

fn current_bin_width_nm(scene: &Scene, wavelengths_nm: &[f64]) -> f64 {
    if wavelengths_nm.len() > 1 {
        return average_spacing_nm(wavelengths_nm);
    }
    if scene.spectral_grid.sample_count > 1 {
        return (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm)
            / f64::from(scene.spectral_grid.sample_count - 1);
    }
    reference_bin_width_nm(scene, SpectralChannel::Radiance, 0)
}

fn reference_bin_width_nm(scene: &Scene, channel: SpectralChannel, sample_count: usize) -> f64 {
    let controls = scene
        .observation_model
        .resolved_channel_controls(channel)
        .noise;
    let operational_band_support = scene.observation_model.primary_operational_band_support();
    if controls.reference_bin_width_nm > 0.0 {
        return controls.reference_bin_width_nm;
    }
    if operational_band_support.operational_refspec_grid.enabled() {
        return operational_band_support
            .operational_refspec_grid
            .effective_spacing_nm();
    }
    if sample_count > 1
        && channel == SpectralChannel::Radiance
        && scene.observation_model.reference_radiance.len() == sample_count
        && scene.observation_model.measured_wavelengths_nm.len() == sample_count
    {
        return average_spacing_nm(&scene.observation_model.measured_wavelengths_nm);
    }
    if scene.observation_model.measured_wavelengths_nm.len() > 1 {
        return average_spacing_nm(&scene.observation_model.measured_wavelengths_nm);
    }
    if scene.spectral_grid.sample_count > 1 {
        return (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm)
            / f64::from(scene.spectral_grid.sample_count - 1);
    }
    1.0
}

fn average_spacing_nm(wavelengths_nm: &[f64]) -> f64 {
    if wavelengths_nm.len() < 2 {
        return 1.0;
    }

    let spacing_sum = wavelengths_nm
        .windows(2)
        .map(|pair| pair[1] - pair[0])
        .sum::<f64>();
    spacing_sum / (wavelengths_nm.len() - 1) as f64
}
