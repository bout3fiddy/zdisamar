pub mod line_list_eval;
pub mod physics_core;
pub mod strong_lines;

pub const HITRAN_REFERENCE_TEMPERATURE_K: f64 = 296.0;
pub const HITRAN_BOLTZMANN_CONSTANT_J_PER_K: f64 = 1.3806488e-23;
pub const HITRAN_BOLTZMANN_CONSTANT_CM3_HPA_PER_K: f64 = 1.380658e-19;
pub const HITRAN_HC_OVER_KB_CM_K: f64 = 1.4387770;
// DISAMAR uses this truncated literal inside HITRAN line-shape normalization.
#[allow(clippy::approx_constant)]
pub const HITRAN_PI: f64 = 3.1415926536;
pub const HITRAN_GAS_CONSTANT_J_PER_MOL_K: f64 = 8.3144621;
pub const HITRAN_SPEED_OF_LIGHT_M_PER_S: f64 = 2.99792458e8;
pub const MIN_SPECTROSCOPY_PRESSURE_ATM: f64 = 1.0e-12;
pub const VENDOR_CUTOFF_BOUNDARY_MARGIN_CM1: f64 = 0.115;
pub const VENDOR_CUTOFF_PREWINDOW_MARGIN_CM1: f64 = 0.25;
