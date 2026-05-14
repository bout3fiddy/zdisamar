use crate::{
    common::errors,
    input::atmosphere::types::{FractionKind, FractionTarget},
};

#[derive(Debug, Default, Clone, PartialEq)]
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
    pub fn validate(&self) -> Result<(), errors::Error> {
        if !self.enabled {
            if self.target != FractionTarget::None
                || self.kind != FractionKind::None
                || !self.values.is_empty()
                || !self.apriori_values.is_empty()
                || !self.variance_values.is_empty()
            {
                return Err(errors::Error::InvalidRequest);
            }
            return Ok(());
        }
        if self.target == FractionTarget::None
            || self.kind == FractionKind::None
            || self.values.is_empty()
        {
            return Err(errors::Error::InvalidRequest);
        }
        if self.kind == FractionKind::WavelIndependent && self.values.len() != 1 {
            return Err(errors::Error::InvalidRequest);
        }
        if self.kind == FractionKind::WavelDependent
            && self.wavelengths_nm.len() != self.values.len()
        {
            return Err(errors::Error::InvalidRequest);
        }
        if (!self.apriori_values.is_empty() && self.apriori_values.len() != self.values.len())
            || (!self.variance_values.is_empty() && self.variance_values.len() != self.values.len())
        {
            return Err(errors::Error::InvalidRequest);
        }
        for value in &self.values {
            validate_fraction(*value)?;
        }
        for value in &self.apriori_values {
            validate_fraction(*value)?;
        }
        for value in &self.variance_values {
            if !value.is_finite() || *value < 0.0 {
                return Err(errors::Error::InvalidRequest);
            }
        }
        for wavelength_nm in &self.wavelengths_nm {
            if !wavelength_nm.is_finite() || *wavelength_nm <= 0.0 {
                return Err(errors::Error::InvalidRequest);
            }
        }
        if self.kind == FractionKind::WavelDependent && self.wavelengths_nm.len() > 1 {
            for pair in self.wavelengths_nm.windows(2) {
                if pair[1] <= pair[0] {
                    return Err(errors::Error::InvalidRequest);
                }
            }
        }
        if self.threshold_cloud_fraction < 0.0 || self.threshold_cloud_fraction > 1.0 {
            return Err(errors::Error::InvalidRequest);
        }
        if self.threshold_variance < 0.0 {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn value_at_wavelength(&self, wavelength_nm: f64) -> f64 {
        if !self.enabled || self.values.is_empty() {
            return 0.0;
        }
        if self.kind != FractionKind::WavelDependent || self.wavelengths_nm.is_empty() {
            return clamp_fraction(self.values[0]);
        }
        if wavelength_nm <= self.wavelengths_nm[0] {
            return clamp_fraction(self.values[0]);
        }
        for index in 0..self.wavelengths_nm.len() - 1 {
            let left = self.wavelengths_nm[index];
            let right = self.wavelengths_nm[index + 1];
            if wavelength_nm > right {
                continue;
            }
            let span = right - left;
            if span <= 0.0 {
                return clamp_fraction(self.values[index + 1]);
            }
            let weight = clamp_fraction((wavelength_nm - left) / span);
            return clamp_fraction(
                self.values[index] + weight * (self.values[index + 1] - self.values[index]),
            );
        }
        clamp_fraction(*self.values.last().unwrap_or(&0.0))
    }
}

fn validate_fraction(value: f64) -> Result<(), errors::Error> {
    if !value.is_finite() || !(0.0..=1.0).contains(&value) {
        return Err(errors::Error::InvalidRequest);
    }
    Ok(())
}

fn clamp_fraction(value: f64) -> f64 {
    value.clamp(0.0, 1.0)
}
