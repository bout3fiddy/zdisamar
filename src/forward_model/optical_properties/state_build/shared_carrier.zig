const Scene = @import("../../../input/Scene.zig").Scene;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");
const carrier_eval = @import("carrier_eval.zig");
const shared_geometry = @import("shared_geometry.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");

const PreparedOpticalState = State.PreparedOpticalState;
const PreparedSublayer = State.PreparedSublayer;
const OpticalDepthBreakdown = State.OpticalDepthBreakdown;
const EvaluatedLayer = State.EvaluatedLayer;
const SharedRtmLayerGeometry = State.SharedRtmLayerGeometry;

const phase_coefficient_count = PhaseFunctions.phase_coefficient_count;

// shared_carrier.zig --------------------------------------------------------------------------------------- |
// Reduces prepared support rows into the optical carriers consumed by the shared-RTM route.                  |
// This is the wavelength-time companion to shared_geometry.zig: geometry says which support rows belong to   |
// each transport layer or level, and this file evaluates gas, CIA, aerosol, scattering, phase, and direct    |
// attenuation on those rows.                                                                                 |
//                                                                                                            |
// called by                                                                                                  |
//   forward_layers.zig fills radiative_transfer.LayerInput rows for LABOS.                                   |
//   rtm_quadrature.zig samples level carriers for integrated-source terms.                                   |
//   source_interfaces.zig fills boundary source-interface rows.                                              |
//   pseudo_spherical.zig writes direct-beam attenuation samples.                                             |
//                                                                                                            |
// carrier routes                                                                                             |
//   reduced support rows : use existing PreparedSublayer rows and their path_length_cm weights. Boundary     |
//                          support rows define layer edges, so the active reduction skips first/last rows.   |
//   Gauss subgrid        : build temporary altitude/weight rows for RTM quadrature and evaluate carriers     |
//                          on those quadrature rows.                                                         |
//   carrier cache        : reuse WavelengthCarrierCache scalar rows when the caller has already evaluated    |
//                          this wavelength across support rows.                                              |
//                                                                                                            |
// output rows                                                                                                |
//   EvaluatedLayer             : diagnostics and layer-level optical-depth summaries.                        |
//   LayerInput                 : transport input row passed to LABOS.                                        |
//   PseudoSphericalSample      : direct-beam attenuation sample for pseudo-spherical paths.                  |
//                                                                                                            |
// hot path                                                                                                   |
//   Runs inside wavelength and shared-support loops. Strong-line state lookup is centralized behind one      |
//   bounded optional-slice check used by each carrier loop.                                                  |
//   Pointer/slice views keep 256 B PreparedSublayer rows in PreparedOpticalState-owned storage.              |
//                                                                                                            |
// memory                                                                                                     |
//   SharedRtmSubgrid borrows GaussRuleScratch storage; prepared sublayers and strong-line states stay owned  |
//   by PreparedOpticalState. This file writes caller-owned output rows and allocates nothing.                |
// ---------------------------------------------------------------------------------------------------------- |

// SharedRtmSubgrid ----------------------------------------------------------------------------------------- |
// Borrowed altitude and weight rows for one shared RTM subgrid.                                              |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 32 B (0.031 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0..15] altitudes_km : []const f64                                                                        |
// [16..31] weights_km   : []const f64                                                                        |
//                                                                                                            |
// footprint: per instance = 32 B; rows borrow GaussRuleScratch storage                                       |
// ---------------------------------------------------------------------------------------------------------- |
pub const SharedRtmSubgrid = struct {
    altitudes_km: []const f64 = &.{},
    weights_km: []const f64 = &.{},
};

