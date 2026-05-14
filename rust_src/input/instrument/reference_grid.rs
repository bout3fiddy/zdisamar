use crate::common::errors;

#[derive(Debug, Default, Clone, PartialEq)]
pub struct OperationalReferenceGrid {
    pub wavelengths_nm: Vec<f64>,
    pub weights: Vec<f64>,
}

impl OperationalReferenceGrid {
    pub fn enabled(&self) -> bool {
        !self.wavelengths_nm.is_empty()
    }

    pub fn validate(&self) -> Result<(), errors::Error> {
        if !self.enabled() {
            return if self.weights.is_empty() {
                Ok(())
            } else {
                Err(errors::Error::InvalidRequest)
            };
        }
        if self.weights.len() != self.wavelengths_nm.len() {
            return Err(errors::Error::InvalidRequest);
        }

        let mut previous_wavelength = None;
        let mut weight_sum = 0.0;
        for (&wavelength_nm, &weight) in self.wavelengths_nm.iter().zip(&self.weights) {
            if !wavelength_nm.is_finite() || !weight.is_finite() || weight < 0.0 {
                return Err(errors::Error::InvalidRequest);
            }
            if previous_wavelength.is_some_and(|previous| wavelength_nm <= previous) {
                return Err(errors::Error::InvalidRequest);
            }
            previous_wavelength = Some(wavelength_nm);
            weight_sum += weight;
        }
        if !weight_sum.is_finite() || weight_sum <= 0.0 {
            return Err(errors::Error::InvalidRequest);
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

        if !pair_weight_sum.is_finite() || pair_weight_sum <= 0.0 {
            return 1.0;
        }
        weighted_spacing_sum / pair_weight_sum
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
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

    pub fn validate(self) -> Result<(), errors::Error> {
        if !self.enabled() {
            return Ok(());
        }
        if self.points_per_fwhm == 0
            || self.strong_line_min_divisions == 0
            || self.strong_line_max_divisions == 0
            || self.strong_line_max_divisions < self.strong_line_min_divisions
        {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }
}
