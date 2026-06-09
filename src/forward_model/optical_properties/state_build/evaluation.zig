const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");

// evaluation.zig ---------------------------------------------------------------------------------------------|
// Small conversion helpers between prepared optical-state evaluations and RTM transport rows.                 |
//                                                                                                             |
// called by                                                                                                   |
//   state_optical_depth.zig builds EvaluatedLayer values from sublayer gas, Rayleigh, CIA, and aerosol terms  |
//   forward_layers.zig converts evaluated rows into radiative_transfer.LayerInput for LABOS                   |
//   diagnostics use the same breakdown accumulation when reporting layer or spectrum totals                   |
//                                                                                                             |
// main paths                                                                                                  |
//   accumulateBreakdown      adds one evaluated optical-depth component row into a running total              |
//   layerInputFromEvaluated copies an EvaluatedLayer into the public RTM LayerInput shape                     |
//                                                                                                             |
// boundary shape                                                                                              |
//   This file does not evaluate spectroscopy, aerosols, geometry, or phase functions. It only preserves the   |
//   field mapping from prepared optical-state names into the transport names consumed by LABOS.               |
//                                                                                                             |
// memory                                                                                                      |
//   Helpers return or mutate fixed-size values. Jacobian lanes are initialized to zero here; layer builders   |
//   attach aerosol derivative lanes later when a derivative route requests them.                              |
// ------------------------------------------------------------------------------------------------------------|

pub fn accumulateBreakdown(
    totals: *State.OpticalDepthBreakdown,
    breakdown: State.OpticalDepthBreakdown,
) void {
    totals.gas_absorption_optical_depth += breakdown.gas_absorption_optical_depth;
    totals.gas_scattering_optical_depth += breakdown.gas_scattering_optical_depth;
    totals.cia_optical_depth += breakdown.cia_optical_depth;
    totals.aerosol_optical_depth += breakdown.aerosol_optical_depth;
    totals.aerosol_scattering_optical_depth += breakdown.aerosol_scattering_optical_depth;
}

pub fn layerInputFromEvaluated(evaluated: State.EvaluatedLayer) transport_common.LayerInput {
    return .{
        .gas_absorption_optical_depth = evaluated.breakdown.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = evaluated.breakdown.gas_scattering_optical_depth,
        .cia_optical_depth = evaluated.breakdown.cia_optical_depth,
        .aerosol_optical_depth = evaluated.breakdown.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = evaluated.breakdown.aerosol_scattering_optical_depth,
        .optical_depth = evaluated.breakdown.totalOpticalDepth(),
        .scattering_optical_depth = evaluated.breakdown.totalScatteringOpticalDepth(),
        .single_scatter_albedo = evaluated.breakdown.singleScatterAlbedo(),
        .optical_depth_jacobian = .{0.0} ** transport_common.Jacobian.state_count,
        .scattering_optical_depth_jacobian = .{0.0} ** transport_common.Jacobian.state_count,
        .single_scatter_albedo_jacobian = .{0.0} ** transport_common.Jacobian.state_count,
        .solar_mu = evaluated.solar_mu,
        .view_mu = evaluated.view_mu,
        .phase = evaluated.phase,
    };
}
