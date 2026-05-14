use crate::common::errors::{Error, Result};

use super::constants::{MAX_LINE_SHAPE_NOMINALS, MAX_LINE_SHAPE_SAMPLES};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum BuiltinLineShapeKind {
    #[default]
    Gaussian,
    FlatTopN4,
    TripleFlatTopN4,
}

impl BuiltinLineShapeKind {
    pub fn parse(name: &str) -> Result<Self> {
        match name {
            "" | "gaussian" | "table" => Ok(Self::Gaussian),
            "flat_top" | "flat_top_n4" | "flat_topped" | "vendor_flat_top" => Ok(Self::FlatTopN4),
            "triple_flat_top" | "triple_flat_top_n4" => Ok(Self::TripleFlatTopN4),
            _ => Err(Error::InvalidRequest),
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct InstrumentLineShape {
    pub sample_count: u8,
    pub offsets_nm: Vec<f64>,
    pub weights: Vec<f64>,
}

impl InstrumentLineShape {
    pub fn validate(&self) -> Result<()> {
        if usize::from(self.sample_count) > MAX_LINE_SHAPE_SAMPLES {
            return Err(Error::InvalidRequest);
        }
        if self.sample_count == 0 {
            return Ok(());
        }
        let sample_count = usize::from(self.sample_count);
        if self.offsets_nm.len() < sample_count || self.weights.len() < sample_count {
            return Err(Error::InvalidRequest);
        }

        let mut weight_sum = 0.0;
        for weight in &self.weights[..sample_count] {
            if *weight < 0.0 {
                return Err(Error::InvalidRequest);
            }
            weight_sum += *weight;
        }
        if !weight_sum.is_finite() || weight_sum <= 0.0 {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn write_normalized_kernel(
        &self,
        offsets_out: &mut [f64],
        weights_out: &mut [f64],
    ) -> usize {
        let sample_count = usize::from(self.sample_count)
            .min(offsets_out.len())
            .min(weights_out.len());
        if sample_count == 0 {
            return 0;
        }

        let mut weight_sum = 0.0;
        for index in 0..sample_count {
            offsets_out[index] = self.offsets_nm[index];
            weights_out[index] = self.weights[index];
            weight_sum += weights_out[index];
        }
        if !weight_sum.is_finite() || weight_sum <= 0.0 {
            return 0;
        }
        for weight in &mut weights_out[..sample_count] {
            *weight /= weight_sum;
        }
        sample_count
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct InstrumentLineShapeTable {
    pub nominal_count: u16,
    pub sample_count: u8,
    pub nominal_wavelengths_nm: Vec<f64>,
    pub offsets_nm: Vec<f64>,
    pub weights: Vec<f64>,
}

impl InstrumentLineShapeTable {
    pub fn validate(&self) -> Result<()> {
        if usize::from(self.nominal_count) > MAX_LINE_SHAPE_NOMINALS
            || usize::from(self.sample_count) > MAX_LINE_SHAPE_SAMPLES
        {
            return Err(Error::InvalidRequest);
        }
        if self.nominal_count == 0 && self.sample_count == 0 {
            return Ok(());
        }
        if self.nominal_count == 0 || self.sample_count == 0 {
            return Err(Error::InvalidRequest);
        }
        let nominal_count = usize::from(self.nominal_count);
        let sample_count = usize::from(self.sample_count);
        if self.nominal_wavelengths_nm.len() < nominal_count
            || self.offsets_nm.len() < sample_count
            || self.weights.len() < nominal_count * sample_count
        {
            return Err(Error::InvalidRequest);
        }

        let mut previous_nominal = None;
        for nominal_index in 0..nominal_count {
            let nominal = self.nominal_wavelengths_nm[nominal_index];
            if !nominal.is_finite() {
                return Err(Error::InvalidRequest);
            }
            if let Some(previous) = previous_nominal
                && nominal < previous
            {
                return Err(Error::InvalidRequest);
            }
            previous_nominal = Some(nominal);

            let mut row_sum = 0.0;
            for sample_index in 0..sample_count {
                let weight = self.weight_at(nominal_index, sample_index);
                if weight < 0.0 || !weight.is_finite() {
                    return Err(Error::InvalidRequest);
                }
                row_sum += weight;
            }
            if row_sum <= 0.0 || !row_sum.is_finite() {
                return Err(Error::InvalidRequest);
            }
        }
        Ok(())
    }

    pub fn weight_at(&self, nominal_index: usize, sample_index: usize) -> f64 {
        self.weights[nominal_index * usize::from(self.sample_count) + sample_index]
    }

    pub fn set_weight(&mut self, nominal_index: usize, sample_index: usize, value: f64) {
        let offset = nominal_index * usize::from(self.sample_count) + sample_index;
        self.weights[offset] = value;
    }

    pub fn nearest_nominal_index(&self, wavelength_nm: f64) -> Option<usize> {
        if self.nominal_count == 0 {
            return None;
        }
        let mut best_index = 0;
        let mut best_delta = f64::INFINITY;
        for index in 0..usize::from(self.nominal_count) {
            let delta = (self.nominal_wavelengths_nm[index] - wavelength_nm).abs();
            if delta < best_delta {
                best_delta = delta;
                best_index = index;
            }
        }
        Some(best_index)
    }

    pub fn write_normalized_kernel_for_nominal(
        &self,
        nominal_wavelength_nm: f64,
        offsets_out: &mut [f64],
        weights_out: &mut [f64],
    ) -> usize {
        let Some(nominal_index) = self.nearest_nominal_index(nominal_wavelength_nm) else {
            return 0;
        };
        let sample_count = usize::from(self.sample_count)
            .min(offsets_out.len())
            .min(weights_out.len());
        if sample_count == 0 {
            return 0;
        }

        let mut weight_sum = 0.0;
        for index in 0..sample_count {
            offsets_out[index] = self.offsets_nm[index];
            weights_out[index] = self.weight_at(nominal_index, index);
            weight_sum += weights_out[index];
        }
        if !weight_sum.is_finite() || weight_sum <= 0.0 {
            return 0;
        }
        for weight in &mut weights_out[..sample_count] {
            *weight /= weight_sum;
        }
        sample_count
    }
}
