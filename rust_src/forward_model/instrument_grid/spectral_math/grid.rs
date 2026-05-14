#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    InvalidSampleCount,
    InvalidBounds,
    IndexOutOfRange,
    InvalidExplicitSamples,
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SpectralGrid {
    pub start_nm: f64,
    pub end_nm: f64,
    pub sample_count: u32,
}

impl SpectralGrid {
    pub fn validate(self) -> Result<()> {
        if self.sample_count < 2 {
            return Err(Error::InvalidSampleCount);
        }
        if self.end_nm <= self.start_nm {
            return Err(Error::InvalidBounds);
        }
        Ok(())
    }

    pub fn sample_at(self, index: u32) -> Result<f64> {
        self.validate()?;
        if index >= self.sample_count {
            return Err(Error::IndexOutOfRange);
        }
        let step = (self.end_nm - self.start_nm) / f64::from(self.sample_count - 1);
        Ok(self.start_nm + step * f64::from(index))
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ResolvedAxis<'a> {
    pub base: SpectralGrid,
    pub explicit_wavelengths_nm: &'a [f64],
}

impl<'a> ResolvedAxis<'a> {
    pub fn validate(self) -> Result<()> {
        self.base.validate()?;
        if self.explicit_wavelengths_nm.is_empty() {
            return Ok(());
        }
        if self.explicit_wavelengths_nm.len() != self.base.sample_count as usize {
            return Err(Error::InvalidExplicitSamples);
        }
        validate_explicit_samples(self.explicit_wavelengths_nm)
    }

    pub fn sample_at(self, index: u32) -> Result<f64> {
        self.validate()?;
        if !self.explicit_wavelengths_nm.is_empty() {
            return sample_at_explicit(self.explicit_wavelengths_nm, index);
        }
        self.base.sample_at(index)
    }
}

pub fn validate_explicit_samples(wavelengths_nm: &[f64]) -> Result<()> {
    if wavelengths_nm.is_empty() {
        return Err(Error::InvalidExplicitSamples);
    }
    let mut previous = None;
    for &wavelength_nm in wavelengths_nm {
        if !wavelength_nm.is_finite() {
            return Err(Error::InvalidExplicitSamples);
        }
        if previous.is_some_and(|earlier| wavelength_nm <= earlier) {
            return Err(Error::InvalidExplicitSamples);
        }
        previous = Some(wavelength_nm);
    }
    Ok(())
}

pub fn sample_at_explicit(wavelengths_nm: &[f64], index: u32) -> Result<f64> {
    validate_explicit_samples(wavelengths_nm)?;
    wavelengths_nm
        .get(index as usize)
        .copied()
        .ok_or(Error::IndexOutOfRange)
}
