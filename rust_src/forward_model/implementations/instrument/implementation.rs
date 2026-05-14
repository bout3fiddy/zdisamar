use crate::{
    forward_model::instrument_grid::spectral_math::calibration::Calibration,
    input::{IntegrationMode, SamplingMode, Scene, SpectralChannel},
};

use super::{
    calibration, response,
    types::{DEFAULT_INTEGRATION_SAMPLE_COUNT, IntegrationKernel, MAX_INTEGRATION_SAMPLE_COUNT},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    DisamarKernelRealizationFailed,
}

pub type Result<T> = std::result::Result<T, Error>;
pub type CalibrationForSceneFn = fn(&Scene, SpectralChannel) -> Calibration;
pub type UsesIntegratedSamplingFn = fn(&Scene, SpectralChannel) -> bool;
pub type IntegrationForWavelengthFn = fn(&Scene, SpectralChannel, f64, &mut IntegrationKernel);
pub type SlitKernelForSceneFn = fn(&Scene, SpectralChannel) -> [f64; 5];

#[derive(Debug, Clone, Copy)]
pub struct Implementation {
    pub id: &'static str,
    pub calibration_for_scene: CalibrationForSceneFn,
    pub uses_integrated_sampling: UsesIntegratedSamplingFn,
    pub integration_for_wavelength: IntegrationForWavelengthFn,
    pub slit_kernel_for_scene: SlitKernelForSceneFn,
}

