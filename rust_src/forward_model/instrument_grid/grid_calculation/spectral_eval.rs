use std::thread;

use crate::{
    forward_model::{
        implementations::instrument::IntegrationKernel,
        instrument_grid::grid_calculation::{
            cache::SpectralEvaluationCache, spectral_forward::MIN_PARALLEL_FORWARD_MISS_COUNT,
        },
    },
    input::{IntegrationMode, Scene, SpectralChannel, solar_irradiance_at_wavelength},
};

pub use crate::forward_model::instrument_grid::grid_calculation::wavelength_plan::ForwardCacheMiss;

pub fn preferred_forward_worker_count(miss_count: usize) -> usize {
    if miss_count < MIN_PARALLEL_FORWARD_MISS_COUNT {
        return 1;
    }
    let cpu_count = thread::available_parallelism().map_or(1, usize::from);
    cpu_count.min((miss_count / MIN_PARALLEL_FORWARD_MISS_COUNT).max(1))
}

pub fn integrate_irradiance_at_nominal(
    scene: &Scene,
    nominal_wavelength_nm: f64,
    cache: &mut SpectralEvaluationCache,
    integration: &IntegrationKernel,
) -> f64 {
    if !integration.enabled {
        return cached_irradiance_at_wavelength(scene, nominal_wavelength_nm, cache);
    }

    let mut irradiance_sum = 0.0;
    for index in 0..integration.sample_count {
        let offset_nm = integration.offsets_nm[index];
        let weight = integration.weights[index];
        irradiance_sum += weight
            * cached_irradiance_at_wavelength(scene, nominal_wavelength_nm + offset_nm, cache);
    }
    irradiance_sum
}

pub fn cached_irradiance_at_wavelength(
    scene: &Scene,
    wavelength_nm: f64,
    cache: &mut SpectralEvaluationCache,
) -> f64 {
    let key = SpectralEvaluationCache::key_for(wavelength_nm);
    if let Some(cached) = cache.irradiance.get(&key) {
        return *cached;
    }

    let response = scene
        .observation_model
        .resolved_channel_controls(SpectralChannel::Irradiance)
        .response;
    let operational_band_support = scene.observation_model.primary_operational_band_support();
    let value = if response.integration_mode == IntegrationMode::DisamarHrGrid
        && operational_band_support
            .operational_solar_spectrum
            .enabled()
    {
        operational_band_support
            .operational_solar_spectrum
            .interpolate_irradiance_within_bounds(wavelength_nm)
            .unwrap_or_else(|| solar_irradiance_at_wavelength(scene, wavelength_nm))
    } else {
        solar_irradiance_at_wavelength(scene, wavelength_nm)
    };
    cache.irradiance.insert(key, value);
    value
}
