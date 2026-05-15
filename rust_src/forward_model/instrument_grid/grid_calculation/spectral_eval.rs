use super::{
    cache::SpectralEvaluationCache,
    forward_input::ForwardInputBuffers,
    spectral_forward::{self, ForwardIntegratedSample, compute_forward_sample_at_wavelength},
};
use crate::{
    forward_model::{
        jacobian, optical_properties::state_build::PreparedOpticalState,
        radiative_transfer::common_types::Route,
    },
    input::{
        instrument::constants::MAX_LINE_SHAPE_SAMPLES, reference::solar_irradiance, scene::Scene,
    },
};

pub const DEFAULT_INTEGRATION_SAMPLE_COUNT: usize = 5;
pub const MAX_INTEGRATION_SAMPLE_COUNT: usize = MAX_LINE_SHAPE_SAMPLES;

#[derive(Debug, Default, Clone, PartialEq)]
pub struct IntegrationKernel {
    pub enabled: bool,
    pub sample_count: usize,
    pub offsets_nm: Vec<f64>,
    pub weights: Vec<f64>,
}

impl IntegrationKernel {
    pub fn disabled() -> Self {
        Self::default()
    }

    pub fn from_samples(offsets_nm: Vec<f64>, weights: Vec<f64>) -> Self {
        Self {
            enabled: true,
            sample_count: offsets_nm.len().min(weights.len()),
            offsets_nm,
            weights,
        }
    }

    fn validate(&self) -> Result<(), Error> {
        if !self.enabled {
            return Ok(());
        }
        if self.sample_count == 0
            || self.sample_count > MAX_INTEGRATION_SAMPLE_COUNT
            || self.offsets_nm.len() < self.sample_count
            || self.weights.len() < self.sample_count
        {
            return Err(Error::InvalidIntegrationKernel);
        }
        if self.offsets_nm[..self.sample_count]
            .iter()
            .any(|value| !value.is_finite())
            || self.weights[..self.sample_count]
                .iter()
                .any(|value| !value.is_finite())
        {
            return Err(Error::InvalidIntegrationKernel);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    InvalidIntegrationKernel,
    ForwardSample(spectral_forward::Error),
}

impl From<spectral_forward::Error> for Error {
    fn from(value: spectral_forward::Error) -> Self {
        Self::ForwardSample(value)
    }
}

pub fn cached_forward_at_wavelength(
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    buffers: &mut ForwardInputBuffers<'_>,
    cache: &mut SpectralEvaluationCache,
) -> Result<ForwardIntegratedSample, Error> {
    if let Some(cached) = cache.forward_at(wavelength_nm) {
        return Ok(cached);
    }

    let sample = compute_forward_sample_at_wavelength(
        scene,
        route,
        prepared,
        wavelength_nm,
        buffers.reborrow(),
    )?;
    cache.put_forward(wavelength_nm, sample);
    Ok(sample)
}

pub fn integrate_forward_at_nominal(
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
    nominal_wavelength_nm: f64,
    buffers: &mut ForwardInputBuffers<'_>,
    cache: &mut SpectralEvaluationCache,
    integration: &IntegrationKernel,
) -> Result<ForwardIntegratedSample, Error> {
    integration.validate()?;
    if !integration.enabled {
        return cached_forward_at_wavelength(
            scene,
            route,
            prepared,
            nominal_wavelength_nm,
            buffers,
            cache,
        );
    }

    let mut radiance_sum = 0.0;
    let mut jacobian_sum = jacobian::zero();
    for index in 0..integration.sample_count {
        let wavelength_nm = nominal_wavelength_nm + integration.offsets_nm[index];
        let sample =
            cached_forward_at_wavelength(scene, route, prepared, wavelength_nm, buffers, cache)?;
        let weight = integration.weights[index];
        radiance_sum += weight * sample.radiance;
        jacobian::add_scaled(&mut jacobian_sum, sample.jacobian, weight);
    }

    Ok(ForwardIntegratedSample {
        radiance: radiance_sum,
        jacobian: jacobian_sum,
    })
}

pub fn cached_irradiance_at_wavelength(
    scene: &Scene,
    wavelength_nm: f64,
    cache: &mut SpectralEvaluationCache,
) -> f64 {
    if let Some(cached) = cache.irradiance_at(wavelength_nm) {
        return cached;
    }

    let irradiance = solar_irradiance::irradiance_at_wavelength(scene, wavelength_nm);
    cache.put_irradiance(wavelength_nm, irradiance);
    irradiance
}

pub fn integrate_irradiance_at_nominal(
    scene: &Scene,
    nominal_wavelength_nm: f64,
    cache: &mut SpectralEvaluationCache,
    integration: &IntegrationKernel,
) -> Result<f64, Error> {
    integration.validate()?;
    if !integration.enabled {
        return Ok(cached_irradiance_at_wavelength(
            scene,
            nominal_wavelength_nm,
            cache,
        ));
    }

    let mut irradiance_sum = 0.0;
    for index in 0..integration.sample_count {
        let wavelength_nm = nominal_wavelength_nm + integration.offsets_nm[index];
        irradiance_sum += integration.weights[index]
            * cached_irradiance_at_wavelength(scene, wavelength_nm, cache);
    }
    Ok(irradiance_sum)
}
