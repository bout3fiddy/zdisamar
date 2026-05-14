use crate::common::errors::{Error, Result};

use super::{
    AdaptiveReferenceGrid, Binding, BuiltinLineShapeKind, InstrumentId, InstrumentLineShape,
    InstrumentLineShapeTable, IntegrationMode, MeasurementPipeline, NoiseModelKind,
    OperationalBandSupport, OperationalCrossSectionLut, OperationalReferenceGrid,
    OperationalSolarSpectrum, ReflectanceCalibration, SamplingMode, SlitIndex, SpectralChannel,
    SpectralChannelControls, SpectralResponse,
};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ObservationRegime {
    #[default]
    Nadir,
    Limb,
    Occultation,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct CrossSectionFitControls {
    pub use_effective_cross_section_oe: bool,
    pub use_polynomial_expansion: bool,
    pub xsec_strong_absorption_bands: Vec<bool>,
    pub polynomial_degree_bands: Vec<u32>,
}

impl CrossSectionFitControls {
    pub fn validate(&self) -> Result<()> {
        if self
            .polynomial_degree_bands
            .iter()
            .any(|degree| *degree > 7)
        {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn validate_for_band_count(&self, band_count: usize) -> Result<()> {
        self.validate()?;
        if !self.xsec_strong_absorption_bands.is_empty()
            && self.xsec_strong_absorption_bands.len() != band_count
        {
            return Err(Error::InvalidRequest);
        }
        if !self.polynomial_degree_bands.is_empty()
            && self.polynomial_degree_bands.len() != band_count
        {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn strong_absorption_for_band(&self, band_index: usize) -> bool {
        self.xsec_strong_absorption_bands
            .get(band_index)
            .copied()
            .unwrap_or(false)
    }

    pub fn polynomial_order_for_band(&self, band_index: usize) -> u32 {
        self.polynomial_degree_bands
            .get(band_index)
            .copied()
            .unwrap_or(0)
    }

    pub fn maximum_polynomial_order(&self) -> u32 {
        self.polynomial_degree_bands
            .iter()
            .copied()
            .max()
            .unwrap_or(0)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ObservationModel {
    pub instrument: InstrumentId,
    pub regime: ObservationRegime,
    pub sampling: SamplingMode,
    pub noise_model: NoiseModelKind,
    pub wavelength_shift_nm: f64,
    pub multiplicative_offset: f64,
    pub stray_light: f64,
    pub instrument_line_fwhm_nm: f64,
    pub builtin_line_shape: BuiltinLineShapeKind,
    pub high_resolution_step_nm: f64,
    pub high_resolution_half_span_nm: f64,
    pub adaptive_reference_grid: AdaptiveReferenceGrid,
    pub solar_spectrum_source: Binding,
    pub weighted_reference_grid_source: Binding,
    pub instrument_line_shape: InstrumentLineShape,
    pub instrument_line_shape_table: InstrumentLineShapeTable,
    pub operational_refspec_grid: OperationalReferenceGrid,
    pub operational_solar_spectrum: OperationalSolarSpectrum,
    pub o2_operational_lut: OperationalCrossSectionLut,
    pub o2o2_operational_lut: OperationalCrossSectionLut,
    pub operational_band_support: Vec<OperationalBandSupport>,
    pub measurement_pipeline: MeasurementPipeline,
    pub cross_section_fit: CrossSectionFitControls,
    pub measured_wavelengths_nm: Vec<f64>,
    pub reference_radiance: Vec<f64>,
    pub ingested_noise_sigma: Vec<f64>,
}

impl Default for ObservationModel {
    fn default() -> Self {
        Self {
            instrument: InstrumentId::Generic,
            regime: ObservationRegime::Nadir,
            sampling: SamplingMode::Native,
            noise_model: NoiseModelKind::None,
            wavelength_shift_nm: 0.0,
            multiplicative_offset: 1.0,
            stray_light: 0.0,
            instrument_line_fwhm_nm: 0.0,
            builtin_line_shape: BuiltinLineShapeKind::Gaussian,
            high_resolution_step_nm: 0.0,
            high_resolution_half_span_nm: 0.0,
            adaptive_reference_grid: AdaptiveReferenceGrid::default(),
            solar_spectrum_source: Binding::None,
            weighted_reference_grid_source: Binding::None,
            instrument_line_shape: InstrumentLineShape::default(),
            instrument_line_shape_table: InstrumentLineShapeTable::default(),
            operational_refspec_grid: OperationalReferenceGrid::default(),
            operational_solar_spectrum: OperationalSolarSpectrum::default(),
            o2_operational_lut: OperationalCrossSectionLut::default(),
            o2o2_operational_lut: OperationalCrossSectionLut::default(),
            operational_band_support: Vec::new(),
            measurement_pipeline: MeasurementPipeline::default(),
            cross_section_fit: CrossSectionFitControls::default(),
            measured_wavelengths_nm: Vec::new(),
            reference_radiance: Vec::new(),
            ingested_noise_sigma: Vec::new(),
        }
    }
}

impl ObservationModel {
    pub fn validate(&self) -> Result<()> {
        self.solar_spectrum_source.validate()?;
        self.weighted_reference_grid_source.validate()?;
        self.instrument.validate()?;
        if !self.multiplicative_offset.is_finite() || self.multiplicative_offset <= 0.0 {
            return Err(Error::InvalidRequest);
        }
        if !self.stray_light.is_finite() {
            return Err(Error::InvalidRequest);
        }
        for value in &self.ingested_noise_sigma {
            if !value.is_finite() || *value <= 0.0 {
                return Err(Error::InvalidRequest);
            }
        }
        for value in &self.reference_radiance {
            if !value.is_finite() || *value < 0.0 {
                return Err(Error::InvalidRequest);
            }
        }
        match self.noise_model {
            NoiseModelKind::SnrFromInput | NoiseModelKind::S5pOperational => {
                if self.ingested_noise_sigma.is_empty() {
                    return Err(Error::InvalidRequest);
                }
            }
            NoiseModelKind::LabOperational => {
                let radiance_noise = self
                    .resolved_channel_controls(SpectralChannel::Radiance)
                    .noise;
                let irradiance_noise = self
                    .resolved_channel_controls(SpectralChannel::Irradiance)
                    .noise;
                if radiance_noise.model != NoiseModelKind::LabOperational
                    || irradiance_noise.model != NoiseModelKind::LabOperational
                {
                    return Err(Error::InvalidRequest);
                }
                radiance_noise.validate()?;
                irradiance_noise.validate()?;
            }
            NoiseModelKind::None | NoiseModelKind::ShotNoise => {}
        }
        if self.noise_model == NoiseModelKind::S5pOperational
            && self.reference_radiance.len() != self.ingested_noise_sigma.len()
        {
            return Err(Error::InvalidRequest);
        }
        if !self.measured_wavelengths_nm.is_empty() {
            let mut previous_wavelength = None;
            for wavelength_nm in &self.measured_wavelengths_nm {
                if !wavelength_nm.is_finite() {
                    return Err(Error::InvalidRequest);
                }
                if let Some(previous) = previous_wavelength
                    && *wavelength_nm <= previous
                {
                    return Err(Error::InvalidRequest);
                }
                previous_wavelength = Some(*wavelength_nm);
            }
            if !self.ingested_noise_sigma.is_empty()
                && self.ingested_noise_sigma.len() != self.measured_wavelengths_nm.len()
            {
                return Err(Error::InvalidRequest);
            }
        }
        if self.instrument_line_fwhm_nm < 0.0 {
            return Err(Error::InvalidRequest);
        }
        if self.high_resolution_step_nm < 0.0 || self.high_resolution_half_span_nm < 0.0 {
            return Err(Error::InvalidRequest);
        }
        if (self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0) {
            // High-resolution sampling needs both step and span, otherwise the grid is underdefined.
            return Err(Error::InvalidRequest);
        }
        self.adaptive_reference_grid.validate()?;
        self.instrument_line_shape.validate()?;
        self.instrument_line_shape_table.validate()?;
        self.operational_refspec_grid.validate()?;
        self.operational_solar_spectrum.validate()?;
        self.o2_operational_lut.validate()?;
        self.o2o2_operational_lut.validate()?;
        if self.operational_band_support.len() > 1 {
            return Err(Error::InvalidRequest);
        }
        for (index, support) in self.operational_band_support.iter().enumerate() {
            support.validate()?;
            for other in &self.operational_band_support[index + 1..] {
                if support.id == other.id {
                    return Err(Error::InvalidRequest);
                }
            }
        }
        self.measurement_pipeline.validate()?;
        self.cross_section_fit.validate()
    }

    pub fn resolved_channel_controls(&self, channel: SpectralChannel) -> SpectralChannelControls {
        match channel {
            SpectralChannel::Radiance if self.measurement_pipeline.radiance.explicit => {
                self.measurement_pipeline.radiance.clone()
            }
            SpectralChannel::Irradiance if self.measurement_pipeline.irradiance.explicit => {
                self.measurement_pipeline.irradiance.clone()
            }
            _ => self.legacy_channel_controls(channel),
        }
    }

    pub fn resolved_ring_controls(&self) -> super::RingControls {
        self.measurement_pipeline.ring.clone()
    }

    pub fn operational_band_count(&self) -> usize {
        if !self.operational_band_support.is_empty() {
            return self.operational_band_support.len();
        }
        usize::from(self.legacy_operational_band_support().enabled())
    }

    pub fn primary_operational_band_support(&self) -> OperationalBandSupport {
        self.resolved_operational_band_support(0)
            .unwrap_or_default()
    }

    pub fn resolved_operational_band_support(
        &self,
        band_index: usize,
    ) -> Option<OperationalBandSupport> {
        if band_index < self.operational_band_support.len() {
            return Some(merge_operational_band_support(
                self.operational_band_support[band_index].clone(),
                self.legacy_operational_band_support(),
            ));
        }
        if band_index == 0 {
            let legacy = self.legacy_operational_band_support();
            if legacy.enabled() {
                return Some(legacy);
            }
        }
        None
    }

    pub fn lut_sampling_half_span_nm(&self) -> f64 {
        lut_sampling_half_span_nm(&self.primary_operational_band_support())
    }

    pub fn operational_replacement_labels(&self) -> Vec<String> {
        (0..self.operational_band_count())
            .filter_map(|band_index| {
                self.resolved_operational_band_support(band_index)
                    .map(|support| support_replacement_label(&support, band_index))
            })
            .collect()
    }

    pub fn resolved_reflectance_calibration(&self) -> ReflectanceCalibration {
        self.measurement_pipeline.reflectance_calibration.clone()
    }

    fn legacy_channel_controls(&self, channel: SpectralChannel) -> SpectralChannelControls {
        let mut controls = SpectralChannelControls {
            response: self.legacy_spectral_response(),
            wavelength_shift_nm: self.wavelength_shift_nm,
            noise: super::NoiseControls {
                enabled: legacy_noise_enabled(self.noise_model, channel),
                model: legacy_noise_model(self.noise_model, channel),
                reference_signal: if channel == SpectralChannel::Radiance {
                    self.reference_radiance.clone()
                } else {
                    Vec::new()
                },
                reference_sigma: if channel == SpectralChannel::Radiance {
                    self.ingested_noise_sigma.clone()
                } else {
                    Vec::new()
                },
                ..super::NoiseControls::default()
            },
            ..SpectralChannelControls::default()
        };
        if channel == SpectralChannel::Radiance {
            controls.multiplicative_offset = self.multiplicative_offset;
            controls.stray_light = self.stray_light;
            controls.use_polarization_scrambler = true;
        }
        controls
    }

    fn legacy_spectral_response(&self) -> SpectralResponse {
        let support = self.primary_operational_band_support();
        let resolved_high_resolution_step_nm = if support.high_resolution_step_nm > 0.0 {
            support.high_resolution_step_nm
        } else {
            self.high_resolution_step_nm
        };
        let resolved_high_resolution_half_span_nm = if support.high_resolution_half_span_nm > 0.0 {
            support.high_resolution_half_span_nm
        } else {
            self.high_resolution_half_span_nm
        };
        SpectralResponse {
            slit_index: match self.builtin_line_shape {
                BuiltinLineShapeKind::Gaussian => {
                    if support.instrument_line_shape_table.nominal_count > 0
                        || self.instrument_line_shape_table.nominal_count > 0
                    {
                        SlitIndex::Table
                    } else {
                        SlitIndex::GaussianModulated
                    }
                }
                BuiltinLineShapeKind::FlatTopN4 => SlitIndex::FlatTopN4,
                BuiltinLineShapeKind::TripleFlatTopN4 => SlitIndex::TripleFlatTopN4,
            },
            fwhm_nm: self.instrument_line_fwhm_nm,
            builtin_line_shape: self.builtin_line_shape,
            integration_mode: if self.adaptive_reference_grid.enabled() {
                IntegrationMode::Adaptive
            } else if resolved_high_resolution_step_nm > 0.0
                && resolved_high_resolution_half_span_nm > 0.0
            {
                IntegrationMode::ExplicitHrGrid
            } else {
                IntegrationMode::Auto
            },
            high_resolution_step_nm: resolved_high_resolution_step_nm,
            high_resolution_half_span_nm: resolved_high_resolution_half_span_nm,
            instrument_line_shape: if support.instrument_line_shape.sample_count > 0 {
                support.instrument_line_shape
            } else {
                self.instrument_line_shape.clone()
            },
            instrument_line_shape_table: if support.instrument_line_shape_table.nominal_count > 0 {
                support.instrument_line_shape_table
            } else {
                self.instrument_line_shape_table.clone()
            },
            ..SpectralResponse::default()
        }
    }

    fn legacy_operational_band_support(&self) -> OperationalBandSupport {
        OperationalBandSupport {
            id: if self.instrument != InstrumentId::Unset {
                "primary".to_string()
            } else {
                String::new()
            },
            high_resolution_step_nm: self.high_resolution_step_nm,
            high_resolution_half_span_nm: self.high_resolution_half_span_nm,
            instrument_line_shape: self.instrument_line_shape.clone(),
            instrument_line_shape_table: self.instrument_line_shape_table.clone(),
            operational_refspec_grid: self.operational_refspec_grid.clone(),
            operational_solar_spectrum: self.operational_solar_spectrum.clone(),
            o2_operational_lut: self.o2_operational_lut.clone(),
            o2o2_operational_lut: self.o2o2_operational_lut.clone(),
        }
    }
}

fn merge_operational_band_support(
    explicit: OperationalBandSupport,
    mut legacy: OperationalBandSupport,
) -> OperationalBandSupport {
    if !explicit.id.is_empty() {
        legacy.id = explicit.id;
    }
    if explicit.high_resolution_step_nm > 0.0 {
        legacy.high_resolution_step_nm = explicit.high_resolution_step_nm;
        legacy.high_resolution_half_span_nm = explicit.high_resolution_half_span_nm;
    }
    if explicit.instrument_line_shape.sample_count > 0 {
        legacy.instrument_line_shape = explicit.instrument_line_shape;
    }
    if explicit.instrument_line_shape_table.nominal_count > 0 {
        legacy.instrument_line_shape_table = explicit.instrument_line_shape_table;
    }
    if explicit.operational_refspec_grid.enabled() {
        legacy.operational_refspec_grid = explicit.operational_refspec_grid;
    }
    if explicit.operational_solar_spectrum.enabled() {
        legacy.operational_solar_spectrum = explicit.operational_solar_spectrum;
    }
    if explicit.o2_operational_lut.enabled() {
        legacy.o2_operational_lut = explicit.o2_operational_lut;
    }
    if explicit.o2o2_operational_lut.enabled() {
        legacy.o2o2_operational_lut = explicit.o2o2_operational_lut;
    }
    legacy
}

fn lut_sampling_half_span_nm(support: &OperationalBandSupport) -> f64 {
    if support.high_resolution_step_nm <= 0.0 {
        return 0.0;
    }
    let mut half_span_nm = support.high_resolution_half_span_nm;
    if support.instrument_line_shape.sample_count > 0 {
        for offset_nm in &support.instrument_line_shape.offsets_nm
            [..usize::from(support.instrument_line_shape.sample_count)]
        {
            half_span_nm = half_span_nm.max(offset_nm.abs());
        }
    }
    if support.instrument_line_shape_table.sample_count > 0 {
        for offset_nm in &support.instrument_line_shape_table.offsets_nm
            [..usize::from(support.instrument_line_shape_table.sample_count)]
        {
            half_span_nm = half_span_nm.max(offset_nm.abs());
        }
    }
    half_span_nm
}

fn support_replacement_label(support: &OperationalBandSupport, band_index: usize) -> String {
    let mut label = if support.id.is_empty() {
        format!("band-{band_index}:")
    } else {
        format!("{}:", support.id)
    };
    if support.high_resolution_step_nm > 0.0 {
        label.push_str("hr_grid,");
    }
    if support.instrument_line_shape.sample_count > 0
        || support.instrument_line_shape_table.nominal_count > 0
    {
        label.push_str("isrf,");
    }
    if support.operational_refspec_grid.enabled() {
        label.push_str("refspec,");
    }
    if support.operational_solar_spectrum.enabled() {
        label.push_str("solar,");
    }
    if support.o2_operational_lut.enabled() {
        label.push_str("o2_lut,");
    }
    if support.o2o2_operational_lut.enabled() {
        label.push_str("o2o2_lut,");
    }
    if label.ends_with(',') {
        label.pop();
    }
    label
}

fn legacy_noise_enabled(model: NoiseModelKind, channel: SpectralChannel) -> bool {
    match channel {
        SpectralChannel::Radiance => model != NoiseModelKind::None,
        SpectralChannel::Irradiance => matches!(
            model,
            NoiseModelKind::ShotNoise | NoiseModelKind::LabOperational
        ),
    }
}

fn legacy_noise_model(model: NoiseModelKind, channel: SpectralChannel) -> NoiseModelKind {
    if channel == SpectralChannel::Radiance {
        return model;
    }
    match model {
        NoiseModelKind::ShotNoise | NoiseModelKind::LabOperational => model,
        NoiseModelKind::None | NoiseModelKind::S5pOperational | NoiseModelKind::SnrFromInput => {
            NoiseModelKind::None
        }
    }
}
