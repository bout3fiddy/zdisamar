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

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: altitudes_km=16 B, weights_km=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: altitudes_km and weights_km are views into GaussRuleScratch storage
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total also includes referenced scratch storage
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
    if (sample_count == 0) return .{};

    if (sample_count == 1) {
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
    phase_numerator: *[phase_coefficient_count]f64,
    carrier: *const carrier_eval.SharedOpticalCarrier,
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

fn accumulateSharedScalars(
    breakdown: *OpticalDepthBreakdown,
    phase_numerator: *[phase_coefficient_count]f64,
    scalars: *const carrier_eval.SharedOpticalScalars,
    weight_km: f64,
    rayleigh_phase_coefficient2: f64,
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64,
    cloud_phase_coefficients: *const [phase_coefficient_count]f64,
) void {
    const weighted_gas_absorption = scalars.gas_absorption_optical_depth_per_km * weight_km;
    const weighted_gas_scattering = scalars.gas_scattering_optical_depth_per_km * weight_km;
    const weighted_cia = scalars.cia_optical_depth_per_km * weight_km;
    const weighted_aerosol = scalars.aerosol_optical_depth_per_km * weight_km;
    const weighted_aerosol_scattering = scalars.aerosol_scattering_optical_depth_per_km * weight_km;
    const weighted_cloud = scalars.cloud_optical_depth_per_km * weight_km;
    const weighted_cloud_scattering = scalars.cloud_scattering_optical_depth_per_km * weight_km;

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
        phase_numerator[index] +=
            weighted_aerosol_scattering * aerosol_phase_coefficients[index] +
            weighted_cloud_scattering * cloud_phase_coefficients[index];
    }
    phase_numerator[0] += weighted_gas_scattering;
    phase_numerator[2] += weighted_gas_scattering * rayleigh_phase_coefficient2;
}

pub fn evaluatedLayerFromSharedCarrier(
    scene: *const Scene,
    wavelength_nm: f64,
    altitude_km: f64,
    breakdown: OpticalDepthBreakdown,
    phase_numerator: [phase_coefficient_count]f64,
) EvaluatedLayer {
    const total_scattering = breakdown.totalScatteringOpticalDepth();
    var phase_coefficients = PhaseFunctions.gasPhaseCoefficientsAtWavelength(wavelength_nm);
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

fn fillLayerInputFromSharedCarrier(
    scene: *const Scene,
    wavelength_nm: f64,
    altitude_km: f64,
    breakdown: OpticalDepthBreakdown,
    phase_numerator: *const [phase_coefficient_count]f64,
    layer_input: *transport_common.LayerInput,
) void {
    const total_optical_depth = breakdown.totalOpticalDepth();
    const total_scattering = breakdown.totalScatteringOpticalDepth();
    layer_input.* = .{
        .gas_absorption_optical_depth = breakdown.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = breakdown.gas_scattering_optical_depth,
        .cia_optical_depth = breakdown.cia_optical_depth,
        .aerosol_optical_depth = breakdown.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = breakdown.aerosol_scattering_optical_depth,
        .cloud_optical_depth = breakdown.cloud_optical_depth,
        .cloud_scattering_optical_depth = breakdown.cloud_scattering_optical_depth,
        .optical_depth = total_optical_depth,
        .scattering_optical_depth = total_scattering,
        .single_scatter_albedo = breakdown.singleScatterAlbedo(),
        .optical_depth_jacobian = .{0.0} ** transport_common.Jacobian.state_count,
        .scattering_optical_depth_jacobian = .{0.0} ** transport_common.Jacobian.state_count,
        .single_scatter_albedo_jacobian = .{0.0} ** transport_common.Jacobian.state_count,
        .solar_mu = scene.geometry.solarCosineAtAltitude(altitude_km),
        .view_mu = scene.geometry.viewingCosineAtAltitude(altitude_km),
        .phase_coefficients = undefined,
    };
    if (total_scattering > 0.0) {
        for (0..phase_coefficient_count) |index| {
            layer_input.phase_coefficients[index] = phase_numerator[index] / total_scattering;
        }
        layer_input.phase_coefficients[0] = 1.0;
        return;
    }
    layer_input.phase_coefficients = PhaseFunctions.gasPhaseCoefficientsAtWavelength(wavelength_nm);
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
        accumulateSharedCarrier(&breakdown, &phase_numerator, &carrier, weight_km);
    }
    return evaluatedLayerFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        phase_numerator,
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
) OpticalDepthBreakdown {
    var breakdown: OpticalDepthBreakdown = .{};
    var phase_numerator = [_]f64{0.0} ** phase_coefficient_count;
    if (support_sublayers.len >= 2) {
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
            accumulateSharedCarrier(&breakdown, &phase_numerator, &carrier, weight_km);
        }
    }
    fillLayerInputFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        &phase_numerator,
        layer_input,
    );
    return breakdown;
}

