use crate::forward_model::{implementations, jacobian::Vector};

pub const REFLECTANCE_EXPORT_NAME: &str = "reflectance";
pub const FITTED_REFLECTANCE_EXPORT_NAME: &str = "fitted_reflectance";

#[derive(Debug, Clone, Copy)]
pub struct Implementations {
    pub transport: implementations::transport::Implementation,
    pub surface: implementations::surface::Implementation,
    pub instrument: implementations::instrument::Implementation,
    pub noise: implementations::noise::Implementation,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct InstrumentGridSummary {
    pub sample_count: u32,
    pub wavelength_start_nm: f64,
    pub wavelength_end_nm: f64,
    pub mean_radiance: f64,
    pub mean_irradiance: f64,
    pub mean_reflectance: f64,
    pub mean_noise_sigma: f64,
    pub mean_jacobian: Option<Vector>,
}

impl Default for InstrumentGridSummary {
    fn default() -> Self {
        Self {
            sample_count: 0,
            wavelength_start_nm: 0.0,
            wavelength_end_nm: 0.0,
            mean_radiance: 0.0,
            mean_irradiance: 0.0,
            mean_reflectance: 0.0,
            mean_noise_sigma: 0.0,
            mean_jacobian: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct InstrumentGridProduct {
    pub summary: InstrumentGridSummary,
    pub wavelengths: Vec<f64>,
    pub radiance: Vec<f64>,
    pub irradiance: Vec<f64>,
    pub reflectance: Vec<f64>,
    pub noise_sigma: Vec<f64>,
    pub radiance_noise_sigma: Vec<f64>,
    pub irradiance_noise_sigma: Vec<f64>,
    pub reflectance_noise_sigma: Vec<f64>,
    pub jacobian: Option<Vec<f64>>,
    pub effective_air_mass_factor: f64,
    pub effective_single_scatter_albedo: f64,
    pub effective_temperature_k: f64,
    pub effective_pressure_hpa: f64,
    pub gas_optical_depth: f64,
    pub cia_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub total_optical_depth: f64,
    pub depolarization_factor: f64,
    pub d_optical_depth_d_temperature: f64,
}

impl Default for InstrumentGridProduct {
    fn default() -> Self {
        Self {
            summary: InstrumentGridSummary::default(),
            wavelengths: Vec::new(),
            radiance: Vec::new(),
            irradiance: Vec::new(),
            reflectance: Vec::new(),
            noise_sigma: Vec::new(),
            radiance_noise_sigma: Vec::new(),
            irradiance_noise_sigma: Vec::new(),
            reflectance_noise_sigma: Vec::new(),
            jacobian: None,
            effective_air_mass_factor: 0.0,
            effective_single_scatter_albedo: 0.0,
            effective_temperature_k: 0.0,
            effective_pressure_hpa: 0.0,
            gas_optical_depth: 0.0,
            cia_optical_depth: 0.0,
            aerosol_optical_depth: 0.0,
            cloud_optical_depth: 0.0,
            total_optical_depth: 0.0,
            depolarization_factor: 0.0,
            d_optical_depth_d_temperature: 0.0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct InstrumentGridProductView<'a> {
    pub summary: InstrumentGridSummary,
    pub wavelengths: &'a [f64],
    pub radiance: &'a [f64],
    pub irradiance: &'a [f64],
    pub reflectance: &'a [f64],
    pub noise_sigma: &'a [f64],
    pub radiance_noise_sigma: &'a [f64],
    pub irradiance_noise_sigma: &'a [f64],
    pub reflectance_noise_sigma: &'a [f64],
    pub jacobian: Option<&'a [f64]>,
    pub effective_air_mass_factor: f64,
    pub effective_single_scatter_albedo: f64,
    pub effective_temperature_k: f64,
    pub effective_pressure_hpa: f64,
    pub gas_optical_depth: f64,
    pub cia_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub total_optical_depth: f64,
    pub depolarization_factor: f64,
    pub d_optical_depth_d_temperature: f64,
}

impl<'a> Default for InstrumentGridProductView<'a> {
    fn default() -> Self {
        Self {
            summary: InstrumentGridSummary::default(),
            wavelengths: &[],
            radiance: &[],
            irradiance: &[],
            reflectance: &[],
            noise_sigma: &[],
            radiance_noise_sigma: &[],
            irradiance_noise_sigma: &[],
            reflectance_noise_sigma: &[],
            jacobian: None,
            effective_air_mass_factor: 0.0,
            effective_single_scatter_albedo: 0.0,
            effective_temperature_k: 0.0,
            effective_pressure_hpa: 0.0,
            gas_optical_depth: 0.0,
            cia_optical_depth: 0.0,
            aerosol_optical_depth: 0.0,
            cloud_optical_depth: 0.0,
            total_optical_depth: 0.0,
            depolarization_factor: 0.0,
            d_optical_depth_d_temperature: 0.0,
        }
    }
}

impl InstrumentGridProductView<'_> {
    pub fn to_owned_product(self) -> InstrumentGridProduct {
        // Zig can let two slices point at one allocation and free it once.
        // Rust keeps each Vec as the owner of its buffer, so each public column is cloned.
        InstrumentGridProduct {
            summary: self.summary,
            wavelengths: self.wavelengths.to_vec(),
            radiance: self.radiance.to_vec(),
            irradiance: self.irradiance.to_vec(),
            reflectance: self.reflectance.to_vec(),
            noise_sigma: self.noise_sigma.to_vec(),
            radiance_noise_sigma: self.radiance_noise_sigma.to_vec(),
            irradiance_noise_sigma: self.irradiance_noise_sigma.to_vec(),
            reflectance_noise_sigma: self.reflectance_noise_sigma.to_vec(),
            jacobian: self.jacobian.map(<[f64]>::to_vec),
            effective_air_mass_factor: self.effective_air_mass_factor,
            effective_single_scatter_albedo: self.effective_single_scatter_albedo,
            effective_temperature_k: self.effective_temperature_k,
            effective_pressure_hpa: self.effective_pressure_hpa,
            gas_optical_depth: self.gas_optical_depth,
            cia_optical_depth: self.cia_optical_depth,
            aerosol_optical_depth: self.aerosol_optical_depth,
            cloud_optical_depth: self.cloud_optical_depth,
            total_optical_depth: self.total_optical_depth,
            depolarization_factor: self.depolarization_factor,
            d_optical_depth_d_temperature: self.d_optical_depth_d_temperature,
        }
    }
}
