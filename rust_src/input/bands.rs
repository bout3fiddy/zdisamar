use crate::common::{errors, units};

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct SpectralWindow {
    pub start_nm: f64,
    pub end_nm: f64,
}

impl SpectralWindow {
    pub fn validate(self) -> Result<(), errors::Error> {
        units::WavelengthRange {
            start_nm: self.start_nm,
            end_nm: self.end_nm,
        }
        .validate()
        .map_err(|_| errors::Error::InvalidRequest)
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct SpectralBand {
    pub id: String,
    pub start_nm: f64,
    pub end_nm: f64,
    pub step_nm: f64,
    pub exclude: Vec<SpectralWindow>,
}

impl SpectralBand {
    pub fn validate(&self) -> Result<(), errors::Error> {
        if self.id.is_empty() || !self.step_nm.is_finite() || self.step_nm <= 0.0 {
            return Err(errors::Error::InvalidRequest);
        }

        units::WavelengthRange {
            start_nm: self.start_nm,
            end_nm: self.end_nm,
        }
        .validate()
        .map_err(|_| errors::Error::InvalidRequest)?;

        let mut previous_end_nm = self.start_nm;
        for window in &self.exclude {
            window.validate()?;
            if window.start_nm < self.start_nm
                || window.end_nm > self.end_nm
                || window.start_nm < previous_end_nm
            {
                return Err(errors::Error::InvalidRequest);
            }
            previous_end_nm = window.end_nm;
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct SpectralBandSet {
    pub items: Vec<SpectralBand>,
}

impl SpectralBandSet {
    pub fn validate(&self) -> Result<(), errors::Error> {
        for (index, band) in self.items.iter().enumerate() {
            band.validate()?;
            for other in &self.items[index + 1..] {
                if band.id == other.id {
                    return Err(errors::Error::InvalidRequest);
                }
            }
        }
        Ok(())
    }
}
