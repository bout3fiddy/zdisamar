use std::collections::HashSet;

use crate::{
    forward_model::{
        implementations::instrument,
        instrument_grid::{
            grid_calculation::{
                cache::SpectralEvaluationCache,
                types::Implementations,
                wavelength_plan::{ForwardCacheMiss, WavelengthSampling},
            },
            spectral_math::{calibration, grid},
        },
    },
    input::{Scene, SpectralChannel},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    InvalidAxis,
    KernelRealizationFailed,
}

pub type Result<T> = std::result::Result<T, Error>;

impl From<grid::Error> for Error {
    fn from(_: grid::Error) -> Self {
        Self::InvalidAxis
    }
}

impl From<instrument::implementation::Error> for Error {
    fn from(_: instrument::implementation::Error) -> Self {
        Self::KernelRealizationFailed
    }
}

pub fn build_wavelength_sampling(
    scene: &Scene,
    resolved_axis: grid::ResolvedAxis<'_>,
    radiance_calibration: calibration::Calibration,
    irradiance_calibration: calibration::Calibration,
    _implementations: Implementations,
) -> Result<Vec<WavelengthSampling>> {
    resolved_axis.validate()?;
    let sample_count = scene.spectral_grid.sample_count as usize;
    let mut plans = Vec::with_capacity(sample_count);
    for index in 0..sample_count {
        plans.push(build_wavelength_sampling_plan(
            scene,
            resolved_axis,
            radiance_calibration,
            irradiance_calibration,
            index,
        )?);
    }
    Ok(plans)
}

pub fn build_wavelength_sampling_plan(
    scene: &Scene,
    resolved_axis: grid::ResolvedAxis<'_>,
    radiance_calibration: calibration::Calibration,
    irradiance_calibration: calibration::Calibration,
    index: usize,
) -> Result<WavelengthSampling> {
    let nominal_wavelength_nm = resolved_sample_at_assume_valid(resolved_axis, index);
    let mut radiance_integration = instrument::IntegrationKernel::default();
    instrument::implementation::integration_for_wavelength_checked(
        scene,
        SpectralChannel::Radiance,
        nominal_wavelength_nm,
        &mut radiance_integration,
    )?;
    let mut irradiance_integration = instrument::IntegrationKernel::default();
    instrument::implementation::integration_for_wavelength_checked(
        scene,
        SpectralChannel::Irradiance,
        nominal_wavelength_nm,
        &mut irradiance_integration,
    )?;

    Ok(WavelengthSampling {
        nominal_wavelength_nm,
        radiance_wavelength_nm: calibration::shifted_wavelength(
            radiance_calibration,
            nominal_wavelength_nm,
        ),
        irradiance_wavelength_nm: calibration::shifted_wavelength(
            irradiance_calibration,
            nominal_wavelength_nm,
        ),
        radiance_integration,
        irradiance_integration,
    })
}

pub fn resolved_sample_at_assume_valid(resolved_axis: grid::ResolvedAxis<'_>, index: usize) -> f64 {
    if !resolved_axis.explicit_wavelengths_nm.is_empty() {
        return resolved_axis.explicit_wavelengths_nm[index];
    }
    let sample_count = resolved_axis.base.sample_count;
    let step =
        (resolved_axis.base.end_nm - resolved_axis.base.start_nm) / f64::from(sample_count - 1);
    resolved_axis.base.start_nm + step * index as f64
}

pub fn collect_unique_forward_misses(plans: &[WavelengthSampling]) -> Vec<ForwardCacheMiss> {
    let mut seen = HashSet::new();
    let mut misses = Vec::new();
    for plan in plans {
        let integration_sample_count = if plan.radiance_integration.enabled {
            plan.radiance_integration.sample_count
        } else {
            1
        };
        for sample_index in 0..integration_sample_count {
            let wavelength_nm = if plan.radiance_integration.enabled {
                plan.radiance_wavelength_nm + plan.radiance_integration.offsets_nm[sample_index]
            } else {
                plan.radiance_wavelength_nm
            };
            let key = SpectralEvaluationCache::key_for(wavelength_nm);
            if seen.insert(key) {
                misses.push(ForwardCacheMiss { key, wavelength_nm });
            }
        }
    }
    misses
}
