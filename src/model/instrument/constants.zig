// The adaptive O2A routine can legitimately exceed 1024 quadrature samples in
// dense strong-line windows near 759.5 nm. Keep enough headroom so the preparation
// does not fall back to the coarse five-point routine in those cases.
pub const max_line_shape_samples: usize = 2048;
pub const max_line_shape_nominals: usize = 256;
pub const max_operational_refspec_temperature_coefficients: usize = 8;
pub const max_operational_refspec_pressure_coefficients: usize = 12;
