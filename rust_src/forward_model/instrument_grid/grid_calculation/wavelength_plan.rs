use crate::forward_model::implementations::instrument::IntegrationKernel;

#[derive(Debug, Clone, PartialEq)]
pub struct WavelengthSampling {
    pub nominal_wavelength_nm: f64,
    pub radiance_wavelength_nm: f64,
    pub irradiance_wavelength_nm: f64,
    pub radiance_integration: IntegrationKernel,
    pub irradiance_integration: IntegrationKernel,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ForwardCacheMiss {
    pub key: u64,
    pub wavelength_nm: f64,
}
