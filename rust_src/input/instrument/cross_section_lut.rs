use crate::{
    common::errors,
    input::instrument::{
        constants::{
            MAX_OPERATIONAL_REFSPEC_PRESSURE_COEFFICIENTS,
            MAX_OPERATIONAL_REFSPEC_TEMPERATURE_COEFFICIENTS,
        },
        cross_section_lut_eval,
    },
};

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

impl OperationalCrossSectionLut {
    pub fn enabled(&self) -> bool {
        !self.wavelengths_nm.is_empty()
    }

    pub fn validate(&self) -> Result<(), errors::Error> {
        if !self.enabled() {
            if self.coefficients.is_empty()
                && self.temperature_coefficient_count == 0
                && self.pressure_coefficient_count == 0
            {
                return Ok(());
            }
            return Err(errors::Error::InvalidRequest);
        }

        let temperature_count = usize::from(self.temperature_coefficient_count);
        let pressure_count = usize::from(self.pressure_coefficient_count);
        if temperature_count == 0
            || temperature_count > MAX_OPERATIONAL_REFSPEC_TEMPERATURE_COEFFICIENTS
            || pressure_count == 0
            || pressure_count > MAX_OPERATIONAL_REFSPEC_PRESSURE_COEFFICIENTS
        {
            return Err(errors::Error::InvalidRequest);
        }

        if !self.min_temperature_k.is_finite()
            || !self.max_temperature_k.is_finite()
            || !self.min_pressure_hpa.is_finite()
            || !self.max_pressure_hpa.is_finite()
            || self.min_temperature_k <= 0.0
            || self.max_temperature_k <= self.min_temperature_k
            || self.min_pressure_hpa <= 0.0
            || self.max_pressure_hpa <= self.min_pressure_hpa
        {
            return Err(errors::Error::InvalidRequest);
        }

        let mut previous_wavelength = None;
        for &wavelength_nm in &self.wavelengths_nm {
            if !wavelength_nm.is_finite() {
                return Err(errors::Error::InvalidRequest);
            }
            if previous_wavelength.is_some_and(|previous| wavelength_nm <= previous) {
                return Err(errors::Error::InvalidRequest);
            }
            previous_wavelength = Some(wavelength_nm);
        }

        let expected_count = self.wavelengths_nm.len() * temperature_count * pressure_count;
        if self.coefficients.len() != expected_count {
            return Err(errors::Error::InvalidRequest);
        }
        if self.coefficients.iter().any(|value| !value.is_finite()) {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn sigma_at(&self, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) -> f64 {
        cross_section_lut_eval::evaluate(self, wavelength_nm, temperature_k, pressure_hpa).sigma
    }

    pub fn d_sigma_d_temperature_at(
        &self,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) -> f64 {
        cross_section_lut_eval::evaluate(self, wavelength_nm, temperature_k, pressure_hpa)
            .d_sigma_d_temperature
    }
}
