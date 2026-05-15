pub mod integration;
pub mod response;

pub use integration::{
    Error, integration_for_wavelength_checked, uses_integrated_instrument_sampling,
};
pub use response::{default_kernel_half_span_nm, spectral_response_weight};
