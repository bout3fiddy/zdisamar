use crate::common::errors::{Error, Result};

#[derive(Debug, Clone, Default, PartialEq)]
pub struct OperationalReferenceGrid {
    pub wavelengths_nm: Vec<f64>,
    pub weights: Vec<f64>,
}

impl OperationalReferenceGrid {
    pub fn enabled(&self) -> bool {
        !self.wavelengths_nm.is_empty()
    }

    pub fn validate(&self) -> Result<()> {
        if !self.enabled() {
            if !self.weights.is_empty() {
                return Err(Error::InvalidRequest);
            }
            return Ok(());
        }
        if self.weights.len() != self.wavelengths_nm.len() {
            return Err(Error::InvalidRequest);
        }

        let mut previous_wavelength = None;
        let mut weight_sum = 0.0;
        for (&wavelength_nm, &weight) in self.wavelengths_nm.iter().zip(&self.weights) {
            if !wavelength_nm.is_finite() || !weight.is_finite() || weight < 0.0 {
                return Err(Error::InvalidRequest);
            }
            if let Some(previous) = previous_wavelength
                && wavelength_nm <= previous
            {
                return Err(Error::InvalidRequest);
            }
            previous_wavelength = Some(wavelength_nm);
            weight_sum += weight;
        }
        if weight_sum <= 0.0 || !weight_sum.is_finite() {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn effective_spacing_nm(&self) -> f64 {
        if self.wavelengths_nm.len() < 2 {
            return 1.0;
        }

        let mut weighted_spacing_sum = 0.0;
        let mut pair_weight_sum = 0.0;
        for index in 0..self.wavelengths_nm.len() - 1 {
            let pair_weight = 0.5 * (self.weights[index] + self.weights[index + 1]);
            weighted_spacing_sum +=
                pair_weight * (self.wavelengths_nm[index + 1] - self.wavelengths_nm[index]);
            pair_weight_sum += pair_weight;
        }
        if pair_weight_sum <= 0.0 || !pair_weight_sum.is_finite() {
            return 1.0;
        }
        weighted_spacing_sum / pair_weight_sum
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct AdaptiveReferenceGrid {
    pub points_per_fwhm: u16,
    pub strong_line_min_divisions: u16,
    pub strong_line_max_divisions: u16,
}

impl AdaptiveReferenceGrid {
    pub fn enabled(self) -> bool {
        self.points_per_fwhm != 0
            || self.strong_line_min_divisions != 0
            || self.strong_line_max_divisions != 0
    }

    pub fn validate(self) -> Result<()> {
        if !self.enabled() {
            return Ok(());
        }
        if self.points_per_fwhm == 0
            || self.strong_line_min_divisions == 0
            || self.strong_line_max_divisions == 0
            || self.strong_line_max_divisions < self.strong_line_min_divisions
        {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}