pub fn resolve(provider_id: &str) -> Option<Implementation> {
    match provider_id {
        "builtin.generic_response" => Some(Implementation {
            id: "builtin.generic_response",
            calibration_for_scene: calibration::calibration_for_scene,
            uses_integrated_sampling: uses_integrated_instrument_sampling,
            integration_for_wavelength,
            slit_kernel_for_scene,
        }),
        _ => None,
    }
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

pub fn integration_for_wavelength(
    scene: &Scene,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    kernel: &mut IntegrationKernel,
) {
    if integration_for_wavelength_checked(scene, channel, nominal_wavelength_nm, kernel).is_err() {
        response::reset_kernel(kernel);
        kernel.sample_count = 1;
    }
}

pub fn integration_for_wavelength_checked(
    scene: &Scene,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    kernel: &mut IntegrationKernel,
) -> Result<()> {
    response::reset_kernel(kernel);
    let spectral_response = scene
        .observation_model
        .resolved_channel_controls(channel)
        .response;
    if !uses_integrated_instrument_sampling(scene, channel) {
        kernel.sample_count = 1;
        return Ok(());
    }

    if spectral_response.instrument_line_shape_table.nominal_count > 0 {
        kernel.sample_count = spectral_response
            .instrument_line_shape_table
            .write_normalized_kernel_for_nominal(
                nominal_wavelength_nm,
                kernel.offsets_nm.as_mut_slice(),
                kernel.weights.as_mut_slice(),
            );
        if kernel.sample_count == 0 {
            set_unit_integrated_kernel(kernel);
        } else {
            kernel.enabled = true;
        }
        return Ok(());
    }

    if spectral_response.instrument_line_shape.sample_count > 0 {
        kernel.sample_count = spectral_response
            .instrument_line_shape
            .write_normalized_kernel(
                kernel.offsets_nm.as_mut_slice(),
                kernel.weights.as_mut_slice(),
            );
        if kernel.sample_count == 0 {
            set_unit_integrated_kernel(kernel);
        } else {
            kernel.enabled = true;
        }
        return Ok(());
    }

    if spectral_response.integration_mode == IntegrationMode::DisamarHrGrid {
        // Prepared optical-state kernels are not ported yet; the checked path
        // fails so the public wrapper uses Zig's single-sample fallback.
        return Err(Error::DisamarKernelRealizationFailed);
    }

    let prefer_explicit_hr_grid = matches!(
        spectral_response.integration_mode,
        IntegrationMode::Auto | IntegrationMode::ExplicitHrGrid
    );
    if prefer_explicit_hr_grid
        && spectral_response.high_resolution_step_nm > 0.0
        && spectral_response.high_resolution_half_span_nm > 0.0
    {
        build_explicit_high_resolution_kernel(&spectral_response, kernel);
        return Ok(());
    }

    if matches!(
        scene.observation_model.sampling,
        SamplingMode::Operational | SamplingMode::MeasuredChannels
    ) {
        kernel.sample_count = 1;
        return Ok(());
    }

    build_default_five_point_kernel(&spectral_response, kernel);
    Ok(())
}

pub fn slit_kernel_for_scene(scene: &Scene, channel: SpectralChannel) -> [f64; 5] {
    let spectral_response = scene
        .observation_model
        .resolved_channel_controls(channel)
        .response;
    if spectral_response.fwhm_nm <= 0.0 {
        return [1.0, 4.0, 6.0, 4.0, 1.0];
    }

    let sample_spacing_nm = if scene.spectral_grid.sample_count <= 1 {
        1.0
    } else {
        (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm)
            / f64::from(scene.spectral_grid.sample_count - 1)
    };
    let mut kernel = [0.0; 5];
    let mut sum = 0.0;
    for (index, value) in kernel.iter_mut().enumerate() {
        let offset_samples = index as f64 - 2.0;
        let offset_nm = offset_samples * sample_spacing_nm;
        *value = response::spectral_response_weight(&spectral_response, offset_nm);
        sum += *value;
    }
    if sum > 0.0 && sum.is_finite() {
        for value in &mut kernel {
            *value /= sum;
        }
    }
    kernel
}

fn build_explicit_high_resolution_kernel(
    spectral_response: &crate::input::SpectralResponse,
    kernel: &mut IntegrationKernel,
) {
    let step_nm = spectral_response.high_resolution_step_nm;
    let half_span_nm = spectral_response.high_resolution_half_span_nm;
    let mut sample_count = 0;
    let mut offset_nm = -half_span_nm;
    while offset_nm <= half_span_nm + (step_nm * 0.5) && sample_count < MAX_INTEGRATION_SAMPLE_COUNT
    {
        kernel.offsets_nm[sample_count] = offset_nm;
        kernel.weights[sample_count] =
            response::spectral_response_weight(spectral_response, offset_nm);
        sample_count += 1;
        offset_nm += step_nm;
    }
    if sample_count == 0 {
        sample_count = 1;
    }

    let total_weight: f64 = kernel.weights[..sample_count].iter().sum();
    if total_weight <= 0.0 || !total_weight.is_finite() {
        response::reset_kernel(kernel);
        kernel.offsets_nm[0] = 0.0;
        kernel.weights[0] = 1.0;
        sample_count = 1;
    } else {
        for weight in &mut kernel.weights[..sample_count] {
            *weight /= total_weight;
        }
    }
    kernel.enabled = true;
    kernel.sample_count = sample_count;
}

fn build_default_five_point_kernel(
    spectral_response: &crate::input::SpectralResponse,
    kernel: &mut IntegrationKernel,
) {
    let default_half_span_nm = response::default_kernel_half_span_nm(spectral_response.fwhm_nm);
    let offsets_nm: [f64; DEFAULT_INTEGRATION_SAMPLE_COUNT] = [
        -default_half_span_nm,
        -0.5 * default_half_span_nm,
        0.0,
        0.5 * default_half_span_nm,
        default_half_span_nm,
    ];

    let mut total_weight = 0.0;
    for (index, offset_nm) in offsets_nm.into_iter().enumerate() {
        kernel.offsets_nm[index] = offset_nm;
        kernel.weights[index] = response::spectral_response_weight(spectral_response, offset_nm);
        total_weight += kernel.weights[index];
    }
    for weight in &mut kernel.weights[..DEFAULT_INTEGRATION_SAMPLE_COUNT] {
        *weight /= total_weight;
    }
    kernel.enabled = true;
    kernel.sample_count = DEFAULT_INTEGRATION_SAMPLE_COUNT;
}

fn set_unit_integrated_kernel(kernel: &mut IntegrationKernel) {
    response::reset_kernel(kernel);
    kernel.enabled = true;
    kernel.sample_count = 1;
    kernel.weights[0] = 1.0;
}
