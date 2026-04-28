const Scene = @import("../../../input/Scene.zig").Scene;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const transport_common = @import("../../radiative_transfer/root.zig");
const Evaluation = @import("evaluation.zig");
const State = @import("state.zig");
const carrier_eval = @import("carrier_eval.zig");
const shared_geometry = @import("shared_geometry.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedOpticalState = State.PreparedOpticalState;
const PreparedSublayer = State.PreparedSublayer;
const OpticalDepthBreakdown = State.OpticalDepthBreakdown;
const EvaluatedLayer = State.EvaluatedLayer;
const SharedRtmLayerGeometry = State.SharedRtmLayerGeometry;

const phase_coefficient_count = @import("../shared/phase_functions.zig").phase_coefficient_count;

pub const SharedRtmSubgrid = struct {
    altitudes_km: [128]f64 = [_]f64{0.0} ** 128,
    weights_km: [128]f64 = [_]f64{0.0} ** 128,
    count: usize = 0,
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
    var subgrid: SharedRtmSubgrid = .{ .count = sample_count };
    if (sample_count == 0) return subgrid;

    if (sample_count == 1) {
        subgrid.altitudes_km[0] = 0.5 * (lower_altitude_km + upper_altitude_km);
        subgrid.weights_km[0] = @max(upper_altitude_km - lower_altitude_km, 0.0);
        return subgrid;
    }

    const rule = shared_geometry.resolveGaussRule(sample_count, scratch);
    for (0..sample_count) |node_index| {
        subgrid.altitudes_km[node_index] = shared_geometry.intervalAltitudeAtNode(
            lower_altitude_km,
            upper_altitude_km,
            rule.nodes[node_index],
        );
        subgrid.weights_km[node_index] = shared_geometry.intervalWeightKm(
            lower_altitude_km,
            upper_altitude_km,
            rule.weights[node_index],
        );
    }
    return subgrid;
}

pub fn accumulateSharedCarrier(
    breakdown: *OpticalDepthBreakdown,
    phase_numerator: *[phase_coefficient_count]f64,
    carrier: carrier_eval.SharedOpticalCarrier,
    weight_km: f64,
) void {
    const weighted_gas_absorption = carrier.gas_absorption_optical_depth_per_km * weight_km;
    const weighted_gas_scattering = carrier.gas_scattering_optical_depth_per_km * weight_km;
    const weighted_cia = carrier.cia_optical_depth_per_km * weight_km;
    const weighted_aerosol = carrier.aerosol_optical_depth_per_km * weight_km;
    const weighted_aerosol_scattering = carrier.aerosol_scattering_optical_depth_per_km * weight_km;
    const weighted_cloud = carrier.cloud_optical_depth_per_km * weight_km;
    const weighted_cloud_scattering = carrier.cloud_scattering_optical_depth_per_km * weight_km;

    breakdown.gas_absorption_optical_depth += weighted_gas_absorption;
    breakdown.gas_scattering_optical_depth += weighted_gas_scattering;
    breakdown.cia_optical_depth += weighted_cia;
    breakdown.aerosol_optical_depth += weighted_aerosol;
    breakdown.aerosol_scattering_optical_depth += weighted_aerosol_scattering;
    breakdown.cloud_optical_depth += weighted_cloud;
    breakdown.cloud_scattering_optical_depth += weighted_cloud_scattering;

    const weighted_scattering = weighted_gas_scattering +
        weighted_aerosol_scattering +
        weighted_cloud_scattering;
    if (weighted_scattering <= 0.0) return;

    for (0..phase_coefficient_count) |index| {
        phase_numerator[index] += weighted_scattering * carrier.phase_coefficients[index];
    }
}

pub fn evaluatedLayerFromSharedCarrier(
    scene: *const Scene,
    wavelength_nm: f64,
    altitude_km: f64,
    breakdown: OpticalDepthBreakdown,
    phase_numerator: [phase_coefficient_count]f64,
) EvaluatedLayer {
    const total_scattering = breakdown.totalScatteringOpticalDepth();
    var phase_coefficients = @import("../shared/phase_functions.zig").gasPhaseCoefficientsAtWavelength(wavelength_nm);
    if (total_scattering > 0.0) {
        for (0..phase_coefficient_count) |index| {
            phase_coefficients[index] = phase_numerator[index] / total_scattering;
        }
        phase_coefficients[0] = 1.0;
    }

    return .{
        .breakdown = breakdown,
        .phase_coefficients = phase_coefficients,
        .solar_mu = scene.geometry.solarCosineAtAltitude(altitude_km),
        .view_mu = scene.geometry.viewingCosineAtAltitude(altitude_km),
    };
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
    var phase_numerator = [_]f64{0.0} ** phase_coefficient_count;
    if (support_sublayers.len < 2) {
        return evaluatedLayerFromSharedCarrier(
            scene,
            wavelength_nm,
            layer_geometry.midpoint_altitude_km,
            breakdown,
            phase_numerator,
        );
    }

    for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
        const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
        if (weight_km <= 0.0) continue;
        const strong_line_state = if (strong_line_states) |states|
            if (local_index < states.len) &states[local_index] else null
        else
            null;
        const carrier = carrier_eval.sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
            self,
            wavelength_nm,
            support_sublayer,
            @intCast(support_sublayer.global_sublayer_index),
            strong_line_state,
            profile_cache,
        );
        accumulateSharedCarrier(&breakdown, &phase_numerator, carrier, weight_km);
    }
    return evaluatedLayerFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        phase_numerator,
    );
}

