use crate::{
    forward_model::{
        implementations::instrument::{self, integration_for_wavelength_checked},
        instrument_grid::grid_calculation::spectral_eval::IntegrationKernel,
        optical_properties::state_build::PreparedOpticalState,
    },
    input::{
        instrument::{IntegrationMode, SpectralChannel},
        scene::Scene,
    },
};

pub const CHANNEL_MASK_RADIANCE: u32 = 1 << 0;
pub const CHANNEL_MASK_IRRADIANCE: u32 = 1 << 1;

#[derive(Debug, Clone, PartialEq)]
pub struct InstrumentResponseRow {
    pub nominal_index: i32,
    pub nominal_wavelength_nm: f64,
    pub channel: u32,
    pub sample_index: u32,
    pub support_count: u32,
    pub offset_nm: f64,
    pub support_wavelength_nm: f64,
    pub weight: f64,
    pub support_width_nm: f64,
    pub instrument_fwhm_nm: f64,
    pub high_resolution_step_nm: f64,
    pub high_resolution_half_span_nm: f64,
    pub integration_mode: u32,
    pub response_enabled: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    EmptyWavelengths,
    EmptyChannels,
    EmptyInstrumentResponse,
    InstrumentIntegration(instrument::Error),
}

impl From<instrument::Error> for Error {
    fn from(value: instrument::Error) -> Self {
        Self::InstrumentIntegration(value)
    }
}

pub fn build(
    scene: &Scene,
    prepared: &PreparedOpticalState,
    nominal_wavelengths_nm: &[f64],
    channel_mask: u32,
) -> Result<Vec<InstrumentResponseRow>, Error> {
    if nominal_wavelengths_nm.is_empty() {
        return Err(Error::EmptyWavelengths);
    }
    if channel_mask & (CHANNEL_MASK_RADIANCE | CHANNEL_MASK_IRRADIANCE) == 0 {
        return Err(Error::EmptyChannels);
    }

    let mut rows = Vec::new();
    for &nominal_wavelength_nm in nominal_wavelengths_nm {
        for channel in [SpectralChannel::Radiance, SpectralChannel::Irradiance] {
            if channel_mask & channel_mask_for(channel) == 0 {
                continue;
            }
            append_response_rows(&mut rows, scene, prepared, channel, nominal_wavelength_nm)?;
        }
    }
    Ok(rows)
}

fn append_response_rows(
    rows: &mut Vec<InstrumentResponseRow>,
    scene: &Scene,
    _prepared: &PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
) -> Result<(), Error> {
    // The Zig API receives prepared optics here. The current Rust resolver only
    // needs scene controls, but keeping the argument preserves the diagnostic
    // boundary for table builders that do need prepared state.
    let response_sampling =
        integration_for_wavelength_checked(scene, channel, nominal_wavelength_nm)?;
    let response = scene
        .observation_model
        .resolved_channel_controls(channel)
        .response;
    if response_sampling.enabled && response_sampling.sample_count == 0 {
        return Err(Error::EmptyInstrumentResponse);
    }

    let support_count = response_sampling.sample_count.max(1);
    let support_width_nm = support_width_nm(&response_sampling);
    for sample_index in 0..support_count {
        let offset_nm = if response_sampling.sample_count == 0 {
            0.0
        } else {
            response_sampling.offsets_nm[sample_index]
        };
        let weight = if !response_sampling.enabled && support_count == 1 {
            1.0
        } else {
            response_sampling.weights[sample_index]
        };
        rows.push(InstrumentResponseRow {
            nominal_index: nearest_nominal_index(scene, nominal_wavelength_nm),
            nominal_wavelength_nm,
            channel: channel_code(channel),
            sample_index: sample_index as u32,
            support_count: support_count as u32,
            offset_nm,
            support_wavelength_nm: nominal_wavelength_nm + offset_nm,
            weight,
            support_width_nm,
            instrument_fwhm_nm: response.fwhm_nm,
            high_resolution_step_nm: response.high_resolution_step_nm,
            high_resolution_half_span_nm: response.high_resolution_half_span_nm,
            integration_mode: integration_mode_code(response.integration_mode),
            response_enabled: u8::from(response_sampling.enabled),
        });
    }
    Ok(())
}

fn support_width_nm(response_sampling: &IntegrationKernel) -> f64 {
    if response_sampling.sample_count <= 1 {
        return 0.0;
    }
    response_sampling.offsets_nm[response_sampling.sample_count - 1]
        - response_sampling.offsets_nm[0]
}

fn channel_mask_for(channel: SpectralChannel) -> u32 {
    match channel {
        SpectralChannel::Radiance => CHANNEL_MASK_RADIANCE,
        SpectralChannel::Irradiance => CHANNEL_MASK_IRRADIANCE,
    }
}

fn channel_code(channel: SpectralChannel) -> u32 {
    match channel {
        SpectralChannel::Radiance => 0,
        SpectralChannel::Irradiance => 1,
    }
}

fn integration_mode_code(mode: IntegrationMode) -> u32 {
    match mode {
        IntegrationMode::Auto => 0,
        IntegrationMode::ExplicitHrGrid => 1,
        IntegrationMode::DisamarHrGrid => 2,
        IntegrationMode::Adaptive => 3,
    }
}

fn nearest_nominal_index(scene: &Scene, nominal_wavelength_nm: f64) -> i32 {
    let sample_count = scene.spectral_grid.sample_count;
    if sample_count <= 1 {
        return 0;
    }
    let step_nm =
        (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) / f64::from(sample_count - 1);
    if step_nm <= 0.0 {
        return 0;
    }
    ((nominal_wavelength_nm - scene.spectral_grid.start_nm) / step_nm)
        .round()
        .clamp(0.0, f64::from(sample_count - 1)) as i32
}
