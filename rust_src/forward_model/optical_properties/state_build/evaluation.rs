use super::state_types::{EvaluatedLayer, OpticalDepthBreakdown};
use crate::forward_model::{jacobian, radiative_transfer::common_types::LayerInput};

pub fn accumulate_breakdown(totals: &mut OpticalDepthBreakdown, breakdown: OpticalDepthBreakdown) {
    totals.gas_absorption_optical_depth += breakdown.gas_absorption_optical_depth;
    totals.gas_scattering_optical_depth += breakdown.gas_scattering_optical_depth;
    totals.cia_optical_depth += breakdown.cia_optical_depth;
    totals.aerosol_optical_depth += breakdown.aerosol_optical_depth;
    totals.aerosol_scattering_optical_depth += breakdown.aerosol_scattering_optical_depth;
    totals.cloud_optical_depth += breakdown.cloud_optical_depth;
    totals.cloud_scattering_optical_depth += breakdown.cloud_scattering_optical_depth;
}

pub fn layer_input_from_evaluated(evaluated: EvaluatedLayer) -> LayerInput {
    LayerInput {
        gas_absorption_optical_depth: evaluated.breakdown.gas_absorption_optical_depth,
        gas_scattering_optical_depth: evaluated.breakdown.gas_scattering_optical_depth,
        cia_optical_depth: evaluated.breakdown.cia_optical_depth,
        aerosol_optical_depth: evaluated.breakdown.aerosol_optical_depth,
        aerosol_scattering_optical_depth: evaluated.breakdown.aerosol_scattering_optical_depth,
        cloud_optical_depth: evaluated.breakdown.cloud_optical_depth,
        cloud_scattering_optical_depth: evaluated.breakdown.cloud_scattering_optical_depth,
        optical_depth: evaluated.breakdown.total_optical_depth(),
        scattering_optical_depth: evaluated.breakdown.total_scattering_optical_depth(),
        single_scatter_albedo: evaluated.breakdown.single_scatter_albedo(),
        optical_depth_jacobian: jacobian::zero(),
        scattering_optical_depth_jacobian: jacobian::zero(),
        single_scatter_albedo_jacobian: jacobian::zero(),
        solar_mu: evaluated.solar_mu,
        view_mu: evaluated.view_mu,
        phase_coefficients: evaluated.phase_coefficients,
    }
}