// hot path:
//   when: forward input construction reduces support rows into a transport layer
//   work: samples carrier cache rows and accumulates layer optical properties
//   data: support-row descriptors, cached optical scalars, layer output fields
//   follow: WavelengthCarrierCache scalar access and direct phase-numerator accumulation
pub fn evaluateReducedLayerFromSupportRowsWithCarrierCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
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
            &phase_numerator,
            scalars,
            weight_km,
            wavelength_cache.rayleigh_phase_coefficient2,
            &self.aerosol_phase_coefficients,
            &self.cloud_phase_coefficients,
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

pub fn fillReducedLayerInputFromSupportRowsWithCarrierCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
    layer_input: *transport_common.LayerInput,
) OpticalDepthBreakdown {
    var breakdown: OpticalDepthBreakdown = .{};
    var phase_numerator = [_]f64{0.0} ** phase_coefficient_count;
    if (support_sublayers.len >= 2) {
        for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
            const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
            if (weight_km <= 0.0) continue;
            const strong_line_state = if (strong_line_states) |states|
                if (local_index < states.len) &states[local_index] else null
            else
                null;
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
                &phase_numerator,
                scalars,
                weight_km,
                wavelength_cache.rayleigh_phase_coefficient2,
                &self.aerosol_phase_coefficients,
                &self.cloud_phase_coefficients,
            );
        }
    }
    fillLayerInputFromSharedCarrier(
        scene,
        wavelength_nm,
        layer_geometry.midpoint_altitude_km,
        breakdown,
        &phase_numerator,
        layer_input,
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
        sample_index += 1;
    }
    return sample_index;
}

// hot path:
//   when: pseudo-spherical grids expand shared support rows for a cached wavelength solve
//   work: writes attenuation samples from support-row carrier optical depth per kilometer
//   data: support sublayers, strong-line states, scalar carrier cache, attenuation sample outputs
//   follow: fillPseudoSphericalGridAtWavelengthWithCarrierCache and carrier cache reuse
pub fn fillSharedPseudoSphericalSamplesFromSupportRowsWithCarrierCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    sample_index_start: usize,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
) usize {
    var sample_index = sample_index_start;
    if (support_sublayers.len < 2) return sample_index;
    for (support_sublayers[1 .. support_sublayers.len - 1], 1..) |support_sublayer, local_index| {
        const weight_km = @max(support_sublayer.path_length_cm / 1.0e5, 0.0);
        const strong_line_state = if (strong_line_states) |states|
            if (local_index < states.len) &states[local_index] else null
        else
            null;
        const optical_depth = if (weight_km > 0.0) optical_depth: {
            var fallback_scalars: carrier_eval.SharedOpticalScalars = undefined;
            const scalars = wavelength_cache.cachedSupportRowScalarsRef(
                self,
                wavelength_nm,
                support_sublayer,
                @intCast(support_sublayer.global_sublayer_index),
                strong_line_state,
                &fallback_scalars,
            );
            break :optical_depth weight_km * scalars.totalOpticalDepthPerKm();
        } else 0.0;
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

// hot path:
//   when: integrated source-function routes evaluate RTM subgrid levels
//   work: evaluates shared optical carriers on Gauss subgrid points for quadrature
//   data: subgrid support rows, profile spectroscopy cache, layer input outputs
//   follow: resolveSharedRtmSubgrid and fillSharedPseudoSphericalSamplesOnSubgrid
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
            &phase_numerator,
            &carrier,
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
        sample_index += 1;
    }
    return sample_index;
}
