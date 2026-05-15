use std::collections::HashMap;

use super::spectral_forward::ForwardIntegratedSample;

#[derive(Debug, Default, Clone)]
pub struct SpectralEvaluationCache {
    forward: HashMap<u64, ForwardIntegratedSample>,
    irradiance: HashMap<u64, f64>,
}

impl SpectralEvaluationCache {
    pub fn reset(&mut self) {
        self.forward.clear();
        self.irradiance.clear();
    }

    pub fn key_for(wavelength_nm: f64) -> u64 {
        wavelength_nm.to_bits()
    }

    pub fn forward_at(&self, wavelength_nm: f64) -> Option<ForwardIntegratedSample> {
        self.forward.get(&Self::key_for(wavelength_nm)).copied()
    }

    pub fn put_forward(&mut self, wavelength_nm: f64, sample: ForwardIntegratedSample) {
        self.forward.insert(Self::key_for(wavelength_nm), sample);
    }

    pub fn irradiance_at(&self, wavelength_nm: f64) -> Option<f64> {
        self.irradiance.get(&Self::key_for(wavelength_nm)).copied()
    }

    pub fn put_irradiance(&mut self, wavelength_nm: f64, irradiance: f64) {
        self.irradiance
            .insert(Self::key_for(wavelength_nm), irradiance);
    }

    pub fn forward_len(&self) -> usize {
        self.forward.len()
    }

    pub fn irradiance_len(&self) -> usize {
        self.irradiance.len()
    }
}
