pub mod attenuation;
pub mod layers;
pub mod matrix;
pub mod phase_basis;
pub mod types;

pub use layers::{
    calc_rt_layers, calc_rt_layers_into, calc_rt_layers_into_with_basis,
    calc_rt_layers_tangent_into_with_basis, fill_layer_effective_scattering_suffixes,
    fill_layer_phase_max_indices, fill_surface, renormalize_zero_fourier_phase_kernel,
    zero_fourier_integral,
};
pub use phase_basis::{
    FourierPlmBasis, PhaseKernel, PhaseKernelRow, fill_zplus_zmin, fill_zplus_zmin_from_basis,
    fill_zplus_zmin_from_basis_limited, fill_zplus_zmin_row_from_basis_limited,
};
pub use types::{
    Geometry, LayerRt, MAX_EXTRA, MAX_GAUSS, MAX_N2, MAX_NMUTOT, MAX_PHASE_COEF, Mat, UdField,
    UdLocal, Vec, Vec2,
};