pub fn sharedRtmSubgridSampleCount(scene: *const Scene) usize {
    return @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

pub fn resolveSharedRtmSubgrid(
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    sample_count: usize,
    scratch: *shared_geometry.GaussRuleScratch,
) SharedRtmSubgrid {
    // resolveSharedRtmSubgrid ------------------------------------------------------------------------------ |
    // Map one layer altitude interval onto borrowed quadrature altitude/weight rows.                         |
    //                                                                                                        |
    // math                                                                                                   |
    //   z_i  = z_low + 0.5 * (x_i + 1) * (z_high - z_low)                                                    |
    //   dz_i = 0.5 * w_i * (z_high - z_low)                                                                  |
    //                                                                                                        |
    // memory                                                                                                 |
    //   scratch owns the temporary node/weight arrays; the returned slices borrow the active prefix.         |
    // ------------------------------------------------------------------------------------------------------ |

    if (sample_count == 0) return .{};

    if (sample_count == 1) {

        // math: one-point quadrature collapses to midpoint altitude and full interval thickness.
        scratch.nodes[0] = 0.5 * (lower_altitude_km + upper_altitude_km);
        scratch.weights[0] = @max(upper_altitude_km - lower_altitude_km, 0.0);
        return .{
            .altitudes_km = scratch.nodes[0..1],
            .weights_km = scratch.weights[0..1],
        };
    }

    const rule = shared_geometry.resolveGaussRule(sample_count, scratch);
    for (0..sample_count) |node_index| {
        const node = rule.nodes[node_index];
        const weight = rule.weights[node_index];
        scratch.nodes[node_index] = shared_geometry.intervalAltitudeAtNode(
            lower_altitude_km,
            upper_altitude_km,
            node,
        );
        scratch.weights[node_index] = shared_geometry.intervalWeightKm(
            lower_altitude_km,
            upper_altitude_km,
            weight,
        );
    }
    return .{
        .altitudes_km = scratch.nodes[0..sample_count],
        .weights_km = scratch.weights[0..sample_count],
    };
}

pub fn accumulateSharedCarrier(
    breakdown: *OpticalDepthBreakdown,
    carrier: *const carrier_eval.SharedOpticalCarrier,
    weight_km: f64,
) void {
    // accumulateSharedCarrier ------------------------------------------------------------------------------ |
    // Add one per-km carrier sample into a layer optical-depth breakdown.                                    |
    //                                                                                                        |
    // math                                                                                                   |
    //   tau_component += k_component(lambda, z_i) * weight_km_i                                              |
    // ------------------------------------------------------------------------------------------------------ |

    // math: layer tau contribution = per-km optical-depth carrier * quadrature/support weight_km.
    const weighted_gas_absorption = carrier.gas_absorption_optical_depth_per_km * weight_km;
    const weighted_gas_scattering = carrier.gas_scattering_optical_depth_per_km * weight_km;
    const weighted_cia = carrier.cia_optical_depth_per_km * weight_km;
    const weighted_aerosol = carrier.aerosol_optical_depth_per_km * weight_km;
    const weighted_aerosol_scattering = carrier.aerosol_scattering_optical_depth_per_km * weight_km;

    breakdown.gas_absorption_optical_depth += weighted_gas_absorption;
    breakdown.gas_scattering_optical_depth += weighted_gas_scattering;
    breakdown.cia_optical_depth += weighted_cia;
    breakdown.aerosol_optical_depth += weighted_aerosol;
    breakdown.aerosol_scattering_optical_depth += weighted_aerosol_scattering;
}

fn accumulateSharedScalars(
    breakdown: *OpticalDepthBreakdown,
    scalars: *const carrier_eval.SharedOpticalScalars,
    weight_km: f64,
) void {
    const weighted_gas_absorption = scalars.gas_absorption_optical_depth_per_km * weight_km;
    const weighted_gas_scattering = scalars.gas_scattering_optical_depth_per_km * weight_km;
    const weighted_cia = scalars.cia_optical_depth_per_km * weight_km;
    const weighted_aerosol = scalars.aerosol_optical_depth_per_km * weight_km;
    const weighted_aerosol_scattering = scalars.aerosol_scattering_optical_depth_per_km * weight_km;

    breakdown.gas_absorption_optical_depth += weighted_gas_absorption;
    breakdown.gas_scattering_optical_depth += weighted_gas_scattering;
    breakdown.cia_optical_depth += weighted_cia;
    breakdown.aerosol_optical_depth += weighted_aerosol;
    breakdown.aerosol_scattering_optical_depth += weighted_aerosol_scattering;
}

pub fn evaluatedLayerFromSharedCarrier(
    scene: *const Scene,
    wavelength_nm: f64,
    altitude_km: f64,
    breakdown: OpticalDepthBreakdown,
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64,
) EvaluatedLayer {
    return .{
        .breakdown = breakdown,
        .phase = PhaseFunctions.PhaseMixture.fromScatteringMix(
            PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm),
            breakdown.gas_scattering_optical_depth,
            breakdown.aerosol_scattering_optical_depth,
            aerosol_phase_coefficients,
        ),
        .solar_mu = scene.geometry.solarCosineAtAltitude(altitude_km),
        .view_mu = scene.geometry.viewingCosineAtAltitude(altitude_km),
    };
}

