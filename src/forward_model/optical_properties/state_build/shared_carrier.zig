const Scene = @import("../../../input/Scene.zig").Scene;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const transport_common = @import("../../radiative_transfer/root.zig");
const Evaluation = @import("evaluation.zig");
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

// shared_carrier.zig ----------------------------------------------------------------------------------------|
// Evaluates optical carriers on the shared RTM support grid.                                                 |
//                                                                                                            |
// called by                                                                                                  |
//   forward-layer, RTM-quadrature, source-interface, and pseudo-spherical builders when shared geometry      |
//   can replace per-layer scalar approximations.                                                             |
//                                                                                                            |
// main path                                                                                                  |
//   resolve a Gauss subgrid for an altitude interval                                                         |
//   evaluate gas, CIA, aerosol, scattering, and phase carriers at support rows                               |
//   accumulate the weighted carrier into layer, level, or source-interface output rows                       |
//                                                                                                            |
// hot path                                                                                                   |
//   Runs inside wavelength and shared-support loops. Strong-line state lookup is centralized so each carrier |
//   loop pays one bounded optional-slice check instead of repeating the same guard in several places.        |
//                                                                                                            |
// memory                                                                                                     |
//   SharedRtmSubgrid borrows GaussRuleScratch storage; prepared sublayers and strong-line states stay owned  |
//   by PreparedOpticalState.                                                                                 |
// -----------------------------------------------------------------------------------------------------------|

// SharedRtmSubgrid ------------------------------------------------------------------------------------------|
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
// -----------------------------------------------------------------------------------------------------------|
pub const SharedRtmSubgrid = struct {
    altitudes_km: []const f64 = &.{},
    weights_km: []const f64 = &.{},
};

fn strongLineStateAt(
    states: ?[]const ReferenceData.StrongLinePreparedState,
    local_index: usize,
) ?*const ReferenceData.StrongLinePreparedState {
    const owned_states = states orelse return null;
    if (local_index >= owned_states.len) return null;
    return &owned_states[local_index];
}

pub fn sharedRtmSubgridSampleCount(scene: *const Scene) usize {
    return @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

pub fn resolveSharedRtmSubgrid(
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    sample_count: usize,
    scratch: *shared_geometry.GaussRuleScratch,
) SharedRtmSubgrid {
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

pub fn evaluateReducedLayerFromSupportRows(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
) EvaluatedLayer {
    return evaluateReducedLayerFromSupportRowsWithSpectroscopyCache(
        self,
        scene,
        wavelength_nm,
        support_sublayers,
        strong_line_states,
        layer_geometry,
        null,
    );
}

pub fn evaluateReducedLayerFromSupportRowsWithSpectroscopyCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) EvaluatedLayer {
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

        const strong_line_state = strongLineStateAt(strong_line_states, local_index);
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

    return evaluatedLayerFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        &self.aerosol_phase_coefficients,
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
    var breakdown: OpticalDepthBreakdown = .{};
    if (support_sublayers.len >= 2) {
        for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
            const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
            if (weight_km <= 0.0) continue;

            const strong_line_state = strongLineStateAt(strong_line_states, local_index);
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
    // evaluateReducedLayerFromSupportRowsWithCarrierCache ---------------------------------------------------|
    // Reduce support rows into one transport layer using cached wavelength scalars.                          |
    //                                                                                                        |
    // hot path                                                                                               |
    // forward input construction calls this for reduced shared-RTM layers.                                   |
    // math: breakdown terms integrate k(lambda, z_i) * weight_i over active support rows.                    |
    // -------------------------------------------------------------------------------------------------------|

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

        const strong_line_state = strongLineStateAt(strong_line_states, local_index);
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

            const strong_line_state = strongLineStateAt(strong_line_states, local_index);
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
    var sample_index = sample_index_start;
    if (support_sublayers.len < 2) return sample_index;

    for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
        const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
        const strong_line_state = strongLineStateAt(strong_line_states, local_index);
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
    // fillSharedPseudoSphericalSamplesFromSupportRowsWithCarrierCache ---------------------------------------|
    // Write pseudo-spherical attenuation samples from cached support-row optical depth.                      |
    //                                                                                                        |
    // hot path                                                                                               |
    // pseudo-spherical grids use this for cached shared support rows.                                        |
    // math: sample optical_depth = total_k_ext(lambda, z_i) * support_weight_km_i.                           |
    // -------------------------------------------------------------------------------------------------------|

    var sample_index = sample_index_start;
    if (support_sublayers.len < 2) return sample_index;

    for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
        const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
        const strong_line_state = strongLineStateAt(strong_line_states, local_index);
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

pub fn evaluateSharedLayerOnSubgrid(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    scratch: *shared_geometry.GaussRuleScratch,
) EvaluatedLayer {
    return evaluateSharedLayerOnSubgridWithSpectroscopyCache(
        self,
        scene,
        wavelength_nm,
        support_sublayers,
        strong_line_states,
        layer_geometry,
        scratch,
        null,
    );
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
    // evaluateSharedLayerOnSubgridWithSpectroscopyCache -----------------------------------------------------|
    // Evaluate shared optical carriers on Gauss subgrid points for RTM quadrature.                           |
    //                                                                                                        |
    // hot path                                                                                               |
    // integrated source-function routes call this for shared RTM subgrid levels.                             |
    // math: layer breakdown approximates int k(lambda,z) dz by sum_i k(lambda,z_i) * w_i.                    |
    // -------------------------------------------------------------------------------------------------------|

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

pub fn fillSharedPseudoSphericalSamplesOnSubgrid(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    sample_index_start: usize,
    scratch: *shared_geometry.GaussRuleScratch,
) usize {
    return fillSharedPseudoSphericalSamplesOnSubgridWithSpectroscopyCache(
        self,
        scene,
        wavelength_nm,
        support_sublayers,
        strong_line_states,
        layer_geometry,
        attenuation_samples,
        sample_index_start,
        scratch,
        null,
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
