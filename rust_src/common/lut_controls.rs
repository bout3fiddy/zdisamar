use crate::common::errors::{Error, Result};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum Mode {
    #[default]
    Direct,
    Generate,
    Consume,
}

impl Mode {
    pub fn label(self) -> &'static str {
        match self {
            Self::Direct => "direct",
            Self::Generate => "generate",
            Self::Consume => "consume",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "direct" => Some(Self::Direct),
            "generate" => Some(Self::Generate),
            "consume" => Some(Self::Consume),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct ReflectanceControls {
    pub reflectance_mode: Mode,
    pub correction_mode: Mode,
    pub use_chandra_formula: bool,
    pub surface_albedo: f64,
}

impl ReflectanceControls {
    pub fn enabled(self) -> bool {
        self.reflectance_mode != Mode::Direct || self.correction_mode != Mode::Direct
    }

    pub fn validate(self) -> Result<()> {
        if !self.surface_albedo.is_finite() || self.surface_albedo < 0.0 {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn matches(self, other: Self) -> bool {
        self.reflectance_mode == other.reflectance_mode
            && self.correction_mode == other.correction_mode
            && self.use_chandra_formula == other.use_chandra_formula
            && approx_eq_compatible_f64(self.surface_albedo, other.surface_albedo)
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct XsecControls {
    pub mode: Mode,
    pub min_temperature_k: f64,
    pub max_temperature_k: f64,
    pub min_pressure_hpa: f64,
    pub max_pressure_hpa: f64,
    pub temperature_grid_count: u8,
    pub pressure_grid_count: u8,
    pub temperature_coefficient_count: u8,
    pub pressure_coefficient_count: u8,
}

impl XsecControls {
    pub fn enabled(self) -> bool {
        self.mode != Mode::Direct
    }

    pub fn coefficient_count(self) -> u32 {
        // Widen before multiplying so two valid u8 counts cannot overflow.
        u32::from(self.temperature_coefficient_count) * u32::from(self.pressure_coefficient_count)
    }

    pub fn validate(self) -> Result<()> {
        if self.mode == Mode::Direct {
            return Ok(());
        }

        if !self.min_temperature_k.is_finite()
            || !self.max_temperature_k.is_finite()
            || !self.min_pressure_hpa.is_finite()
            || !self.max_pressure_hpa.is_finite()
        {
            return Err(Error::InvalidRequest);
        }
        if self.min_temperature_k <= 0.0 || self.max_temperature_k <= self.min_temperature_k {
            return Err(Error::InvalidRequest);
        }
        if self.min_pressure_hpa <= 0.0 || self.max_pressure_hpa <= self.min_pressure_hpa {
            return Err(Error::InvalidRequest);
        }
        if self.temperature_grid_count == 0
            || self.pressure_grid_count == 0
            || self.temperature_coefficient_count == 0
            || self.pressure_coefficient_count == 0
        {
            return Err(Error::InvalidRequest);
        }
        if self.temperature_coefficient_count > self.temperature_grid_count
            || self.pressure_coefficient_count > self.pressure_grid_count
        {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn matches(self, other: Self) -> bool {
        self.mode == other.mode
            && approx_eq_compatible_f64(self.min_temperature_k, other.min_temperature_k)
            && approx_eq_compatible_f64(self.max_temperature_k, other.max_temperature_k)
            && approx_eq_compatible_f64(self.min_pressure_hpa, other.min_pressure_hpa)
            && approx_eq_compatible_f64(self.max_pressure_hpa, other.max_pressure_hpa)
            && self.temperature_grid_count == other.temperature_grid_count
            && self.pressure_grid_count == other.pressure_grid_count
            && self.temperature_coefficient_count == other.temperature_coefficient_count
            && self.pressure_coefficient_count == other.pressure_coefficient_count
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Controls {
    pub reflectance: ReflectanceControls,
    pub xsec: XsecControls,
}

impl Controls {
    pub fn enabled(self) -> bool {
        self.reflectance.enabled() || self.xsec.enabled()
    }

    pub fn validate(self) -> Result<()> {
        self.reflectance.validate()?;
        self.xsec.validate()
    }

    pub fn matches(self, other: Self) -> bool {
        self.reflectance.matches(other.reflectance) && self.xsec.matches(other.xsec)
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct CompatibilityKey {
    pub controls: Controls,
    pub spectral_start_nm: f64,
    pub spectral_end_nm: f64,
    pub nominal_sample_count: u32,
    pub nominal_wavelength_hash: u64,
    pub solar_zenith_deg: f64,
    pub viewing_zenith_deg: f64,
    pub relative_azimuth_deg: f64,
    pub surface_albedo: f64,
    pub instrument_line_fwhm_nm: f64,
    pub high_resolution_step_nm: f64,
    pub high_resolution_half_span_nm: f64,
    pub lut_sampling_half_span_nm: f64,
}

impl CompatibilityKey {
    pub fn enabled(self) -> bool {
        self.controls.enabled()
    }

    pub fn validate(self) -> Result<()> {
        self.controls.validate()?;
        if !self.enabled() {
            return Ok(());
        }

        if !self.spectral_start_nm.is_finite()
            || !self.spectral_end_nm.is_finite()
            || !self.solar_zenith_deg.is_finite()
            || !self.viewing_zenith_deg.is_finite()
            || !self.relative_azimuth_deg.is_finite()
            || !self.surface_albedo.is_finite()
            || !self.instrument_line_fwhm_nm.is_finite()
            || !self.high_resolution_step_nm.is_finite()
            || !self.high_resolution_half_span_nm.is_finite()
            || !self.lut_sampling_half_span_nm.is_finite()
        {
            return Err(Error::InvalidRequest);
        }
        if self.spectral_end_nm <= self.spectral_start_nm {
            return Err(Error::InvalidRequest);
        }
        if self.surface_albedo < 0.0 || self.instrument_line_fwhm_nm < 0.0 {
            return Err(Error::InvalidRequest);
        }
        if self.high_resolution_step_nm < 0.0
            || self.high_resolution_half_span_nm < 0.0
            || self.lut_sampling_half_span_nm < 0.0
        {
            return Err(Error::InvalidRequest);
        }
        if (self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0) {
            return Err(Error::InvalidRequest);
        }
        if self.high_resolution_step_nm > 0.0 {
            if self.nominal_sample_count != 0 || self.nominal_wavelength_hash != 0 {
                return Err(Error::InvalidRequest);
            }
        } else if self.nominal_sample_count == 0 {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn matches(self, other: Self) -> bool {
        self.controls.matches(other.controls)
            && approx_eq_compatible_f64(self.spectral_start_nm, other.spectral_start_nm)
            && approx_eq_compatible_f64(self.spectral_end_nm, other.spectral_end_nm)
            && self.nominal_sample_count == other.nominal_sample_count
            && self.nominal_wavelength_hash == other.nominal_wavelength_hash
            && approx_eq_compatible_f64(self.solar_zenith_deg, other.solar_zenith_deg)
            && approx_eq_compatible_f64(self.viewing_zenith_deg, other.viewing_zenith_deg)
            && approx_eq_compatible_f64(self.relative_azimuth_deg, other.relative_azimuth_deg)
            && approx_eq_compatible_f64(self.surface_albedo, other.surface_albedo)
            && approx_eq_compatible_f64(self.instrument_line_fwhm_nm, other.instrument_line_fwhm_nm)
            && approx_eq_compatible_f64(self.high_resolution_step_nm, other.high_resolution_step_nm)
            && approx_eq_compatible_f64(
                self.high_resolution_half_span_nm,
                other.high_resolution_half_span_nm,
            )
            && approx_eq_compatible_f64(
                self.lut_sampling_half_span_nm,
                other.lut_sampling_half_span_nm,
            )
    }
}

fn approx_eq_compatible_f64(lhs: f64, rhs: f64) -> bool {
    lhs == rhs || (lhs - rhs).abs() <= 1.0e-12 || relative_diff(lhs, rhs) <= 1.0e-12
}

fn relative_diff(lhs: f64, rhs: f64) -> f64 {
    let scale = lhs.abs().max(rhs.abs()).max(f64::MIN_POSITIVE);
    (lhs - rhs).abs() / scale
}
