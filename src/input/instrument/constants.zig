// constants.zig ----------------------------------------------------------------------------------------------|
// Shared instrument-size caps for line-shape and operational cross-section LUT code.                          |
//                                                                                                             |
// called by                                                                                                   |
//   Instrument.zig re-exports the caps for public input validation                                            |
//   instrument/line_shape.zig bounds explicit kernel and table storage                                        |
//   instrument/cross_section_lut.zig bounds Legendre basis arrays for operational LUT evaluation              |
//   instrument RTM code consumes the resulting bounded line-shape and LUT values during product simulation    |
//                                                                                                             |
// hot path                                                                                                    |
//   The operational LUT evaluator keeps Legendre basis arrays on the stack using these caps. Line-shape       |
//   preparation allocates fixed support arrays sized by max_line_shape_* so repeated convolution can reuse    |
//   bounded caller-owned slices.                                                                              |
//                                                                                                             |
// numbers                                                                                                     |
//   max_line_shape_samples leaves headroom for dense adaptive O2 A strong-line windows near 759.5 nm.         |
//   max_line_shape_nominals caps table kernels. The refspec coefficient caps bound temperature and pressure   |
//   polynomial work in operational LUT evaluation.                                                            |
//                                                                                                             |
// memory                                                                                                      |
//   Compile-time constants only; this file owns no storage.                                                   |
// ------------------------------------------------------------------------------------------------------------|

// The adaptive O2A routine can legitimately exceed 1024 quadrature samples in
// dense strong-line windows near 759.5 nm. Keep enough headroom so the preparation
// does not fall back to the coarse five-point routine in those cases.
pub const max_line_shape_samples: usize = 2048;
pub const max_line_shape_nominals: usize = 256;
pub const max_operational_refspec_temperature_coefficients: usize = 8;
pub const max_operational_refspec_pressure_coefficients: usize = 12;
