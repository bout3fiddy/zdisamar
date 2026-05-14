use std::collections::HashMap;

use super::spectral_forward::ForwardIntegratedSample;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct SpectralEvaluationCache {
    pub forward: HashMap<u64, ForwardIntegratedSample>,
    pub irradiance: HashMap<u64, f64>,
}

impl SpectralEvaluationCache {
    pub fn reset(&mut self) {
        self.forward.clear();
        self.irradiance.clear();
    }

    pub fn key_for(wavelength_nm: f64) -> u64 {
        wavelength_nm.to_bits()
    }
}
