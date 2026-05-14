use crate::common::errors::{Error, Result};

use super::types::{FractionKind, FractionTarget};

#[derive(Debug, Clone, Default, PartialEq)]
pub struct FractionControl {
    pub enabled: bool,
    pub target: FractionTarget,
    pub kind: FractionKind,
    pub threshold_cloud_fraction: f64,
    pub threshold_variance: f64,
    pub wavelengths_nm: Vec<f64>,
    pub values: Vec<f64>,
    pub apriori_values: Vec<f64>,
    pub variance_values: Vec<f64>,
}

impl FractionControl {
    pub fn validate(&self) -> Result<()> {
        if !self.enabled {
            if self.target != FractionTarget::None
                || self.kind != FractionKind::None
                || !self.values.is_empty()
                || !self.apriori_values.is_empty()
                || !self.variance_values.is_empty()
            {
                return Err(Error::InvalidRequest);
            }
            return Ok(());
        }
        if self.target == FractionTarget::None || self.kind == FractionKind::None {
            return Err(Error::InvalidRequest);
        }
        if self.values.is_empty() {
            return Err(Error::InvalidRequest);
        }
        if self.kind == FractionKind::WavelIndependent && self.values.len() != 1 {
            return Err(Error::InvalidRequest);
        }
        if self.kind == FractionKind::WavelDependent
            && self.wavelengths_nm.len() != self.values.len()
        {
            return Err(Error::InvalidRequest);
        }
        if !self.apriori_values.is_empty() && self.apriori_values.len() != self.values.len() {
            return Err(Error::InvalidRequest);
        }
        if !self.variance_values.is_empty() && self.variance_values.len() != self.values.len() {
            return Err(Error::InvalidRequest);
        }
        for value in &self.values {
            validate_fraction_value(*value)?;
        }
        for value in &self.apriori_values {
            validate_fraction_value(*value)?;
        }
        for value in &self.variance_values {
            if !value.is_finite() || *value < 0.0 {
                return Err(Error::InvalidRequest);
            }
        }
        for wavelength_nm in &self.wavelengths_nm {
            if !wavelength_nm.is_finite() || *wavelength_nm <= 0.0 {
                return Err(Error::InvalidRequest);
            }
        }
        if self.kind == FractionKind::WavelDependent && self.wavelengths_nm.len() > 1 {
            let mut previous_wavelength_nm = self.wavelengths_nm[0];
            for wavelength_nm in &self.wavelengths_nm[1..] {
                if *wavelength_nm <= previous_wavelength_nm {
                    return Err(Error::InvalidRequest);
                }
                previous_wavelength_nm = *wavelength_nm;
            }
        }
        if self.threshold_cloud_fraction < 0.0 || self.threshold_cloud_fraction > 1.0 {
            return Err(Error::InvalidRequest);
        }
        if self.threshold_variance < 0.0 {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn value_at_wavelength(&self, wavelength_nm: f64) -> f64 {
        if !self.enabled || self.values.is_empty() {
            return 0.0;
        }
        if self.kind != FractionKind::WavelDependent || self.wavelengths_nm.is_empty() {
            return self.values[0].clamp(0.0, 1.0);
        }
        if wavelength_nm <= self.wavelengths_nm[0] {
            return self.values[0].clamp(0.0, 1.0);
        }

        for (index, window) in self.wavelengths_nm.windows(2).enumerate() {
            let left = window[0];
            let right = window[1];
            if wavelength_nm > right {
                continue;
            }
            let span = right - left;
            if span <= 0.0 {
                return self.values[index + 1].clamp(0.0, 1.0);
            }
            // Linear interpolation is enough here because the control grid is user-supplied.
            let weight = ((wavelength_nm - left) / span).clamp(0.0, 1.0);
            return (self.values[index] + weight * (self.values[index + 1] - self.values[index]))
                .clamp(0.0, 1.0);
        }

        self.values[self.values.len() - 1].clamp(0.0, 1.0)
    }
}

fn validate_fraction_value(value: f64) -> Result<()> {
    if !value.is_finite() || !(0.0..=1.0).contains(&value) {
        return Err(Error::InvalidRequest);
    }
    Ok(())
}
