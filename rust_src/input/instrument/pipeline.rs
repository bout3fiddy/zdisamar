use crate::common::errors::{Error, Result};

use super::{BuiltinLineShapeKind, InstrumentLineShape, InstrumentLineShapeTable};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpectralChannel {
    Radiance,
    Irradiance,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum SamplingMode {
    #[default]
    Native,
    Operational,
    MeasuredChannels,
    Synthetic,
}

impl SamplingMode {
    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "native" => Ok(Self::Native),
            "operational" => Ok(Self::Operational),
            "measured_channels" => Ok(Self::MeasuredChannels),
            "synthetic" => Ok(Self::Synthetic),
            _ => Err(Error::InvalidRequest),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Native => "native",
            Self::Operational => "operational",
            Self::MeasuredChannels => "measured_channels",
            Self::Synthetic => "synthetic",
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum NoiseModelKind {
    #[default]
    None,
    ShotNoise,
    S5pOperational,
    LabOperational,
    SnrFromInput,
}

impl NoiseModelKind {
    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "none" => Ok(Self::None),
            "shot_noise" => Ok(Self::ShotNoise),
            "s5p_operational" => Ok(Self::S5pOperational),
            "lab_operational" => Ok(Self::LabOperational),
            "snr_from_input" => Ok(Self::SnrFromInput),
            _ => Err(Error::InvalidRequest),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::ShotNoise => "shot_noise",
            Self::S5pOperational => "s5p_operational",
            Self::LabOperational => "lab_operational",
            Self::SnrFromInput => "snr_from_input",
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum SlitIndex {
    #[default]
    GaussianModulated,
    FlatTopN4,
    TripleFlatTopN4,
    Table,
}

impl SlitIndex {
    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "0" | "gaussian" | "gaussian_modulated" => Ok(Self::GaussianModulated),
            "1" | "flat_top" | "flat_top_n4" => Ok(Self::FlatTopN4),
            "2" | "triple_flat_top" | "triple_flat_top_n4" => Ok(Self::TripleFlatTopN4),
            "5" | "table" => Ok(Self::Table),
            _ => Err(Error::InvalidRequest),
        }
    }

    pub fn builtin_kind(self) -> BuiltinLineShapeKind {
        match self {
            Self::GaussianModulated | Self::Table => BuiltinLineShapeKind::Gaussian,
            Self::FlatTopN4 => BuiltinLineShapeKind::FlatTopN4,
            Self::TripleFlatTopN4 => BuiltinLineShapeKind::TripleFlatTopN4,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct NodalCorrection {
    pub wavelengths_nm: Vec<f64>,
    pub values: Vec<f64>,
    pub variances: Vec<f64>,
    pub use_linear_interpolation: bool,
    pub use_reference_spectrum: bool,
    pub use_characteristic_bias: bool,
    pub characteristic_bias: Vec<f64>,
}

impl NodalCorrection {
    pub fn enabled(&self) -> bool {
        !self.wavelengths_nm.is_empty() || !self.values.is_empty()
    }

    pub fn validate(&self) -> Result<()> {
        if self.wavelengths_nm.is_empty()
            && self.values.is_empty()
            && self.variances.is_empty()
            && self.characteristic_bias.is_empty()
        {
            return Ok(());
        }
        if self.wavelengths_nm.is_empty()
            || self.values.is_empty()
            || self.wavelengths_nm.len() != self.values.len()
        {
            return Err(Error::InvalidRequest);
        }
        if !self.variances.is_empty() && self.variances.len() != self.values.len() {
            return Err(Error::InvalidRequest);
        }
        if !self.characteristic_bias.is_empty()
            && self.characteristic_bias.len() != self.values.len()
        {
            return Err(Error::InvalidRequest);
        }

        let mut previous_wavelength = None;
        for (index, (&wavelength_nm, &value)) in
            self.wavelengths_nm.iter().zip(&self.values).enumerate()
        {
            if !wavelength_nm.is_finite() || !value.is_finite() {
                return Err(Error::InvalidRequest);
            }
            if let Some(previous) = previous_wavelength
                && wavelength_nm <= previous
            {
                return Err(Error::InvalidRequest);
            }
            previous_wavelength = Some(wavelength_nm);
            if let Some(variance) = self.variances.get(index)
                && (!variance.is_finite() || *variance < 0.0)
            {
                return Err(Error::InvalidRequest);
            }
            if let Some(bias) = self.characteristic_bias.get(index)
                && !bias.is_finite()
            {
                return Err(Error::InvalidRequest);
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum IntegrationMode {
    #[default]
    Auto,
    ExplicitHrGrid,
    DisamarHrGrid,
    Adaptive,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SpectralResponse {
    pub explicit: bool,
    pub slit_index: SlitIndex,
    pub fwhm_nm: f64,
    pub amplitude: f64,
    pub scale: f64,
    pub phase_deg: f64,
    pub builtin_line_shape: BuiltinLineShapeKind,
    pub integration_mode: IntegrationMode,
    pub high_resolution_step_nm: f64,
    pub high_resolution_half_span_nm: f64,
    pub instrument_line_shape: InstrumentLineShape,
    pub instrument_line_shape_table: InstrumentLineShapeTable,
}

impl Default for SpectralResponse {
    fn default() -> Self {
        Self {
            explicit: false,
            slit_index: SlitIndex::GaussianModulated,
            fwhm_nm: 0.0,
            amplitude: 0.0,
            scale: 1.0,
            phase_deg: 0.0,
            builtin_line_shape: BuiltinLineShapeKind::Gaussian,
            integration_mode: IntegrationMode::Auto,
            high_resolution_step_nm: 0.0,
            high_resolution_half_span_nm: 0.0,
            instrument_line_shape: InstrumentLineShape::default(),
            instrument_line_shape_table: InstrumentLineShapeTable::default(),
        }
    }
}

impl SpectralResponse {
    pub fn validate(&self) -> Result<()> {
        if self.fwhm_nm < 0.0 || !self.fwhm_nm.is_finite() {
            return Err(Error::InvalidRequest);
        }
        if !self.amplitude.is_finite()
            || !self.scale.is_finite()
            || self.scale <= 0.0
            || !self.phase_deg.is_finite()
        {
            return Err(Error::InvalidRequest);
        }
        if self.high_resolution_step_nm < 0.0 || self.high_resolution_half_span_nm < 0.0 {
            return Err(Error::InvalidRequest);
        }
        if (self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0) {
            return Err(Error::InvalidRequest);
        }
        self.instrument_line_shape.validate()?;
        self.instrument_line_shape_table.validate()?;
        if self.slit_index == SlitIndex::Table
            && self.instrument_line_shape_table.nominal_count == 0
            && self.instrument_line_shape.sample_count == 0
        {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct SimpleOffsets {
    pub multiplicative_percent: f64,
    pub additive_percent_of_first: f64,
}

impl SimpleOffsets {
    pub fn enabled(self) -> bool {
        self.multiplicative_percent != 0.0 || self.additive_percent_of_first != 0.0
    }

    pub fn validate(self) -> Result<()> {
        if !self.multiplicative_percent.is_finite() || !self.additive_percent_of_first.is_finite() {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct SinusoidalFeatures {
    pub additive_amplitude_percent: f64,
    pub additive_period_nm: f64,
    pub additive_phase_deg: f64,
    pub multiplicative_amplitude_percent: f64,
    pub multiplicative_period_nm: f64,
    pub multiplicative_phase_deg: f64,
}

impl SinusoidalFeatures {
    pub fn enabled(self) -> bool {
        self.additive_amplitude_percent != 0.0 || self.multiplicative_amplitude_percent != 0.0
    }

    pub fn validate(self) -> Result<()> {
        if !self.additive_amplitude_percent.is_finite()
            || !self.additive_period_nm.is_finite()
            || !self.additive_phase_deg.is_finite()
            || !self.multiplicative_amplitude_percent.is_finite()
            || !self.multiplicative_period_nm.is_finite()
            || !self.multiplicative_phase_deg.is_finite()
        {
            return Err(Error::InvalidRequest);
        }
        if self.additive_amplitude_percent != 0.0 && self.additive_period_nm <= 0.0 {
            return Err(Error::InvalidRequest);
        }
        if self.multiplicative_amplitude_percent != 0.0 && self.multiplicative_period_nm <= 0.0 {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct NoiseControls {
    pub explicit: bool,
    pub enabled: bool,
    pub model: NoiseModelKind,
    pub electrons_per_count: f64,
    pub reference_bin_width_nm: f64,
    pub snr_max: f64,
    pub lab_a: f64,
    pub lab_b: f64,
    pub snr_wavelengths_nm: Vec<f64>,
    pub snr_values: Vec<f64>,
    pub reference_signal: Vec<f64>,
    pub reference_sigma: Vec<f64>,
}

impl Default for NoiseControls {
    fn default() -> Self {
        Self {
            explicit: false,
            enabled: false,
            model: NoiseModelKind::None,
            electrons_per_count: 2.0,
            reference_bin_width_nm: 0.0,
            snr_max: f64::INFINITY,
            lab_a: 0.0,
            lab_b: 0.0,
            snr_wavelengths_nm: Vec::new(),
            snr_values: Vec::new(),
            reference_signal: Vec::new(),
            reference_sigma: Vec::new(),
        }
    }
}

impl NoiseControls {
    pub fn validate(&self) -> Result<()> {
        if !self.electrons_per_count.is_finite() || self.electrons_per_count <= 0.0 {
            return Err(Error::InvalidRequest);
        }
        if !self.reference_bin_width_nm.is_finite() || self.reference_bin_width_nm < 0.0 {
            return Err(Error::InvalidRequest);
        }
        if self.snr_max.is_nan() || self.snr_max <= 0.0 {
            return Err(Error::InvalidRequest);
        }
        if !self.lab_a.is_finite()
            || self.lab_a < 0.0
            || !self.lab_b.is_finite()
            || self.lab_b < 0.0
        {
            return Err(Error::InvalidRequest);
        }
        if self.enabled && self.model == NoiseModelKind::LabOperational && self.lab_a <= 0.0 {
            return Err(Error::InvalidRequest);
        }
        if self.snr_wavelengths_nm.len() != self.snr_values.len()
            || self.reference_signal.len() != self.reference_sigma.len()
        {
            return Err(Error::InvalidRequest);
        }

        let mut previous_wavelength = None;
        for (&wavelength_nm, &snr_value) in self.snr_wavelengths_nm.iter().zip(&self.snr_values) {
            if !wavelength_nm.is_finite() || !snr_value.is_finite() || snr_value <= 0.0 {
                return Err(Error::InvalidRequest);
            }
            if let Some(previous) = previous_wavelength
                && wavelength_nm <= previous
            {
                return Err(Error::InvalidRequest);
            }
            previous_wavelength = Some(wavelength_nm);
        }
        for (&signal, &sigma) in self.reference_signal.iter().zip(&self.reference_sigma) {
            if !signal.is_finite() || signal <= 0.0 || !sigma.is_finite() || sigma <= 0.0 {
                return Err(Error::InvalidRequest);
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct SpectralChannelControls {
    pub explicit: bool,
    pub response: SpectralResponse,
    pub wavelength_shift_nm: f64,
    pub multiplicative_offset: f64,
    pub additive_offset: f64,
    pub stray_light: f64,
    pub simple_offsets: SimpleOffsets,
    pub spectral_features: SinusoidalFeatures,
    pub smear_percent: f64,
    pub multiplicative_nodes: NodalCorrection,
    pub stray_light_nodes: NodalCorrection,
    pub noise: NoiseControls,
    pub use_polarization_scrambler: bool,
}

impl Default for SpectralChannelControls {
    fn default() -> Self {
        Self {
            explicit: false,
            response: SpectralResponse::default(),
            wavelength_shift_nm: 0.0,
            multiplicative_offset: 1.0,
            additive_offset: 0.0,
            stray_light: 0.0,
            simple_offsets: SimpleOffsets::default(),
            spectral_features: SinusoidalFeatures::default(),
            smear_percent: 0.0,
            multiplicative_nodes: NodalCorrection::default(),
            stray_light_nodes: NodalCorrection::default(),
            noise: NoiseControls::default(),
            use_polarization_scrambler: true,
        }
    }
}

impl SpectralChannelControls {
    pub fn validate(&self) -> Result<()> {
        if !self.wavelength_shift_nm.is_finite()
            || !self.multiplicative_offset.is_finite()
            || self.multiplicative_offset <= 0.0
            || !self.additive_offset.is_finite()
            || !self.stray_light.is_finite()
            || !self.smear_percent.is_finite()
        {
            return Err(Error::InvalidRequest);
        }
        self.response.validate()?;
        self.simple_offsets.validate()?;
        self.spectral_features.validate()?;
        self.multiplicative_nodes.validate()?;
        self.stray_light_nodes.validate()?;
        self.noise.validate()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RingControls {
    pub explicit: bool,
    pub enabled: bool,
    pub differential: bool,
    pub coefficient: f64,
    pub approximate_rrs: bool,
    pub fraction_raman_lines: f64,
    pub use_cabannes: bool,
    pub degree_poly: u32,
    pub include_absorption: bool,
    pub spectrum: Vec<f64>,
}

impl Default for RingControls {
    fn default() -> Self {
        Self {
            explicit: false,
            enabled: false,
            differential: false,
            coefficient: 0.0,
            approximate_rrs: false,
            fraction_raman_lines: 1.0,
            use_cabannes: false,
            degree_poly: 0,
            include_absorption: false,
            spectrum: Vec::new(),
        }
    }
}

impl RingControls {
    pub fn validate(&self) -> Result<()> {
        if !self.coefficient.is_finite()
            || !self.fraction_raman_lines.is_finite()
            || self.fraction_raman_lines < 0.0
            || self.degree_poly > 7
        {
            return Err(Error::InvalidRequest);
        }
        if self.spectrum.iter().any(|value| !value.is_finite()) {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ReflectanceCalibration {
    pub multiplicative_error: NodalCorrection,
    pub additive_error: NodalCorrection,
}

impl ReflectanceCalibration {
    pub fn validate(&self) -> Result<()> {
        self.multiplicative_error.validate()?;
        self.additive_error.validate()
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct MeasurementPipeline {
    pub radiance: SpectralChannelControls,
    pub irradiance: SpectralChannelControls,
    pub ring: RingControls,
    pub reflectance_calibration: ReflectanceCalibration,
}

impl MeasurementPipeline {
    pub fn validate(&self) -> Result<()> {
        self.radiance.validate()?;
        self.irradiance.validate()?;
        self.ring.validate()?;
        self.reflectance_calibration.validate()
    }
}