fn fillLayerInputFromSharedCarrier(
    scene: *const Scene,
    wavelength_nm: f64,
    altitude_km: f64,
    breakdown: OpticalDepthBreakdown,
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64,
    layer_input: *transport_common.LayerInput,
    compute_jacobian: bool,
) void {
    const total_optical_depth = breakdown.totalOpticalDepth();
    const total_scattering = breakdown.totalScatteringOpticalDepth();

    // math: omega0 = total_scattering / total_optical_depth and phase is the gas/aerosol scattering-weighted mixture.
    // No-derivative LABOS consumes the aggregate transport fields below;
    // per-component fields feed derivative weighting.
    if (compute_jacobian) {
        layer_input.gas_absorption_optical_depth = breakdown.gas_absorption_optical_depth;
        layer_input.gas_scattering_optical_depth = breakdown.gas_scattering_optical_depth;
        layer_input.cia_optical_depth = breakdown.cia_optical_depth;
        layer_input.aerosol_optical_depth = breakdown.aerosol_optical_depth;
        layer_input.aerosol_scattering_optical_depth = breakdown.aerosol_scattering_optical_depth;
    }

    layer_input.optical_depth = total_optical_depth;
    layer_input.scattering_optical_depth = total_scattering;
    layer_input.single_scatter_albedo = breakdown.singleScatterAlbedo();

    if (compute_jacobian) {
        layer_input.optical_depth_jacobian = .{0.0} ** transport_common.Jacobian.state_count;
        layer_input.scattering_optical_depth_jacobian = .{0.0} ** transport_common.Jacobian.state_count;
        layer_input.single_scatter_albedo_jacobian = .{0.0} ** transport_common.Jacobian.state_count;
    }

    layer_input.solar_mu = scene.geometry.solarCosineAtAltitude(altitude_km);
    layer_input.view_mu = scene.geometry.viewingCosineAtAltitude(altitude_km);
    layer_input.phase = PhaseFunctions.PhaseMixture.fromScatteringMix(
        PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm),
        breakdown.gas_scattering_optical_depth,
        breakdown.aerosol_scattering_optical_depth,
        aerosol_phase_coefficients,
    );
}

pub fn fillReducedLayerInputFromSupportRowsWithSpectroscopyCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    layer_input: *transport_common.LayerInput,
    compute_jacobian: bool,
) OpticalDepthBreakdown {
    // fillReducedLayerInputFromSupportRowsWithSpectroscopyCache -------------------------------------------- |
    // Integrate prepared support rows into one transport LayerInput row.                                     |
    //                                                                                                        |
    // route                                                                                                  |
    //   support rows -> wavelength carrier -> weighted breakdown -> LayerInput                               |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Called from forward_layers.zig for each shared-RTM layer and wavelength when only the spectroscopy   |
    //   profile cache is available. It skips boundary rows because they mark layer edges, not interior       |
    //   support thickness.                                                                                   |
    // ------------------------------------------------------------------------------------------------------ |

    var breakdown: OpticalDepthBreakdown = .{};
    if (support_sublayers.len >= 2) {
        for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
            const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
            if (weight_km <= 0.0) continue;

            const strong_line_state = SpectroscopyState.strongLineStateAt(strong_line_states, local_index);
            const carrier = carrier_eval.sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
                self,
                wavelength_nm,
                support_sublayer,
                @intCast(support_sublayer.global_sublayer_index),
                strong_line_state,
                profile_cache,
            );
            accumulateSharedCarrier(&breakdown, &carrier, weight_km);
        }
    }

    fillLayerInputFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        &self.aerosol_phase_coefficients,
        layer_input,
        compute_jacobian,
    );
    return breakdown;
}

