use std::hash::Hasher;

use wyhash::WyHash;

use crate::{
    common::{errors, lut_controls},
    input::{
        absorber::AbsorberSet, aerosol::Aerosol, atmosphere::Atmosphere, bands::SpectralBandSet,
        cloud::Cloud, geometry::Geometry, observation_model::ObservationModel,
        spectrum::SpectralGrid, surface::Surface,
    },
};

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum DerivativeMode {
    #[default]
    None,
    SemiAnalytical,
    Numerical,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Scene {
    pub id: String,
    pub atmosphere: Atmosphere,
    pub geometry: Geometry,
    pub spectral_grid: SpectralGrid,
    pub bands: SpectralBandSet,
    pub absorbers: AbsorberSet,
    pub surface: Surface,
    pub cloud: Cloud,
    pub aerosol: Aerosol,
    pub observation_model: ObservationModel,
    pub lut_controls: lut_controls::Controls,
    pub phase_function_truncation_threshold: f64,
}

impl Default for Scene {
    fn default() -> Self {
        Self {
            id: "scene-0".to_string(),
            atmosphere: Atmosphere::default(),
            geometry: Geometry::default(),
            spectral_grid: SpectralGrid::default(),
            bands: SpectralBandSet::default(),
            absorbers: AbsorberSet::default(),
            surface: Surface::default(),
            cloud: Cloud::default(),
            aerosol: Aerosol::default(),
            observation_model: ObservationModel::default(),
            lut_controls: lut_controls::Controls::default(),
            phase_function_truncation_threshold: 1.0e-8,
        }
    }
}

impl Scene {
    pub fn validate(&self) -> Result<(), errors::Error> {
        if self.id.is_empty() {
            return Err(errors::Error::MissingScene);
        }

        self.atmosphere.validate()?;
        self.geometry.validate()?;
        self.spectral_grid.validate()?;
        self.bands.validate()?;
        self.absorbers.validate()?;
        self.surface.validate()?;
        self.cloud.validate()?;
        self.aerosol.validate()?;
        self.observation_model.validate()?;
        self.lut_controls.validate()?;
        if !self.phase_function_truncation_threshold.is_finite()
            || self.phase_function_truncation_threshold <= 0.0
        {
            return Err(errors::Error::InvalidRequest);
        }
        self.observation_model
            .cross_section_fit
            .validate_for_band_count(self.bands.items.len())?;
        let explicit_operational_band_count = self.observation_model.operational_band_support.len();
        if !self.bands.items.is_empty()
            && explicit_operational_band_count != 0
            && explicit_operational_band_count != self.bands.items.len()
        {
            return Err(errors::Error::InvalidRequest);
        }
        if !self.observation_model.measured_wavelengths_nm.is_empty()
            && self.observation_model.measured_wavelengths_nm.len()
                != self.spectral_grid.sample_count as usize
        {
            // Explicit measured channels and the scene spectral grid must agree
            // before the scene is ready for RTM execution.
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn lut_compatibility_key(&self) -> lut_controls::CompatibilityKey {
        let support = self.observation_model.primary_operational_band_support();
        let nominal_bounds = self.lut_nominal_wavelength_bounds();
        let low_resolution_sampling = self.lut_low_resolution_sampling_identity();
        lut_controls::CompatibilityKey {
            controls: self.lut_controls,
            spectral_start_nm: nominal_bounds.start_nm,
            spectral_end_nm: nominal_bounds.end_nm,
            nominal_sample_count: low_resolution_sampling.sample_count,
            nominal_wavelength_hash: low_resolution_sampling.wavelength_hash,
            solar_zenith_deg: self.geometry.solar_zenith_deg,
            viewing_zenith_deg: self.geometry.viewing_zenith_deg,
            relative_azimuth_deg: self.geometry.relative_azimuth_deg,
            surface_albedo: self.surface.albedo,
            instrument_line_fwhm_nm: self.observation_model.instrument_line_fwhm_nm,
            high_resolution_step_nm: support.high_resolution_step_nm,
            high_resolution_half_span_nm: support.high_resolution_half_span_nm,
            lut_sampling_half_span_nm: self.observation_model.lut_sampling_half_span_nm(),
        }
    }

    pub fn lut_nominal_wavelength_bounds(&self) -> WavelengthBounds {
        let nominal_wavelengths = &self.observation_model.measured_wavelengths_nm;
        if !nominal_wavelengths.is_empty() {
            return WavelengthBounds {
                start_nm: nominal_wavelengths[0],
                end_nm: nominal_wavelengths[nominal_wavelengths.len() - 1],
            };
        }
        WavelengthBounds {
            start_nm: self.spectral_grid.start_nm,
            end_nm: self.spectral_grid.end_nm,
        }
    }

    pub fn uses_high_resolution_lut_sampling(&self) -> bool {
        let support = self.observation_model.primary_operational_band_support();
        support.high_resolution_step_nm > 0.0
            && self.observation_model.lut_sampling_half_span_nm() > 0.0
    }

    fn lut_low_resolution_sampling_identity(&self) -> LowResolutionSamplingIdentity {
        if self.uses_high_resolution_lut_sampling() {
            return LowResolutionSamplingIdentity {
                sample_count: 0,
                wavelength_hash: 0,
            };
        }

        let nominal_wavelengths = &self.observation_model.measured_wavelengths_nm;
        if !nominal_wavelengths.is_empty() {
            return LowResolutionSamplingIdentity {
                sample_count: nominal_wavelengths.len() as u32,
                wavelength_hash: hash_wavelengths(nominal_wavelengths),
            };
        }

        LowResolutionSamplingIdentity {
            sample_count: self.spectral_grid.sample_count,
            wavelength_hash: 0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct WavelengthBounds {
    pub start_nm: f64,
    pub end_nm: f64,
}

struct LowResolutionSamplingIdentity {
    sample_count: u32,
    wavelength_hash: u64,
}

fn hash_wavelengths(wavelengths_nm: &[f64]) -> u64 {
    let mut hasher = WyHash::with_seed(0);
    for wavelength_nm in wavelengths_nm {
        // Native-endian bytes keep this cache key tied to the process-local f64 representation.
        hasher.write(&wavelength_nm.to_ne_bytes());
    }
    hasher.finish()
}
