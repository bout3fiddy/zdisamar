use crate::common::{
    errors::{Error, Result},
    units::WavelengthRange,
};

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct SpectralWindow {
    pub start_nm: f64,
    pub end_nm: f64,
}

impl SpectralWindow {
    pub fn validate(self) -> Result<()> {
        WavelengthRange {
            start_nm: self.start_nm,
            end_nm: self.end_nm,
        }
        .validate()
        .map_err(|_| Error::InvalidRequest)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct SpectralBand {
    pub id: String,
    pub start_nm: f64,
    pub end_nm: f64,
    pub step_nm: f64,
    pub exclude: Vec<SpectralWindow>,
}

impl Default for SpectralBand {
    fn default() -> Self {
        Self {
            id: String::new(),
            start_nm: 0.0,
            end_nm: 0.0,
            step_nm: 0.0,
            exclude: Vec::new(),
        }
    }
}

impl SpectralBand {
    pub fn validate(&self) -> Result<()> {
        if self.id.is_empty() || !self.step_nm.is_finite() || self.step_nm <= 0.0 {
            return Err(Error::InvalidRequest);
        }
        WavelengthRange {
            start_nm: self.start_nm,
            end_nm: self.end_nm,
        }
        .validate()
        .map_err(|_| Error::InvalidRequest)?;

        // Exclusion windows are consumed in order, so overlapping windows are rejected here.
        let mut previous_end_nm = self.start_nm;
        for window in &self.exclude {
            window.validate()?;
            if window.start_nm < self.start_nm
                || window.end_nm > self.end_nm
                || window.start_nm < previous_end_nm
            {
                return Err(Error::InvalidRequest);
            }
            previous_end_nm = window.end_nm;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct SpectralBandSet {
    pub items: Vec<SpectralBand>,
}

impl SpectralBandSet {
    pub fn validate(&self) -> Result<()> {
        for (index, band) in self.items.iter().enumerate() {
            band.validate()?;
            for other in &self.items[index + 1..] {
                if band.id == other.id {
                    return Err(Error::InvalidRequest);
                }
            }
        }
        Ok(())
    }
}
