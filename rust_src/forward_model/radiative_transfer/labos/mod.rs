pub mod attenuation;
pub mod layers;
pub mod matrix;
pub mod orders;
pub mod phase_basis;
pub mod types;

pub use attenuation::{AttenArray, DynamicAttenArray};
pub use layers::{
    calc_rt_layers, calc_rt_layers_into, calc_rt_layers_into_with_basis,
    calc_rt_layers_tangent_into_with_basis, fill_layer_effective_scattering_suffixes,
    fill_layer_phase_max_indices, fill_surface, renormalize_zero_fourier_phase_kernel,
    zero_fourier_integral,
};
pub use orders::{
    AttenuationAccess, DotPair, OrdersResult, OrdersResultView, OrdersWorkspace,
    accumulate_order_contribution, copy_transported_order_into_output, dot_gauss, dot_gauss_pair,
    initialize_orders_buffers, max_outgoing_upward, refresh_active_layer_mask, rt_layer_has_signal,
    transport_to_other_levels, zero_orders_result, zero_ud_field, zero_ud_local,
};
pub use phase_basis::{
    FourierPlmBasis, PhaseKernel, PhaseKernelRow, fill_zplus_zmin, fill_zplus_zmin_from_basis,
    fill_zplus_zmin_from_basis_limited, fill_zplus_zmin_row_from_basis_limited,
};
pub use types::{
    Geometry, LayerRt, MAX_EXTRA, MAX_GAUSS, MAX_N2, MAX_NMUTOT, MAX_PHASE_COEF, Mat, UdField,
    UdLocal, Vec, Vec2,
};
