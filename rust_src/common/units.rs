#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    InvalidRange,
    InvalidValue,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct WavelengthRange {
    pub start_nm: f64,
    pub end_nm: f64,
}

impl Default for WavelengthRange {
    fn default() -> Self {
        Self {
            // The public scene model is wavelength-first; wavenumber conversion happens later.
            start_nm: 270.0,
            end_nm: 2400.0,
        }
    }
}

impl WavelengthRange {
    pub fn validate(self) -> Result<(), Error> {
        if !self.start_nm.is_finite() || !self.end_nm.is_finite() {
            return Err(Error::InvalidValue);
        }
        if self.end_nm <= self.start_nm {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct AltitudeRangeKm {
    pub bottom_km: f64,
    pub top_km: f64,
}

impl AltitudeRangeKm {
    pub fn validate(self) -> Result<(), Error> {
        if !self.bottom_km.is_finite() || !self.top_km.is_finite() {
            return Err(Error::InvalidValue);
        }
        if self.bottom_km < 0.0 || self.top_km < self.bottom_km {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct PressureRangeHpa {
    pub top_hpa: f64,
    pub bottom_hpa: f64,
}

impl PressureRangeHpa {
    pub fn validate(self) -> Result<(), Error> {
        if !self.top_hpa.is_finite() || !self.bottom_hpa.is_finite() {
            return Err(Error::InvalidValue);
        }
        if self.top_hpa <= 0.0 || self.bottom_hpa <= 0.0 || self.bottom_hpa < self.top_hpa {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct AngleDeg {
    pub value: f64,
}

impl AngleDeg {
    pub fn validate(self) -> Result<(), Error> {
        if !self.value.is_finite() {
            return Err(Error::InvalidValue);
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct ZenithAngleDeg {
    pub value: f64,
}

impl ZenithAngleDeg {
    pub fn validate(self) -> Result<(), Error> {
        // Keep finite-angle checks centralized so every angle wrapper rejects NaN the same way.
        AngleDeg { value: self.value }.validate()?;
        if self.value < 0.0 || self.value > 180.0 {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct AzimuthAngleDeg {
    pub value: f64,
}

impl AzimuthAngleDeg {
    pub fn validate(self) -> Result<(), Error> {
        // Keep finite-angle checks centralized so every angle wrapper rejects NaN the same way.
        AngleDeg { value: self.value }.validate()?;
        if self.value < 0.0 || self.value > 360.0 {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}
