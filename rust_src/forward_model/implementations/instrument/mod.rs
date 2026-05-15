pub mod adaptive_plan;
pub mod calibration;
pub mod implementation;
pub mod integration;
pub mod response;

pub use calibration::calibration_for_scene;
pub use implementation::{GENERIC_RESPONSE_ID, Implementation, resolve};
pub use integration::{
    DEFAULT_SLIT_KERNEL, Error, integration_for_wavelength_checked, slit_kernel_for_scene,
    uses_integrated_instrument_sampling,
};
pub use response::{default_kernel_half_span_nm, spectral_response_weight};
