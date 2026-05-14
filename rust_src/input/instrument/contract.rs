use crate::common::errors::{Error, Result};

use super::{
    AdaptiveReferenceGrid, BuiltinLineShapeKind, Id, InstrumentLineShape, InstrumentLineShapeTable,
    NoiseModelKind, OperationalCrossSectionLut, OperationalReferenceGrid, OperationalSolarSpectrum,
    SamplingMode,
};

#[derive(Debug, Clone, PartialEq)]
pub struct OperationalBandSupport {
    pub id: String,
    pub high_resolution_step_nm: f64,
    pub high_resolution_half_span_nm: f64,
    pub instrument_line_shape: InstrumentLineShape,
    pub instrument_line_shape_table: InstrumentLineShapeTable,
    pub operational_refspec_grid: OperationalReferenceGrid,
    pub operational_solar_spectrum: OperationalSolarSpectrum,
    pub o2_operational_lut: OperationalCrossSectionLut,
    pub o2o2_operational_lut: OperationalCrossSectionLut,
}

impl Default for OperationalBandSupport {
    fn default() -> Self {
        Self {
            id: String::new(),
            high_resolution_step_nm: 0.0,
            high_resolution_half_span_nm: 0.0,
            instrument_line_shape: InstrumentLineShape::default(),
            instrument_line_shape_table: InstrumentLineShapeTable::default(),
            operational_refspec_grid: OperationalReferenceGrid::default(),
            operational_solar_spectrum: OperationalSolarSpectrum::default(),
            o2_operational_lut: OperationalCrossSectionLut::default(),
            o2o2_operational_lut: OperationalCrossSectionLut::default(),
        }
    }
}

impl OperationalBandSupport {
    pub fn enabled(&self) -> bool {
        self.high_resolution_step_nm > 0.0
            || self.high_resolution_half_span_nm > 0.0
            || self.instrument_line_shape.sample_count > 0
            || self.instrument_line_shape_table.nominal_count > 0
            || self.operational_refspec_grid.enabled()
            || self.operational_solar_spectrum.enabled()
            || self.o2_operational_lut.enabled()
            || self.o2o2_operational_lut.enabled()
    }

    pub fn validate(&self) -> Result<()> {
        if self.high_resolution_step_nm < 0.0 || self.high_resolution_half_span_nm < 0.0 {
            return Err(Error::InvalidRequest);
        }
        if (self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0) {
            return Err(Error::InvalidRequest);
        }
        if !self.enabled() {
            return Ok(());
        }
        if self.id.is_empty() {
            return Err(Error::InvalidRequest);
        }
        self.instrument_line_shape.validate()?;
        self.instrument_line_shape_table.validate()?;
        self.operational_refspec_grid.validate()?;
        self.operational_solar_spectrum.validate()?;
        self.o2_operational_lut.validate()?;
        self.o2o2_operational_lut.validate()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Instrument {
    pub id: Id,
    pub sampling: SamplingMode,
    pub noise_model: NoiseModelKind,
    pub wavelength_shift_nm: f64,
    pub instrument_line_fwhm_nm: f64,
    pub builtin_line_shape: BuiltinLineShapeKind,
    pub high_resolution_step_nm: f64,
    pub high_resolution_half_span_nm: f64,
    pub adaptive_reference_grid: AdaptiveReferenceGrid,
    pub instrument_line_shape: InstrumentLineShape,
    pub instrument_line_shape_table: InstrumentLineShapeTable,
    pub operational_refspec_grid: OperationalReferenceGrid,
    pub operational_solar_spectrum: OperationalSolarSpectrum,
    pub o2_operational_lut: OperationalCrossSectionLut,
    pub o2o2_operational_lut: OperationalCrossSectionLut,
}

impl Default for Instrument {
    fn default() -> Self {
        Self {
            id: Id::Generic,
            sampling: SamplingMode::Native,
            noise_model: NoiseModelKind::None,
            wavelength_shift_nm: 0.0,
            instrument_line_fwhm_nm: 0.0,
            builtin_line_shape: BuiltinLineShapeKind::Gaussian,
            high_resolution_step_nm: 0.0,
            high_resolution_half_span_nm: 0.0,
            adaptive_reference_grid: AdaptiveReferenceGrid::default(),
            instrument_line_shape: InstrumentLineShape::default(),
            instrument_line_shape_table: InstrumentLineShapeTable::default(),
            operational_refspec_grid: OperationalReferenceGrid::default(),
            operational_solar_spectrum: OperationalSolarSpectrum::default(),
            o2_operational_lut: OperationalCrossSectionLut::default(),
            o2o2_operational_lut: OperationalCrossSectionLut::default(),
        }
    }
}

impl Instrument {
    pub fn validate(&self) -> Result<()> {
        self.id.validate()?;
        if self.instrument_line_fwhm_nm < 0.0 {
            return Err(Error::InvalidRequest);
        }
        if self.high_resolution_step_nm < 0.0 || self.high_resolution_half_span_nm < 0.0 {
            return Err(Error::InvalidRequest);
        }
        if (self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0) {
            return Err(Error::InvalidRequest);
        }
        self.adaptive_reference_grid.validate()?;
        self.instrument_line_shape.validate()?;
        self.instrument_line_shape_table.validate()?;
        self.operational_refspec_grid.validate()?;
        self.operational_solar_spectrum.validate()?;
        self.o2_operational_lut.validate()?;
        self.o2o2_operational_lut.validate()
    }
}