pub fn fillSharedPseudoSphericalSamplesFromSupportRows(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    attenuation_layers: []transport_common.LayerInput,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    sample_index_start: usize,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) usize {
    var sample_index = sample_index_start;
    if (support_sublayers.len < 2) return sample_index;
    for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
        const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
        const strong_line_state = if (strong_line_states) |states|
            if (local_index < states.len) &states[local_index] else null
        else
            null;
        const optical_depth = if (weight_km > 0.0)
            weight_km * carrier_eval.sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
                self,
                wavelength_nm,
                support_sublayer,
                @intCast(support_sublayer.global_sublayer_index),
                strong_line_state,
                profile_cache,
            ).totalOpticalDepthPerKm()
        else
            0.0;
        attenuation_samples[sample_index] = .{
            .altitude_km = support_sublayer.altitude_km,
            .thickness_km = weight_km,
            .optical_depth = optical_depth,
        };
        if (sample_index < attenuation_layers.len) {
            attenuation_layers[sample_index] = .{ .optical_depth = optical_depth };
        }
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
    const subgrid = resolveSharedRtmSubgrid(
        layer_geometry.lower_altitude_km,
        layer_geometry.upper_altitude_km,
        sharedRtmSubgridSampleCount(scene),
        scratch,
    );
    var breakdown: OpticalDepthBreakdown = .{};
    var phase_numerator = [_]f64{0.0} ** phase_coefficient_count;
    for (0..subgrid.count) |node_index| {
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
            &phase_numerator,
            carrier,
            weight_km,
        );
    }
    return evaluatedLayerFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        phase_numerator,
    );
}

pub fn fillSharedPseudoSphericalSamplesOnSubgrid(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    attenuation_layers: []transport_common.LayerInput,
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
        attenuation_layers,
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
    attenuation_layers: []transport_common.LayerInput,
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
    for (0..subgrid.count) |node_index| {
        const weight_km = subgrid.weights_km[node_index];
        const optical_depth = if (weight_km > 0.0)
            weight_km * carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
                self,
                wavelength_nm,
                support_sublayers,
                strong_line_states,
                subgrid.altitudes_km[node_index],
                profile_cache,
            ).totalOpticalDepthPerKm()
        else
            0.0;
        attenuation_samples[sample_index] = .{
            .altitude_km = subgrid.altitudes_km[node_index],
            .thickness_km = weight_km,
            .optical_depth = optical_depth,
        };
        if (sample_index < attenuation_layers.len) {
            attenuation_layers[sample_index] = .{ .optical_depth = optical_depth };
        }
        sample_index += 1;
    }
    return sample_index;
}
