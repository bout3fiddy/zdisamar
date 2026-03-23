//! Purpose:
//!   Hold fixed size limits for instrument line-shape and reference-spectrum tables.
//!
//! Physics:
//!   Constrains the number of nominal samples and polynomial coefficients supported by the compact instrument models.
//!
//! Vendor:
//!   `instrument constants`
//!
//! Design:
//!   These caps keep the owned buffers and table shapes bounded and easy to validate.
//!
//! Invariants:
//!   The limits are compile-time constants and must remain large enough for the shipped instrument tables.

pub const max_line_shape_samples: usize = 257;
pub const max_line_shape_nominals: usize = 256;
pub const max_operational_refspec_temperature_coefficients: usize = 8;
pub const max_operational_refspec_pressure_coefficients: usize = 12;
