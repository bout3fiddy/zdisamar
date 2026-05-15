use super::{
    Error, calibration::calibration_for_scene, integration_for_wavelength_checked,
    slit_kernel_for_scene, uses_integrated_instrument_sampling,
};
use crate::{
    forward_model::instrument_grid::{
        grid_calculation::spectral_eval::IntegrationKernel, spectral_math::calibration::Calibration,
    },
    input::{instrument::SpectralChannel, scene::Scene},
};

pub const GENERIC_RESPONSE_ID: &str = "builtin.generic_response";

#[derive(Debug, Clone, Copy)]
pub struct Implementation {
    pub id: &'static str,
    pub calibration_for_scene: fn(&Scene, SpectralChannel) -> Calibration,
    pub uses_integrated_sampling: fn(&Scene, SpectralChannel) -> bool,
    pub integration_for_wavelength:
        fn(&Scene, SpectralChannel, f64) -> Result<IntegrationKernel, Error>,
    pub slit_kernel_for_scene: fn(&Scene, SpectralChannel) -> [f64; 5],
}

pub fn resolve(provider_id: &str) -> Option<Implementation> {
    if provider_id == GENERIC_RESPONSE_ID {
        return Some(generic_provider());
    }
    None
}

fn generic_provider() -> Implementation {
    Implementation {
        id: GENERIC_RESPONSE_ID,
        calibration_for_scene,
        uses_integrated_sampling: uses_integrated_instrument_sampling,
        integration_for_wavelength: integration_for_wavelength_checked,
        slit_kernel_for_scene,
    }
}