pub fn evaluateReducedLayerFromSupportRowsWithCarrierCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
) EvaluatedLayer {
    // evaluateReducedLayerFromSupportRowsWithCarrierCache -------------------------------------------------- |
    // Reduce support rows into one transport layer using cached wavelength scalars.                          |
    //                                                                                                        |
    // hot path                                                                                               |
    // forward input construction calls this for reduced shared-RTM layers.                                   |
    // math: breakdown terms integrate k(lambda, z_i) * weight_i over active support rows.                    |
    // ------------------------------------------------------------------------------------------------------ |

    var breakdown: OpticalDepthBreakdown = .{};
    if (support_sublayers.len < 2) {
        return evaluatedLayerFromSharedCarrier(
            scene,
            wavelength_nm,
            layer_geometry.midpoint_altitude_km,
            breakdown,
            &self.aerosol_phase_coefficients,
        );
    }

    for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
        const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
        if (weight_km <= 0.0) continue;

        const strong_line_state = SpectroscopyState.strongLineStateAt(strong_line_states, local_index);
        var fallback_scalars: carrier_eval.SharedOpticalScalars = undefined;
        const scalars = wavelength_cache.cachedSupportRowScalarsRef(
            self,
            wavelength_nm,
            support_sublayer,
            @intCast(support_sublayer.global_sublayer_index),
            strong_line_state,
            &fallback_scalars,
        );
        accumulateSharedScalars(
            &breakdown,
            scalars,
            weight_km,
        );
    }

    return evaluatedLayerFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        &self.aerosol_phase_coefficients,
    );
}

pub fn fillReducedLayerInputFromSupportRowsWithCarrierCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
    layer_input: *transport_common.LayerInput,
    compute_jacobian: bool,
) OpticalDepthBreakdown {
    var breakdown: OpticalDepthBreakdown = .{};
    if (support_sublayers.len >= 2) {
        for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
            const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
            if (weight_km <= 0.0) continue;

            const strong_line_state = SpectroscopyState.strongLineStateAt(strong_line_states, local_index);
            var fallback_scalars: carrier_eval.SharedOpticalScalars = undefined;
            const scalars = wavelength_cache.cachedSupportRowScalarsRef(
                self,
                wavelength_nm,
                support_sublayer,
                @intCast(support_sublayer.global_sublayer_index),
                strong_line_state,
                &fallback_scalars,
            );
            accumulateSharedScalars(
                &breakdown,
                scalars,
                weight_km,
            );
        }
    }

    fillLayerInputFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        &self.aerosol_phase_coefficients,
        layer_input,
        compute_jacobian,
    );
    return breakdown;
}

pub fn fillSharedPseudoSphericalSamplesFromSupportRows(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    sample_index_start: usize,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) usize {
    // fillSharedPseudoSphericalSamplesFromSupportRows ------------------------------------------------------ |
    // Write direct-beam attenuation samples at prepared support-row altitudes.                               |
    //                                                                                                        |
    // route                                                                                                  |
    //   support row -> total optical depth per km -> PseudoSphericalSample                                   |
    //                                                                                                        |
    // memory                                                                                                 |
    //   attenuation_samples is caller-owned worker scratch; this function appends from sample_index_start.   |
    // ------------------------------------------------------------------------------------------------------ |

    var sample_index = sample_index_start;
    if (support_sublayers.len < 2) return sample_index;

    for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
        const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
        const strong_line_state = SpectroscopyState.strongLineStateAt(strong_line_states, local_index);
        const optical_depth = choose_optical_depth: {
            if (weight_km <= 0.0) break :choose_optical_depth 0.0;

            break :choose_optical_depth weight_km * carrier_eval.sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
                self,
                wavelength_nm,
                support_sublayer,
                @intCast(support_sublayer.global_sublayer_index),
                strong_line_state,
                profile_cache,
            ).totalOpticalDepthPerKm();
        };

        attenuation_samples[sample_index] = .{
            .altitude_km = support_sublayer.altitude_km,
            .thickness_km = weight_km,
            .optical_depth = optical_depth,
        };
        sample_index += 1;
    }

    return sample_index;
}

