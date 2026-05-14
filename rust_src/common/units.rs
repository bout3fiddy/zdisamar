#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    InvalidRange,
    InvalidValue,
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct WavelengthRange {
    pub start_nm: f64,
    pub end_nm: f64,
}

impl Default for WavelengthRange {
    fn default() -> Self {
        Self {
            start_nm: 270.0,
            end_nm: 2400.0,
        }
    }
}

impl WavelengthRange {
    pub fn validate(self) -> Result<()> {
        if !self.start_nm.is_finite() || !self.end_nm.is_finite() {
            return Err(Error::InvalidValue);
        }
        if self.end_nm <= self.start_nm {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct AltitudeRangeKm {
    pub bottom_km: f64,
    pub top_km: f64,
}

impl AltitudeRangeKm {
    pub fn validate(self) -> Result<()> {
        if !self.bottom_km.is_finite() || !self.top_km.is_finite() {
            return Err(Error::InvalidValue);
        }
        if self.bottom_km < 0.0 || self.top_km < self.bottom_km {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct PressureRangeHpa {
    pub top_hpa: f64,
    pub bottom_hpa: f64,
}

impl PressureRangeHpa {
    pub fn validate(self) -> Result<()> {
        if !self.top_hpa.is_finite() || !self.bottom_hpa.is_finite() {
            return Err(Error::InvalidValue);
        }
        if self.top_hpa <= 0.0 || self.bottom_hpa <= 0.0 || self.bottom_hpa < self.top_hpa {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct AngleDeg {
    pub value: f64,
}

impl AngleDeg {
    pub fn validate(self) -> Result<()> {
        if !self.value.is_finite() {
            return Err(Error::InvalidValue);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct ZenithAngleDeg {
    pub value: f64,
}

impl ZenithAngleDeg {
    pub fn validate(self) -> Result<()> {
        AngleDeg { value: self.value }.validate()?;
        if self.value < 0.0 || self.value > 180.0 {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct AzimuthAngleDeg {
    pub value: f64,
}

impl AzimuthAngleDeg {
    pub fn validate(self) -> Result<()> {
        AngleDeg { value: self.value }.validate()?;
        if self.value < 0.0 || self.value > 360.0 {
            return Err(Error::InvalidRange);
        }
        Ok(())
    }
}
