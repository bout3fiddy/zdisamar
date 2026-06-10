const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");

// evaluation.zig ---------------------------------------------------------------------------------------------|
// Narrow handoff from prepared optical-property evaluation rows into the transport rows consumed by LABOS.    |
// The expensive work happens before this file: spectroscopy, Rayleigh, CIA, aerosols, phase mixtures, and     |
// geometry have already been evaluated into OpticalDepthBreakdown or EvaluatedLayer value rows. This file     |
// keeps the final component list and the RTM field mapping in one place so totals, diagnostics, and forward   |
// layer builders cannot quietly drift apart.                                                                  |
//                                                                                                             |
// called by                                                                                                   |
//   state_optical_depth.zig uses accumulateBreakdown when a wavelength-level scalar total walks prepared      |
//   layers. forward_layers.zig uses the same accumulator for shared-geometry, reduced-support, sublayer, and  |
//   ordinary layer routes, then uses layerInputFromEvaluated for rows that go directly into LABOS. Tests in   |
//   forward_layers_test.zig build expected LayerInput rows through this file instead of repeating the map.    |
//                                                                                                             |
// row handoff                                                                                                 |
//   OpticalDepthBreakdown stores the five prepared optical-depth components: gas absorption, gas scattering,  |
//   CIA, aerosol extinction, and aerosol scattering. EvaluatedLayer adds direction cosines and phase mixture  |
//   data for one physical layer or support interval. LayerInput is the public RTM row: it keeps the same      |
//   components, plus derived total extinction, total scattering, single-scatter albedo, Jacobian lanes, and   |
//   phase/direction fields.                                                                                   |
//                                                                                                             |
// ownership and hot path                                                                                      |
//   Everything here is a stack or caller-owned value row. No slices are allocated, borrowed, or released.     |
//   These helpers run inside per-wavelength layer loops, so the accumulator is deliberately just the shared   |
//   field list, and the LayerInput conversion only writes fixed-size values.                                  |
//                                                                                                             |
// Jacobian boundary                                                                                           |
//   This file initializes RTM Jacobian lanes to zero because the plain EvaluatedLayer row is a value result,  |
//   not a derivative carrier. forward_layers.zig attaches aerosol derivative lanes after conversion when the  |
//   selected derivative route requests them.                                                                  |
// ------------------------------------------------------------------------------------------------------------|

pub fn accumulateBreakdown(
    totals: *State.OpticalDepthBreakdown,
    breakdown: State.OpticalDepthBreakdown,
) void {
    // accumulateBreakdown ------------------------------------------------------------------------------------|
    // Add one prepared component row into a running wavelength or layer total.                                |
    //                                                                                                         |
    // boundary                                                                                                |
    //   Keep this as the single list of additive OpticalDepthBreakdown fields. Derived values such as total   |
    //   extinction and single-scatter albedo stay as methods on OpticalDepthBreakdown so callers do not add   |
    //   stale cached totals.                                                                                  |
    // --------------------------------------------------------------------------------------------------------|

    totals.gas_absorption_optical_depth += breakdown.gas_absorption_optical_depth;
    totals.gas_scattering_optical_depth += breakdown.gas_scattering_optical_depth;
    totals.cia_optical_depth += breakdown.cia_optical_depth;
    totals.aerosol_optical_depth += breakdown.aerosol_optical_depth;
    totals.aerosol_scattering_optical_depth += breakdown.aerosol_scattering_optical_depth;
}

pub fn layerInputFromEvaluated(evaluated: State.EvaluatedLayer) transport_common.LayerInput {
    // layerInputFromEvaluated --------------------------------------------------------------------------------|
    // Convert one prepared layer/support evaluation into the exact RTM row shape used by LABOS.               |
    //                                                                                                         |
    // field map                                                                                               |
    //   direct copies : five optical-depth components, direction cosines, and phase mixture                   |
    //   derived       : total extinction, total scattering, and single-scatter albedo                         |
    //   initialized   : Jacobian lanes start at zero; derivative routes patch them after this conversion      |
    //                                                                                                         |
    // math                                                                                                    |
    //   tau_ext = tau_abs_gas + tau_sca_gas + tau_cia + tau_aerosol                                           |
    //   tau_sca = tau_sca_gas + tau_sca_aerosol                                                               |
    //   omega0  = clamp(tau_sca / tau_ext, 0, 1)                                                              |
    // --------------------------------------------------------------------------------------------------------|

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
