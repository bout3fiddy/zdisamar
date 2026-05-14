#[derive(Debug, Default, Clone, PartialEq)]
pub struct OperationalCrossSectionLut {
    pub wavelengths_nm: Vec<f64>,
    pub coefficients: Vec<f64>,
    pub temperature_coefficient_count: u8,
    pub pressure_coefficient_count: u8,
    pub min_temperature_k: f64,
    pub max_temperature_k: f64,
    pub min_pressure_hpa: f64,
    pub max_pressure_hpa: f64,
}
