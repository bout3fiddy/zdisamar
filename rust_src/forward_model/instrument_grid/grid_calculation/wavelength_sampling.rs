use super::{
    cache::SpectralEvaluationCache,
    wavelength_plan::{ForwardCacheMiss, WavelengthSampling},
};
use crate::{
    forward_model::{
        implementations::instrument,
        instrument_grid::spectral_math::{
            calibration::shifted_wavelength,
            grid::{self, ResolvedAxis},
        },
        optical_properties::PreparedOpticalState,
    },
    input::{instrument::SpectralChannel, scene::Scene},
};
use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    Grid(grid::Error),
    Instrument(instrument::Error),
}

impl From<grid::Error> for Error {
    fn from(value: grid::Error) -> Self {
        Self::Grid(value)
    }
}

impl From<instrument::Error> for Error {
    fn from(value: instrument::Error) -> Self {
        Self::Instrument(value)
    }
}

pub fn build_wavelength_sampling(
    scene: &Scene,
    resolved_axis: &ResolvedAxis,
    prepared: &PreparedOpticalState,
    instrument: instrument::Implementation,
) -> Result<Vec<WavelengthSampling>, Error> {
    resolved_axis.validate()?;
    let sample_count = scene.spectral_grid.sample_count as usize;
    let radiance_calibration = (instrument.calibration_for_scene)(scene, SpectralChannel::Radiance);
    let irradiance_calibration =
        (instrument.calibration_for_scene)(scene, SpectralChannel::Irradiance);
    let mut plans = Vec::with_capacity(sample_count);
    for index in 0..sample_count {
        let nominal_wavelength_nm = resolved_axis.sample_at(index as u32)?;
        let radiance_integration = (instrument.integration_for_wavelength)(
            scene,
            Some(prepared),
            SpectralChannel::Radiance,
            nominal_wavelength_nm,
        )?;
        let irradiance_integration = (instrument.integration_for_wavelength)(
            scene,
            Some(prepared),
            SpectralChannel::Irradiance,
            nominal_wavelength_nm,
        )?;
        plans.push(WavelengthSampling {
            nominal_wavelength_nm,
            radiance_wavelength_nm: shifted_wavelength(radiance_calibration, nominal_wavelength_nm),
            irradiance_wavelength_nm: shifted_wavelength(
                irradiance_calibration,
                nominal_wavelength_nm,
            ),
            radiance_integration,
            irradiance_integration,
        });
    }
    Ok(plans)
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
