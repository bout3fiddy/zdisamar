use super::{
    adaptive_plan,
    response::{default_kernel_half_span_nm, spectral_response_weight},
};
use crate::{
    forward_model::instrument_grid::grid_calculation::spectral_eval::{
        DEFAULT_INTEGRATION_SAMPLE_COUNT, IntegrationKernel, MAX_INTEGRATION_SAMPLE_COUNT,
    },
    forward_model::optical_properties::PreparedOpticalState,
    input::{
        instrument::{IntegrationMode, SamplingMode, SpectralChannel},
        scene::Scene,
    },
};

pub const DEFAULT_SLIT_KERNEL: [f64; DEFAULT_INTEGRATION_SAMPLE_COUNT] = [1.0, 4.0, 6.0, 4.0, 1.0];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    DisamarKernelRealizationFailed,
}

pub fn uses_integrated_instrument_sampling(scene: &Scene, channel: SpectralChannel) -> bool {
    let response = scene
        .observation_model
        .resolved_channel_controls(channel)
        .response;
    let mode_requires_native_integration = matches!(
        scene.observation_model.sampling,
        SamplingMode::Operational | SamplingMode::MeasuredChannels
    );
    mode_requires_native_integration
        || response.fwhm_nm > 0.0
        || response.instrument_line_shape.sample_count > 0
        || response.instrument_line_shape_table.nominal_count > 0
}

pub fn integration_for_wavelength_checked(
    scene: &Scene,
    prepared: Option<&PreparedOpticalState>,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
) -> Result<IntegrationKernel, Error> {
    let response = scene
        .observation_model
        .resolved_channel_controls(channel)
        .response;
    if !uses_integrated_instrument_sampling(scene, channel) {
        return Ok(IntegrationKernel::disabled());
    }

    if response.instrument_line_shape_table.nominal_count > 0 {
        let mut offsets = vec![0.0; MAX_INTEGRATION_SAMPLE_COUNT];
        let mut weights = vec![0.0; MAX_INTEGRATION_SAMPLE_COUNT];
        let sample_count = response
            .instrument_line_shape_table
            .write_normalized_kernel_for_nominal(nominal_wavelength_nm, &mut offsets, &mut weights);
        return Ok(kernel_from_written_samples(offsets, weights, sample_count));
    }

    if response.instrument_line_shape.sample_count > 0 {
        let mut offsets = vec![0.0; MAX_INTEGRATION_SAMPLE_COUNT];
        let mut weights = vec![0.0; MAX_INTEGRATION_SAMPLE_COUNT];
        let sample_count = response
            .instrument_line_shape
            .write_normalized_kernel(&mut offsets, &mut weights);
        return Ok(kernel_from_written_samples(offsets, weights, sample_count));
    }

    if response.integration_mode == IntegrationMode::DisamarHrGrid {
        if let Some(prepared) = prepared {
            if let Some(kernel) = adaptive_plan::build_adaptive_integration_kernel(
                scene,
                prepared,
                &response,
                nominal_wavelength_nm,
                channel == SpectralChannel::Irradiance,
            ) {
                return Ok(kernel);
            }
        } else if let Some(kernel) = adaptive_plan::build_disamar_realized_kernel(
            scene,
            &response,
            nominal_wavelength_nm,
            channel == SpectralChannel::Irradiance,
        ) {
            return Ok(kernel);
        }
        return Err(Error::DisamarKernelRealizationFailed);
    }

    let prefer_explicit_hr_grid = matches!(
        response.integration_mode,
        IntegrationMode::Auto | IntegrationMode::ExplicitHrGrid
    );
    if prefer_explicit_hr_grid
        && response.high_resolution_step_nm > 0.0
        && response.high_resolution_half_span_nm > 0.0
    {
        return Ok(explicit_high_resolution_kernel(&response));
    }

    if let Some(prepared) = prepared
        && (response.integration_mode == IntegrationMode::Adaptive
            || response.high_resolution_step_nm == 0.0
            || response.high_resolution_half_span_nm == 0.0)
        && let Some(kernel) = adaptive_plan::build_adaptive_integration_kernel(
            scene,
            prepared,
            &response,
            nominal_wavelength_nm,
            channel == SpectralChannel::Irradiance,
        )
    {
        return Ok(kernel);
    }

    if matches!(
        scene.observation_model.sampling,
        SamplingMode::Operational | SamplingMode::MeasuredChannels
    ) {
        return Ok(IntegrationKernel::disabled());
    }

    Ok(default_slit_kernel(&response))
}

