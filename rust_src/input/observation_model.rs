use crate::{
    common::errors,
    input::{
        binding::Binding,
        instrument::{
            AdaptiveReferenceGrid, BuiltinLineShapeKind, Id, InstrumentLineShape,
            InstrumentLineShapeTable, MeasurementPipeline, NoiseModelKind, OperationalBandSupport,
            OperationalCrossSectionLut, OperationalReferenceGrid, OperationalSolarSpectrum,
            ReflectanceCalibration, RingControls, SamplingMode, SpectralChannel,
            SpectralChannelControls,
        },
        observation_legacy_support,
    },
};

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum ObservationRegime {
    #[default]
    Nadir,
    Limb,
    Occultation,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct CrossSectionFitControls {
    pub use_effective_cross_section_oe: bool,
    pub use_polynomial_expansion: bool,
    pub xsec_strong_absorption_bands: Vec<bool>,
    pub polynomial_degree_bands: Vec<u32>,
}

impl CrossSectionFitControls {
    pub fn validate(&self) -> Result<(), errors::Error> {
        if self
            .polynomial_degree_bands
            .iter()
            .any(|degree| *degree > 7)
        {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn validate_for_band_count(&self, band_count: usize) -> Result<(), errors::Error> {
        self.validate()?;
        if (!self.xsec_strong_absorption_bands.is_empty()
            && self.xsec_strong_absorption_bands.len() != band_count)
            || (!self.polynomial_degree_bands.is_empty()
                && self.polynomial_degree_bands.len() != band_count)
        {
            return Err(errors::Error::InvalidRequest);
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
    pub instrument: Id,
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
            instrument: Id::Generic,
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
            solar_spectrum_source: Binding::default(),
            weighted_reference_grid_source: Binding::default(),
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
    pub fn validate(&self) -> Result<(), errors::Error> {
        self.solar_spectrum_source.validate()?;
        self.weighted_reference_grid_source.validate()?;
        self.instrument.validate()?;
        if !self.multiplicative_offset.is_finite()
            || self.multiplicative_offset <= 0.0
            || !self.stray_light.is_finite()
        {
            return Err(errors::Error::InvalidRequest);
        }
        if self
            .ingested_noise_sigma
            .iter()
            .any(|value| !value.is_finite() || *value <= 0.0)
            || self
                .reference_radiance
                .iter()
                .any(|value| !value.is_finite() || *value < 0.0)
        {
            return Err(errors::Error::InvalidRequest);
        }

        match self.noise_model {
            NoiseModelKind::SnrFromInput | NoiseModelKind::S5pOperational => {
                // Input-driven noise has to arrive as an actual sigma vector so
                // later RTM and retrieval code can treat noise as materialized.
                if self.ingested_noise_sigma.is_empty() {
                    return Err(errors::Error::InvalidRequest);
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
                    return Err(errors::Error::InvalidRequest);
                }
                radiance_noise.validate()?;
                irradiance_noise.validate()?;
            }
            NoiseModelKind::None | NoiseModelKind::ShotNoise => {}
        }
        if self.noise_model == NoiseModelKind::S5pOperational
            && self.reference_radiance.len() != self.ingested_noise_sigma.len()
        {
            return Err(errors::Error::InvalidRequest);
        }

        if !self.measured_wavelengths_nm.is_empty() {
            let mut previous_wavelength = None;
            for &wavelength_nm in &self.measured_wavelengths_nm {
                if !wavelength_nm.is_finite() {
                    return Err(errors::Error::InvalidRequest);
                }
                if previous_wavelength.is_some_and(|previous| wavelength_nm <= previous) {
                    return Err(errors::Error::InvalidRequest);
                }
                previous_wavelength = Some(wavelength_nm);
            }
            if !self.ingested_noise_sigma.is_empty()
                && self.ingested_noise_sigma.len() != self.measured_wavelengths_nm.len()
            {
                return Err(errors::Error::InvalidRequest);
            }
        }

        if self.instrument_line_fwhm_nm < 0.0
            || self.high_resolution_step_nm < 0.0
            || self.high_resolution_half_span_nm < 0.0
            || ((self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0))
        {
            return Err(errors::Error::InvalidRequest);
        }
        self.adaptive_reference_grid.validate()?;
        self.instrument_line_shape.validate()?;
        self.instrument_line_shape_table.validate()?;
        self.operational_refspec_grid.validate()?;
        self.operational_solar_spectrum.validate()?;
        self.o2_operational_lut.validate()?;
        self.o2o2_operational_lut.validate()?;
        if self.operational_band_support.len() > 1 {
            // The current runtime resolves one operational support record per scene.
            // Reject multi-band replacement until the consumers are truly band-indexed.
            return Err(errors::Error::InvalidRequest);
        }
        for (index, support) in self.operational_band_support.iter().enumerate() {
            support.validate()?;
            for other in &self.operational_band_support[index + 1..] {
                if support.id == other.id {
                    return Err(errors::Error::InvalidRequest);
                }
            }
        }
        self.measurement_pipeline.validate()?;
        self.cross_section_fit.validate()
    }

    pub fn resolved_channel_controls(&self, channel: SpectralChannel) -> SpectralChannelControls {
        observation_legacy_support::resolved_channel_controls(self, channel)
    }

    pub fn resolved_ring_controls(&self) -> RingControls {
        self.measurement_pipeline.ring.clone()
    }

    pub fn operational_band_count(&self) -> usize {
        observation_legacy_support::operational_band_count(self)
    }

    pub fn primary_operational_band_support(&self) -> OperationalBandSupport {
        observation_legacy_support::primary_operational_band_support(self)
    }

    pub fn lut_sampling_half_span_nm(&self) -> f64 {
        observation_legacy_support::lut_sampling_half_span_nm(
            &self.primary_operational_band_support(),
        )
    }

    pub fn resolved_operational_band_support(
        &self,
        band_index: usize,
    ) -> Option<OperationalBandSupport> {
        observation_legacy_support::resolved_operational_band_support(self, band_index)
    }

    pub fn operational_replacement_labels(&self) -> Vec<String> {
        let band_count = self.operational_band_count();
        (0..band_count)
            .filter_map(|band_index| {
                self.resolved_operational_band_support(band_index)
                    .map(|support| support_replacement_label(&support, band_index))
            })
            .collect()
    }

    pub fn resolved_reflectance_calibration(&self) -> ReflectanceCalibration {
        self.measurement_pipeline.reflectance_calibration.clone()
    }
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
