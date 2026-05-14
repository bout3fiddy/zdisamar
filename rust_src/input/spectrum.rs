use crate::common::{errors, units};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SpectralGrid {
    pub start_nm: f64,
    pub end_nm: f64,
    pub sample_count: u32,
}

impl Default for SpectralGrid {
    fn default() -> Self {
        Self {
            start_nm: 270.0,
            end_nm: 2400.0,
            sample_count: 0,
        }
    }
}

impl SpectralGrid {
    pub fn validate(self) -> Result<(), errors::Error> {
        units::WavelengthRange {
            start_nm: self.start_nm,
            end_nm: self.end_nm,
        }
        .validate()
        .map_err(|_| errors::Error::InvalidRequest)?;

        if self.sample_count == 0 {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }
}