pub fn slit_kernel_for_scene(scene: &Scene, channel: SpectralChannel) -> [f64; 5] {
    let response = scene
        .observation_model
        .resolved_channel_controls(channel)
        .response;
    if response.fwhm_nm <= 0.0 {
        return DEFAULT_SLIT_KERNEL;
    }

    let sample_spacing_nm = if scene.spectral_grid.sample_count <= 1 {
        1.0
    } else {
        (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm)
            / f64::from(scene.spectral_grid.sample_count - 1)
    };
    let mut kernel = [0.0; DEFAULT_INTEGRATION_SAMPLE_COUNT];
    let mut sum = 0.0;
    for (index, value) in kernel.iter_mut().enumerate() {
        let offset_samples = index as f64 - 2.0;
        let offset_nm = offset_samples * sample_spacing_nm;
        *value = spectral_response_weight(&response, offset_nm);
        sum += *value;
    }
    for value in &mut kernel {
        *value /= sum;
    }
    kernel
}

fn kernel_from_written_samples(
    mut offsets: Vec<f64>,
    mut weights: Vec<f64>,
    sample_count: usize,
) -> IntegrationKernel {
    if sample_count == 0 {
        return IntegrationKernel::from_samples(vec![0.0], vec![1.0]);
    }
    offsets.truncate(sample_count);
    weights.truncate(sample_count);
    IntegrationKernel::from_samples(offsets, weights)
}

fn explicit_high_resolution_kernel(
    response: &crate::input::instrument::SpectralResponse,
) -> IntegrationKernel {
    let step_nm = response.high_resolution_step_nm;
    let half_span_nm = response.high_resolution_half_span_nm;
    let mut offsets = Vec::new();
    let mut weights = Vec::new();
    let mut offset_nm = -half_span_nm;
    while offset_nm <= half_span_nm + step_nm * 0.5 && offsets.len() < MAX_INTEGRATION_SAMPLE_COUNT
    {
        offsets.push(offset_nm);
        weights.push(spectral_response_weight(response, offset_nm));
        offset_nm += step_nm;
    }
    normalize_or_unit_kernel(offsets, weights)
}

fn default_slit_kernel(response: &crate::input::instrument::SpectralResponse) -> IntegrationKernel {
    let half_span_nm = default_kernel_half_span_nm(response.fwhm_nm);
    let offsets = vec![
        -half_span_nm,
        -0.5 * half_span_nm,
        0.0,
        0.5 * half_span_nm,
        half_span_nm,
    ];
    debug_assert_eq!(offsets.len(), DEFAULT_INTEGRATION_SAMPLE_COUNT);
    let weights = offsets
        .iter()
        .map(|&offset_nm| spectral_response_weight(response, offset_nm))
        .collect::<Vec<_>>();
    normalize_or_unit_kernel(offsets, weights)
}

fn normalize_or_unit_kernel(offsets: Vec<f64>, mut weights: Vec<f64>) -> IntegrationKernel {
    let total = weights.iter().sum::<f64>();
    if total <= 0.0 || !total.is_finite() {
        return IntegrationKernel::from_samples(vec![0.0], vec![1.0]);
    }
    for weight in &mut weights {
        *weight /= total;
    }
    IntegrationKernel::from_samples(offsets, weights)
}