pub fn fillSharedPseudoSphericalSamplesFromSupportRowsWithCarrierCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    sample_index_start: usize,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
) usize {
    // fillSharedPseudoSphericalSamplesFromSupportRowsWithCarrierCache -------------------------------------- |
    // Write pseudo-spherical attenuation samples from cached support-row optical depth.                      |
    //                                                                                                        |
    // hot path                                                                                               |
    // pseudo-spherical grids use this for cached shared support rows.                                        |
    // math: sample optical_depth = total_k_ext(lambda, z_i) * support_weight_km_i.                           |
    // ------------------------------------------------------------------------------------------------------ |

    var sample_index = sample_index_start;
    if (support_sublayers.len < 2) return sample_index;

    for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
        const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
        const strong_line_state = SpectroscopyState.strongLineStateAt(strong_line_states, local_index);
        const optical_depth = choose_optical_depth: {
            if (weight_km <= 0.0) break :choose_optical_depth 0.0;

            var fallback_scalars: carrier_eval.SharedOpticalScalars = undefined;
            const scalars = wavelength_cache.cachedSupportRowScalarsRef(
                self,
                wavelength_nm,
                support_sublayer,
                @intCast(support_sublayer.global_sublayer_index),
                strong_line_state,
                &fallback_scalars,
            );
            break :choose_optical_depth weight_km * scalars.totalOpticalDepthPerKm();
        };

        attenuation_samples[sample_index] = .{
            .altitude_km = support_sublayer.altitude_km,
            .thickness_km = weight_km,
            .optical_depth = optical_depth,
        };
        sample_index += 1;
    }

    return sample_index;
}

pub fn evaluateSharedLayerOnSubgridWithSpectroscopyCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    scratch: *shared_geometry.GaussRuleScratch,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) EvaluatedLayer {
    // evaluateSharedLayerOnSubgridWithSpectroscopyCache ---------------------------------------------------- |
    // Evaluate shared optical carriers on Gauss subgrid points for RTM quadrature.                           |
    //                                                                                                        |
    // hot path                                                                                               |
    // integrated source-function routes call this for shared RTM subgrid levels.                             |
    // math: layer breakdown approximates int k(lambda,z) dz by sum_i k(lambda,z_i) * w_i.                    |
    // ------------------------------------------------------------------------------------------------------ |

    const subgrid = resolveSharedRtmSubgrid(
        layer_geometry.lower_altitude_km,
        layer_geometry.upper_altitude_km,
        sharedRtmSubgridSampleCount(scene),
        scratch,
    );
    var breakdown: OpticalDepthBreakdown = .{};
    for (0..subgrid.altitudes_km.len) |node_index| {
        const weight_km = subgrid.weights_km[node_index];
        if (weight_km <= 0.0) continue;
        const carrier = carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
            self,
            wavelength_nm,
            support_sublayers,
            strong_line_states,
            subgrid.altitudes_km[node_index],
            profile_cache,
        );
        accumulateSharedCarrier(
            &breakdown,
            &carrier,
            weight_km,
        );
    }

    return evaluatedLayerFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        &self.aerosol_phase_coefficients,
    );
}

pub fn fillSharedPseudoSphericalSamplesOnSubgridWithSpectroscopyCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    sample_index_start: usize,
    scratch: *shared_geometry.GaussRuleScratch,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) usize {
    // fillSharedPseudoSphericalSamplesOnSubgridWithSpectroscopyCache --------------------------------------- |
    // Write direct-beam attenuation samples on a temporary Gauss subgrid.                                    |
    //                                                                                                        |
    // route                                                                                                  |
    //   SharedRtmLayerGeometry -> Gauss subgrid -> total optical depth per km -> PseudoSphericalSample       |
    //                                                                                                        |
    // memory                                                                                                 |
    //   scratch owns the temporary quadrature rows; attenuation_samples is caller-owned output storage.      |
    // ------------------------------------------------------------------------------------------------------ |

    const subgrid = resolveSharedRtmSubgrid(
        layer_geometry.lower_altitude_km,
        layer_geometry.upper_altitude_km,
        sharedRtmSubgridSampleCount(scene),
        scratch,
    );
    var sample_index = sample_index_start;
    for (0..subgrid.altitudes_km.len) |node_index| {
        const weight_km = subgrid.weights_km[node_index];
        const optical_depth = choose_optical_depth: {
            if (weight_km <= 0.0) break :choose_optical_depth 0.0;

            break :choose_optical_depth weight_km * carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
                self,
                wavelength_nm,
                support_sublayers,
                strong_line_states,
                subgrid.altitudes_km[node_index],
                profile_cache,
            ).totalOpticalDepthPerKm();
        };

        attenuation_samples[sample_index] = .{
            .altitude_km = subgrid.altitudes_km[node_index],
            .thickness_km = weight_km,
            .optical_depth = optical_depth,
        };
        sample_index += 1;
    }

    return sample_index;
}
