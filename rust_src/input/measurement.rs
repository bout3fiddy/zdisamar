use crate::common::errors::{Error, Result};

use super::{Binding, SpectralWindow};

#[derive(Debug, Clone, Default, PartialEq)]
pub struct SpectralMask {
    pub band: String,
    pub exclude: Vec<SpectralWindow>,
}

impl SpectralMask {
    pub fn validate(&self) -> Result<()> {
        let mut previous_end_nm = 0.0;
        for (index, window) in self.exclude.iter().enumerate() {
            window.validate()?;
            if index != 0 && window.start_nm < previous_end_nm {
                return Err(Error::InvalidRequest);
            }
            previous_end_nm = window.end_nm;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct ErrorModel {
    pub from_source_noise: bool,
    pub floor: f64,
}

impl ErrorModel {
    pub fn defines_covariance(self) -> bool {
        self.from_source_noise || self.floor > 0.0
    }

    pub fn validate(self) -> Result<()> {
        if !self.floor.is_finite() || self.floor < 0.0 {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum Quantity {
    #[default]
    Radiance,
    Irradiance,
    Reflectance,
    SlantColumn,
}

impl Quantity {
    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "radiance" => Ok(Self::Radiance),
            "irradiance" => Ok(Self::Irradiance),
            "reflectance" => Ok(Self::Reflectance),
            "slant_column" => Ok(Self::SlantColumn),
            _ => Err(Error::InvalidRequest),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Radiance => "radiance",
            Self::Irradiance => "irradiance",
            Self::Reflectance => "reflectance",
            Self::SlantColumn => "slant_column",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Measurement {
    pub product_name: String,
    pub observable: Quantity,
    pub sample_count: u32,
    pub source: Binding,
    pub mask: SpectralMask,
    pub error_model: ErrorModel,
}

impl Default for Measurement {
    fn default() -> Self {
        Self {
            product_name: String::new(),
            observable: Quantity::Radiance,
            sample_count: 0,
            source: Binding::None,
            mask: SpectralMask::default(),
            error_model: ErrorModel::default(),
        }
    }
}

impl Measurement {
    pub fn validate(&self) -> Result<()> {
        if self.sample_count == 0 {
            return Err(Error::InvalidRequest);
        }
        self.source.validate()?;
        self.mask.validate()?;
        self.error_model.validate()
    }

    pub fn resolved_product_name(&self) -> &str {
        if !self.product_name.is_empty() {
            return &self.product_name;
        }
        self.observable.label()
    }

    pub fn includes_wavelength(&self, wavelength_nm: f64) -> bool {
        for window in &self.mask.exclude {
            if wavelength_nm >= window.start_nm && wavelength_nm <= window.end_nm {
                return false;
            }
        }
        true
    }

    pub fn selected_sample_count(&self, wavelengths_nm: &[f64]) -> u32 {
        wavelengths_nm
            .iter()
            .filter(|wavelength_nm| self.includes_wavelength(**wavelength_nm))
            .count() as u32
    }
}

pub type MeasurementVector = Measurement;
