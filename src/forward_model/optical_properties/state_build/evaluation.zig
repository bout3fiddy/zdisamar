const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");

pub fn accumulateBreakdown(
    totals: *State.OpticalDepthBreakdown,
    breakdown: State.OpticalDepthBreakdown,
) void {
    totals.gas_absorption_optical_depth += breakdown.gas_absorption_optical_depth;
    totals.gas_scattering_optical_depth += breakdown.gas_scattering_optical_depth;
    totals.cia_optical_depth += breakdown.cia_optical_depth;
    totals.aerosol_optical_depth += breakdown.aerosol_optical_depth;
    totals.aerosol_scattering_optical_depth += breakdown.aerosol_scattering_optical_depth;
    totals.cloud_optical_depth += breakdown.cloud_optical_depth;
    totals.cloud_scattering_optical_depth += breakdown.cloud_scattering_optical_depth;
}

pub fn layerInputFromEvaluated(evaluated: State.EvaluatedLayer) transport_common.LayerInput {
    return .{
        .gas_absorption_optical_depth = evaluated.breakdown.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = evaluated.breakdown.gas_scattering_optical_depth,
        .cia_optical_depth = evaluated.breakdown.cia_optical_depth,
        .aerosol_optical_depth = evaluated.breakdown.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = evaluated.breakdown.aerosol_scattering_optical_depth,
        .cloud_optical_depth = evaluated.breakdown.cloud_optical_depth,
        .cloud_scattering_optical_depth = evaluated.breakdown.cloud_scattering_optical_depth,
        .optical_depth = evaluated.breakdown.totalOpticalDepth(),
        .scattering_optical_depth = evaluated.breakdown.totalScatteringOpticalDepth(),
        .single_scatter_albedo = evaluated.breakdown.singleScatterAlbedo(),
        .solar_mu = evaluated.solar_mu,
        .view_mu = evaluated.view_mu,
        .phase_coefficients = evaluated.phase_coefficients,
    };
}
