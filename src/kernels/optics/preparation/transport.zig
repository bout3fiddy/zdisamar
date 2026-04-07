//! Purpose:
//!   Convert prepared optical state into transport-ready layer, source, and
//!   pseudo-spherical carriers.
//!
//! Physics:
//!   Evaluates wavelength-dependent optical-depth breakdowns and builds the
//!   RTM quadrature and pseudo-spherical geometry used by the transport
//!   executors.
//!
//! Vendor:
//!   `optics preparation transport`
//!
//! Design:
//!   Keeps the transport-facing preparation logic separate from the layer and
//!   spectroscopy state builders so the solver can reuse the same prepared
//!   state for multiple routes.
//!
//! Invariants:
//!   Prepared layers, quadrature nodes, and pseudo-spherical samples must stay
//!   aligned with the scene's transport grid.
//!
//! Validation:
//!   Optics-preparation transport tests and transport integration suites.

const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const Rayleigh = @import("../../../model/reference/rayleigh.zig");
const gauss_legendre = @import("../../quadrature/gauss_legendre.zig");
const transport_common = @import("../../transport/common.zig");
const ParticleProfiles = @import("../prepare/particle_profiles.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");
const State = @import("state.zig");
const Evaluation = @import("evaluation.zig");

const phase_coefficient_count = PhaseFunctions.phase_coefficient_count;
const centimeters_per_kilometer = 1.0e5;
const max_dynamic_gauss_order: usize = 128;

const PreparedOpticalState = State.PreparedOpticalState;
const PreparedSublayer = State.PreparedSublayer;
const OpticalDepthBreakdown = State.OpticalDepthBreakdown;
const EvaluatedLayer = State.EvaluatedLayer;
const SharedRtmGeometry = State.SharedRtmGeometry;
const SharedRtmLayerGeometry = State.SharedRtmLayerGeometry;
const SharedRtmLevelGeometry = State.SharedRtmLevelGeometry;

const ResolvedGaussRule = struct {
    nodes: []const f64,
    weights: []const f64,
};

const GaussRuleScratch = struct {
    nodes: [max_dynamic_gauss_order]f64 = [_]f64{0.0} ** max_dynamic_gauss_order,
    weights: [max_dynamic_gauss_order]f64 = [_]f64{0.0} ** max_dynamic_gauss_order,
};

const SharedRtmSubgrid = struct {
    altitudes_km: [max_dynamic_gauss_order]f64 = [_]f64{0.0} ** max_dynamic_gauss_order,
    weights_km: [max_dynamic_gauss_order]f64 = [_]f64{0.0} ** max_dynamic_gauss_order,
    count: usize = 0,
};

const SharedOpticalCarrier = struct {
    gas_absorption_optical_depth_per_km: f64 = 0.0,
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    cia_optical_depth_per_km: f64 = 0.0,
    aerosol_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,
    cloud_optical_depth_per_km: f64 = 0.0,
    cloud_scattering_optical_depth_per_km: f64 = 0.0,
    phase_coefficients: [phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),

    fn totalScatteringOpticalDepthPerKm(self: SharedOpticalCarrier) f64 {
        return self.gas_scattering_optical_depth_per_km +
            self.aerosol_scattering_optical_depth_per_km +
            self.cloud_scattering_optical_depth_per_km;
    }

    fn totalOpticalDepthPerKm(self: SharedOpticalCarrier) f64 {
        return self.gas_absorption_optical_depth_per_km +
            self.gas_scattering_optical_depth_per_km +
            self.cia_optical_depth_per_km +
            self.aerosol_optical_depth_per_km +
            self.cloud_optical_depth_per_km;
    }
};

const SharedRtmInterval = struct {
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState = null,
};

const SharedSupportSlices = struct {
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
};

fn usesSharedRtmGrid(self: *const PreparedOpticalState, transport_layer_count: usize) bool {
    if (self.interval_semantics == .none) return false;
    const sublayers = self.sublayers orelse return false;
    return transport_layer_count == sublayers.len;
}

fn cachedSharedRtmGeometry(
    self: *const PreparedOpticalState,
    transport_layer_count: usize,
) ?*const SharedRtmGeometry {
    if (!self.shared_rtm_geometry.isValidFor(transport_layer_count)) return null;
    return &self.shared_rtm_geometry;
}

fn resolveGaussRule(order: usize, scratch: *GaussRuleScratch) ResolvedGaussRule {
    if (order == 0) unreachable;
    if (order > max_dynamic_gauss_order) {
        @panic("gauss-legendre order exceeds shared RTM scratch capacity");
    }

    if (order <= 10) {
        const rule = gauss_legendre.rule(@intCast(order)) catch unreachable;
        @memcpy(scratch.nodes[0..order], rule.nodes[0..order]);
        @memcpy(scratch.weights[0..order], rule.weights[0..order]);
    } else {
        gauss_legendre.fillNodesAndWeights(
            @intCast(order),
            scratch.nodes[0..order],
            scratch.weights[0..order],
        ) catch unreachable;
    }

    return .{
        .nodes = scratch.nodes[0..order],
        .weights = scratch.weights[0..order],
    };
}

fn intervalAltitudeAtNode(
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    normalized_node: f64,
) f64 {
    const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);
    return lower_altitude_km + 0.5 * (normalized_node + 1.0) * altitude_span_km;
}

fn intervalWeightKm(
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    normalized_weight: f64,
) f64 {
    const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);
    return 0.5 * normalized_weight * altitude_span_km;
}

fn sharedRtmInterval(
    self: *const PreparedOpticalState,
    sublayers: []const PreparedSublayer,
    layer: State.PreparedLayer,
) SharedRtmInterval {
    const start_index: usize = @intCast(layer.sublayer_start_index);
    const count: usize = @intCast(layer.sublayer_count);
    const stop_index = start_index + count;
    return .{
        .lower_altitude_km = levelAltitudeFromSublayers(sublayers, start_index),
        .upper_altitude_km = levelAltitudeFromSublayers(sublayers, stop_index),
        .support_sublayers = sublayers[start_index..stop_index],
        .strong_line_states = if (self.strong_line_states) |states|
            states[start_index..stop_index]
        else
            null,
    };
}

fn sharedSupportSlices(
    self: *const PreparedOpticalState,
    sublayers: []const PreparedSublayer,
    support_start_index: usize,
    support_count: usize,
) SharedSupportSlices {
    const support_stop_index = support_start_index + support_count;
    return .{
        .sublayers = sublayers[support_start_index..support_stop_index],
        .strong_line_states = if (self.strong_line_states) |states|
            states[support_start_index..support_stop_index]
        else
            null,
    };
}

/// Purpose:
///   Build the wavelength-invariant shared RTM geometry cache.
///
/// Physics:
///   Resolves the explicit shared-grid transport path onto one RTM level grid
///   so level and layer indices carry the same physical altitudes for every
///   wavelength evaluation.
///
/// Vendor:
///   `integrated source-function RTM grid` stage
///
/// Validation:
///   Shared-grid measurement-space tests and O2A forward profiles.
pub fn buildSharedRtmGeometry(
    allocator: std.mem.Allocator,
    self: *const PreparedOpticalState,
) !SharedRtmGeometry {
    const transport_layer_count = self.transportLayerCount();
    if (!usesSharedRtmGrid(self, transport_layer_count)) return .{};
    const sublayers = self.sublayers orelse return .{};

    const layers = try allocator.alloc(SharedRtmLayerGeometry, transport_layer_count);
    errdefer allocator.free(layers);
    const levels = try allocator.alloc(SharedRtmLevelGeometry, transport_layer_count + 1);
    errdefer allocator.free(levels);
    @memset(layers, .{});
    @memset(levels, .{});

    var interval_rule_scratch: GaussRuleScratch = .{};
    for (self.layers) |layer| {
        const start_index: usize = @intCast(layer.sublayer_start_index);
        const count: usize = @intCast(layer.sublayer_count);
        if (count == 0) continue;

        const interval = sharedRtmInterval(self, sublayers, layer);
        const level_node_count = count - 1;
        const level_rule = if (level_node_count > 0)
            resolveGaussRule(level_node_count, &interval_rule_scratch)
        else
            null;

        levels[start_index] = .{
            .altitude_km = interval.lower_altitude_km,
            .weight_km = 0.0,
            .support_start_index = @intCast(start_index),
            .support_count = @intCast(count),
        };
        for (0..level_node_count) |node_index| {
            levels[start_index + 1 + node_index] = .{
                .altitude_km = intervalAltitudeAtNode(
                    interval.lower_altitude_km,
                    interval.upper_altitude_km,
                    level_rule.?.nodes[node_index],
                ),
                .weight_km = intervalWeightKm(
                    interval.lower_altitude_km,
                    interval.upper_altitude_km,
                    level_rule.?.weights[node_index],
                ),
                .support_start_index = @intCast(start_index),
                .support_count = @intCast(count),
            };
        }

        const stop_index = start_index + count;
        levels[stop_index] = .{
            .altitude_km = interval.upper_altitude_km,
            .weight_km = 0.0,
            .support_start_index = @intCast(start_index),
            .support_count = @intCast(count),
        };

        for (0..count) |local_layer_index| {
            const lower_altitude_km = levels[start_index + local_layer_index].altitude_km;
            const upper_altitude_km = levels[start_index + local_layer_index + 1].altitude_km;
            layers[start_index + local_layer_index] = .{
                .lower_altitude_km = lower_altitude_km,
                .upper_altitude_km = upper_altitude_km,
                .midpoint_altitude_km = 0.5 * (lower_altitude_km + upper_altitude_km),
                .thickness_km = @max(upper_altitude_km - lower_altitude_km, 0.0),
                .support_start_index = @intCast(start_index),
                .support_count = @intCast(count),
            };
        }
    }

    return .{
        .layers = layers,
        .levels = levels,
    };
}

fn accumulateSharedCarrier(
    breakdown: *OpticalDepthBreakdown,
    phase_numerator: *[phase_coefficient_count]f64,
    carrier: SharedOpticalCarrier,
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

fn evaluatedLayerFromSharedCarrier(
    scene: *const Scene,
    altitude_km: f64,
    breakdown: OpticalDepthBreakdown,
    phase_numerator: [phase_coefficient_count]f64,
) EvaluatedLayer {
    const total_scattering = breakdown.totalScatteringOpticalDepth();
    var phase_coefficients = PhaseFunctions.gasPhaseCoefficients();
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

fn sharedRtmSubgridSampleCount(scene: *const Scene) usize {
    return @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

fn resolveSharedRtmSubgrid(
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    sample_count: usize,
    scratch: *GaussRuleScratch,
) SharedRtmSubgrid {
    var subgrid: SharedRtmSubgrid = .{ .count = sample_count };
    if (sample_count == 0) return subgrid;

    if (sample_count == 1) {
        subgrid.altitudes_km[0] = 0.5 * (lower_altitude_km + upper_altitude_km);
        subgrid.weights_km[0] = @max(upper_altitude_km - lower_altitude_km, 0.0);
        return subgrid;
    }

    const rule = resolveGaussRule(sample_count, scratch);
    for (0..sample_count) |node_index| {
        subgrid.altitudes_km[node_index] = intervalAltitudeAtNode(
            lower_altitude_km,
            upper_altitude_km,
            rule.nodes[node_index],
        );
        subgrid.weights_km[node_index] = intervalWeightKm(
            lower_altitude_km,
            upper_altitude_km,
            rule.weights[node_index],
        );
    }
    return subgrid;
}

fn evaluateSharedLayerOnSubgrid(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    scratch: *GaussRuleScratch,
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
        const carrier = sharedOpticalCarrierAtAltitude(
            self,
            wavelength_nm,
            support_sublayers,
            strong_line_states,
            subgrid.altitudes_km[node_index],
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
        layer_geometry.midpoint_altitude_km,
        breakdown,
        phase_numerator,
    );
}

fn fillSharedPseudoSphericalSamplesOnSubgrid(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    layer_geometry: SharedRtmLayerGeometry,
    attenuation_layers: []transport_common.LayerInput,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    sample_index_start: usize,
    scratch: *GaussRuleScratch,
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
            weight_km * sharedOpticalCarrierAtAltitude(
                self,
                wavelength_nm,
                support_sublayers,
                strong_line_states,
                subgrid.altitudes_km[node_index],
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

/// Purpose:
///   Convert the prepared state into a forward-input carrier.
pub fn toForwardInput(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
) transport_common.ForwardInput {
    return toForwardInputWithLayers(prepared, scene, null);
}

/// Purpose:
///   Convert the prepared state into a forward-input carrier using explicit
///   layer inputs.
pub fn toForwardInputWithLayers(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    layer_inputs: ?[]transport_common.LayerInput,
) transport_common.ForwardInput {
    return toForwardInputAtWavelengthWithLayers(
        prepared,
        scene,
        (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
        layer_inputs,
    );
}

/// Purpose:
///   Convert the prepared state into a forward-input carrier at one wavelength.
pub fn toForwardInputAtWavelength(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
) transport_common.ForwardInput {
    return toForwardInputAtWavelengthWithLayers(prepared, scene, wavelength_nm, null);
}

/// Purpose:
///   Convert the prepared state into a wavelength-specific forward-input
///   carrier using explicit layer inputs.
pub fn toForwardInputAtWavelengthWithLayers(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: ?[]transport_common.LayerInput,
) transport_common.ForwardInput {
    const optical_depths = if (layer_inputs) |owned_layers|
        fillForwardLayersAtWavelength(prepared, scene, wavelength_nm, owned_layers)
    else
        prepared.opticalDepthBreakdownAtWavelength(wavelength_nm);
    const mu0 = scene.geometry.solarCosineAtAltitude(0.0);
    const muv = scene.geometry.viewingCosineAtAltitude(0.0);
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const spectral_weight = if (scene.spectral_grid.sample_count <= 1)
        @max(span_nm, 1.0e-6)
    else
        span_nm / @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    return .{
        .wavelength_nm = wavelength_nm,
        .spectral_weight = @max(spectral_weight, 1.0e-6),
        .air_mass_factor = prepared.effective_air_mass_factor,
        .mu0 = mu0,
        .muv = muv,
        .relative_azimuth_rad = transportAzimuthDifferenceRad(scene.geometry.relative_azimuth_deg),
        .surface_albedo = std.math.clamp(scene.surface.albedo, 0.0, 1.0),
        .gas_absorption_optical_depth = optical_depths.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = optical_depths.gas_scattering_optical_depth,
        .cia_optical_depth = optical_depths.cia_optical_depth,
        .aerosol_optical_depth = optical_depths.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = optical_depths.aerosol_scattering_optical_depth,
        .cloud_optical_depth = optical_depths.cloud_optical_depth,
        .cloud_scattering_optical_depth = optical_depths.cloud_scattering_optical_depth,
        .optical_depth = optical_depths.totalOpticalDepth(),
        .single_scatter_albedo = if (optical_depths.totalOpticalDepth() > 0.0)
            optical_depths.singleScatterAlbedo()
        else
            prepared.effective_single_scatter_albedo,
        .layers = if (layer_inputs) |owned_layers| owned_layers else &.{},
    };
}

fn transportAzimuthDifferenceRad(relative_azimuth_deg: f64) f64 {
    // VENDOR PARITY:
    //   DISAMAR/LABOS expands the Fourier series in dphi, the azimuth
    //   difference between incident sunlight and the line of sight.
    const transport_dphi_deg = @mod(180.0 - relative_azimuth_deg, 360.0);
    return std.math.degreesToRadians(transport_dphi_deg);
}

/// Purpose:
///   Materialize transport layer inputs at one wavelength.
pub fn fillForwardLayersAtWavelength(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: []transport_common.LayerInput,
) OpticalDepthBreakdown {
    if (layer_inputs.len == 0) return self.opticalDepthBreakdownAtWavelength(wavelength_nm);

    if (self.sublayers) |sublayers| {
        if (usesSharedRtmGrid(self, layer_inputs.len)) {
            if (cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                var totals: OpticalDepthBreakdown = .{};
                var subgrid_rule_scratch: GaussRuleScratch = .{};
                for (geometry.layers, layer_inputs) |layer_geometry, *layer_input| {
                    const support_start_index: usize = @intCast(layer_geometry.support_start_index);
                    const support_count: usize = @intCast(layer_geometry.support_count);
                    const support = sharedSupportSlices(
                        self,
                        sublayers,
                        support_start_index,
                        support_count,
                    );

                    const evaluated = evaluateSharedLayerOnSubgrid(
                        self,
                        scene,
                        wavelength_nm,
                        support.sublayers,
                        support.strong_line_states,
                        layer_geometry,
                        &subgrid_rule_scratch,
                    );
                    layer_input.* = Evaluation.layerInputFromEvaluated(evaluated);
                    Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
                }
                return totals;
            }

            var totals: OpticalDepthBreakdown = .{};
            var interval_rule_scratch: GaussRuleScratch = .{};

            for (self.layers) |layer| {
                const start_index: usize = @intCast(layer.sublayer_start_index);
                const count: usize = @intCast(layer.sublayer_count);
                if (count == 0) continue;

                const interval = sharedRtmInterval(self, sublayers, layer);
                const level_node_count = count - 1;
                const level_rule = if (level_node_count > 0)
                    resolveGaussRule(level_node_count, &interval_rule_scratch)
                else
                    null;

                for (0..count) |local_layer_index| {
                    const lower_altitude_km = if (local_layer_index == 0)
                        interval.lower_altitude_km
                    else
                        intervalAltitudeAtNode(
                            interval.lower_altitude_km,
                            interval.upper_altitude_km,
                            level_rule.?.nodes[local_layer_index - 1],
                        );
                    const upper_altitude_km = if (local_layer_index + 1 == count)
                        interval.upper_altitude_km
                    else
                        intervalAltitudeAtNode(
                            interval.lower_altitude_km,
                            interval.upper_altitude_km,
                            level_rule.?.nodes[local_layer_index],
                        );
                    const midpoint_altitude_km = 0.5 * (lower_altitude_km + upper_altitude_km);
                    const evaluated = evaluateSharedLayerOnSubgrid(
                        self,
                        scene,
                        wavelength_nm,
                        interval.support_sublayers,
                        interval.strong_line_states,
                        .{
                            .lower_altitude_km = lower_altitude_km,
                            .upper_altitude_km = upper_altitude_km,
                            .midpoint_altitude_km = midpoint_altitude_km,
                            .thickness_km = @max(upper_altitude_km - lower_altitude_km, 0.0),
                            .support_start_index = @intCast(start_index),
                            .support_count = @intCast(count),
                        },
                        &interval_rule_scratch,
                    );
                    layer_inputs[start_index + local_layer_index] = Evaluation.layerInputFromEvaluated(evaluated);
                    Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
                }
            }
            return totals;
        }

        if (layer_inputs.len == sublayers.len) {
            var totals: OpticalDepthBreakdown = .{};
            for (sublayers, 0..) |sublayer, sublayer_index| {
                const evaluated = self.evaluateLayerAtWavelength(
                    scene,
                    sublayer.altitude_km,
                    wavelength_nm,
                    sublayer_index,
                    sublayers[sublayer_index .. sublayer_index + 1],
                    if (self.strong_line_states) |states| states[sublayer_index .. sublayer_index + 1] else null,
                );
                layer_inputs[sublayer_index] = Evaluation.layerInputFromEvaluated(evaluated);
                Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
            }
            return totals;
        }

        var totals: OpticalDepthBreakdown = .{};
        for (self.layers, layer_inputs) |layer, *layer_input| {
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const end_index = start_index + @as(usize, @intCast(layer.sublayer_count));
            const evaluated = self.evaluateLayerAtWavelength(
                scene,
                layer.altitude_km,
                wavelength_nm,
                start_index,
                sublayers[start_index..end_index],
                if (self.strong_line_states) |states| states[start_index..end_index] else null,
            );
            layer_input.* = Evaluation.layerInputFromEvaluated(evaluated);
            Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
        }
        return totals;
    }

    const particle_single_scatter_albedos = self.resolvedParticleSingleScatterAlbedos();

    var totals: OpticalDepthBreakdown = .{};
    for (self.layers, layer_inputs) |layer, *layer_input| {
        const aerosol_optical_depth = PreparedOpticalState.particleOpticalDepthAtWavelength(
            layer.aerosol_optical_depth,
            layer.aerosol_base_optical_depth,
            self.aerosol_reference_wavelength_nm,
            self.aerosol_angstrom_exponent,
            self.aerosol_fraction_control,
            wavelength_nm,
        );
        const cloud_optical_depth = PreparedOpticalState.particleOpticalDepthAtWavelength(
            layer.cloud_optical_depth,
            layer.cloud_base_optical_depth,
            self.cloud_reference_wavelength_nm,
            self.cloud_angstrom_exponent,
            self.cloud_fraction_control,
            wavelength_nm,
        );
        const gas_scattering_optical_depth = layer.gas_scattering_optical_depth;
        const gas_absorption_optical_depth = @max(
            layer.gas_optical_depth - gas_scattering_optical_depth,
            0.0,
        );
        const aerosol_scattering_optical_depth =
            aerosol_optical_depth * particle_single_scatter_albedos.aerosol;
        const cloud_scattering_optical_depth =
            cloud_optical_depth * particle_single_scatter_albedos.cloud;
        const optical_depth =
            gas_absorption_optical_depth +
            gas_scattering_optical_depth +
            layer.cia_optical_depth +
            aerosol_optical_depth +
            cloud_optical_depth;
        const scattering_optical_depth =
            gas_scattering_optical_depth +
            aerosol_scattering_optical_depth +
            cloud_scattering_optical_depth;
        layer_input.* = .{
            .gas_absorption_optical_depth = gas_absorption_optical_depth,
            .gas_scattering_optical_depth = gas_scattering_optical_depth,
            .cia_optical_depth = layer.cia_optical_depth,
            .aerosol_optical_depth = aerosol_optical_depth,
            .aerosol_scattering_optical_depth = aerosol_scattering_optical_depth,
            .cloud_optical_depth = cloud_optical_depth,
            .cloud_scattering_optical_depth = cloud_scattering_optical_depth,
            .optical_depth = optical_depth,
            .scattering_optical_depth = scattering_optical_depth,
            .single_scatter_albedo = if (optical_depth > 0.0)
                std.math.clamp(scattering_optical_depth / optical_depth, 0.0, 1.0)
            else
                0.0,
            .solar_mu = scene.geometry.solarCosineAtAltitude(layer.altitude_km),
            .view_mu = scene.geometry.viewingCosineAtAltitude(layer.altitude_km),
            .phase_coefficients = PhaseFunctions.hgPhaseCoefficients(scene.aerosol.asymmetry_factor),
        };
        totals.gas_absorption_optical_depth += gas_absorption_optical_depth;
        totals.gas_scattering_optical_depth += gas_scattering_optical_depth;
        totals.cia_optical_depth += layer.cia_optical_depth;
        totals.aerosol_optical_depth += aerosol_optical_depth;
        totals.aerosol_scattering_optical_depth += aerosol_scattering_optical_depth;
        totals.cloud_optical_depth += cloud_optical_depth;
        totals.cloud_scattering_optical_depth += cloud_scattering_optical_depth;
    }
    return totals;
}

/// Purpose:
///   Materialize source-interface carriers at one wavelength.
pub fn fillSourceInterfacesAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
) void {
    if (layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1) return;

    if (self.sublayers) |sublayers| {
        if (usesSharedRtmGrid(self, layer_inputs.len)) {
            if (cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                for (source_interfaces, geometry.levels) |*source_interface, level_geometry| {
                    const support_start_index: usize = @intCast(level_geometry.support_start_index);
                    const support_count: usize = @intCast(level_geometry.support_count);
                    const support = sharedSupportSlices(
                        self,
                        sublayers,
                        support_start_index,
                        support_count,
                    );
                    const carrier = sharedOpticalCarrierAtAltitude(
                        self,
                        wavelength_nm,
                        support.sublayers,
                        support.strong_line_states,
                        level_geometry.altitude_km,
                    );
                    source_interface.* = .{
                        .source_weight = 0.0,
                        .rtm_weight = level_geometry.weight_km,
                        .ksca_above = if (level_geometry.weight_km > 0.0)
                            carrier.totalScatteringOpticalDepthPerKm()
                        else
                            0.0,
                        .phase_coefficients_above = carrier.phase_coefficients,
                    };
                }
                return;
            }

            for (source_interfaces) |*source_interface| source_interface.* = .{};

            var interval_rule_scratch: GaussRuleScratch = .{};
            for (self.layers) |layer| {
                const start_index: usize = @intCast(layer.sublayer_start_index);
                const count: usize = @intCast(layer.sublayer_count);
                if (count == 0) continue;

                const interval = sharedRtmInterval(self, sublayers, layer);
                const level_node_count = count - 1;
                const level_rule = if (level_node_count > 0)
                    resolveGaussRule(level_node_count, &interval_rule_scratch)
                else
                    null;

                const lower_carrier = sharedOpticalCarrierAtAltitude(
                    self,
                    wavelength_nm,
                    interval.support_sublayers,
                    interval.strong_line_states,
                    interval.lower_altitude_km,
                );
                source_interfaces[start_index] = .{
                    .source_weight = 0.0,
                    .rtm_weight = 0.0,
                    .ksca_above = 0.0,
                    .phase_coefficients_above = lower_carrier.phase_coefficients,
                };

                for (0..level_node_count) |node_index| {
                    const altitude_km = intervalAltitudeAtNode(
                        interval.lower_altitude_km,
                        interval.upper_altitude_km,
                        level_rule.?.nodes[node_index],
                    );
                    const weight_km = intervalWeightKm(
                        interval.lower_altitude_km,
                        interval.upper_altitude_km,
                        level_rule.?.weights[node_index],
                    );
                    const carrier = sharedOpticalCarrierAtAltitude(
                        self,
                        wavelength_nm,
                        interval.support_sublayers,
                        interval.strong_line_states,
                        altitude_km,
                    );
                    source_interfaces[start_index + 1 + node_index] = .{
                        .source_weight = 0.0,
                        .rtm_weight = weight_km,
                        .ksca_above = carrier.totalScatteringOpticalDepthPerKm(),
                        .phase_coefficients_above = carrier.phase_coefficients,
                    };
                }

                const stop_index = start_index + count;
                const upper_carrier = sharedOpticalCarrierAtAltitude(
                    self,
                    wavelength_nm,
                    interval.support_sublayers,
                    interval.strong_line_states,
                    interval.upper_altitude_km,
                );
                source_interfaces[stop_index] = .{
                    .source_weight = 0.0,
                    .rtm_weight = 0.0,
                    .ksca_above = 0.0,
                    .phase_coefficients_above = upper_carrier.phase_coefficients,
                };
            }
            return;
        }
    }

    transport_common.fillSourceInterfacesFromLayers(layer_inputs, source_interfaces);

    if (self.sublayers) |sublayers| {
        if (layer_inputs.len == sublayers.len) {
            for (1..layer_inputs.len) |ilevel| {
                // UNITS:
                //   `path_length_cm` is converted back to kilometers before it
                //   is used as the RTM quadrature weight.
                const sublayer = sublayers[ilevel];
                const scattering_optical_depth = @max(layer_inputs[ilevel].scattering_optical_depth, 0.0);
                const rtm_weight = @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
                source_interfaces[ilevel] = .{
                    .source_weight = 0.0,
                    .rtm_weight = rtm_weight,
                    .ksca_above = if (rtm_weight > 0.0)
                        scattering_optical_depth / rtm_weight
                    else
                        0.0,
                    .phase_coefficients_above = layer_inputs[ilevel].phase_coefficients,
                };
            }
            return;
        }

        if (layer_inputs.len == 1) {
            return;
        }

        if (self.layers.len != layer_inputs.len) return;
        for (1..layer_inputs.len) |ilevel| {
            const layer = self.layers[ilevel];
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const sublayer_count: usize = @intCast(layer.sublayer_count);
            if (sublayer_count == 0) {
                source_interfaces[ilevel] = .{
                    .source_weight = 0.0,
                    .phase_coefficients_above = layer_inputs[ilevel].phase_coefficients,
                };
                continue;
            }
            const stop_index = start_index + sublayer_count;
            var rtm_weight: f64 = 0.0;
            for (sublayers[start_index..stop_index]) |sublayer| {
                rtm_weight += @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
            }
            const scattering_optical_depth = @max(layer_inputs[ilevel].scattering_optical_depth, 0.0);
            source_interfaces[ilevel] = .{
                .source_weight = 0.0,
                .rtm_weight = rtm_weight,
                .ksca_above = if (rtm_weight > 0.0)
                    scattering_optical_depth / rtm_weight
                else
                    0.0,
                .phase_coefficients_above = layer_inputs[ilevel].phase_coefficients,
            };
        }
        return;
    }
}

fn levelAltitudeFromSublayers(
    sublayers: []const PreparedSublayer,
    level: usize,
) f64 {
    if (sublayers.len == 0) return 0.0;
    if (level == 0) {
        const first = sublayers[0];
        return @max(first.altitude_km - 0.5 * first.path_length_cm / centimeters_per_kilometer, 0.0);
    }
    if (level >= sublayers.len) {
        const last = sublayers[sublayers.len - 1];
        return @max(last.altitude_km + 0.5 * last.path_length_cm / centimeters_per_kilometer, 0.0);
    }
    const sample = sublayers[level];
    return @max(sample.altitude_km - 0.5 * sample.path_length_cm / centimeters_per_kilometer, 0.0);
}

const PreparedQuadratureCarrier = struct {
    ksca: f64,
    phase_coefficients: [phase_coefficient_count]f64,
};

const PseudoSphericalInterval = struct {
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState = null,
    lower_altitude_km: f64,
    upper_altitude_km: f64,
};

const InterpolatedQuadratureState = struct {
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    absorber_number_density_cm3: f64,
    aerosol_optical_depth_per_km: f64,
    cloud_optical_depth_per_km: f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_phase_coefficients: [phase_coefficient_count]f64,
    cloud_phase_coefficients: [phase_coefficient_count]f64,
};

fn opticalDepthPerKilometer(
    optical_depth: f64,
    path_length_cm: f64,
) f64 {
    const span_km = @max(path_length_cm / centimeters_per_kilometer, 0.0);
    return if (span_km > 0.0) optical_depth / span_km else 0.0;
}

fn interpolatePhaseCoefficientsByScattering(
    left_scattering_per_km: f64,
    right_scattering_per_km: f64,
    left_phase_coefficients: [phase_coefficient_count]f64,
    right_phase_coefficients: [phase_coefficient_count]f64,
    fraction: f64,
) [phase_coefficient_count]f64 {
    const left_weight = 1.0 - fraction;
    const right_weight = fraction;
    const interpolated_scattering_per_km =
        left_weight * left_scattering_per_km +
        right_weight * right_scattering_per_km;

    var coefficients = [_]f64{0.0} ** phase_coefficient_count;
    coefficients[0] = 1.0;
    for (1..phase_coefficient_count) |index| {
        if (interpolated_scattering_per_km > 0.0) {
            coefficients[index] =
                (left_weight * left_scattering_per_km * left_phase_coefficients[index] +
                    right_weight * right_scattering_per_km * right_phase_coefficients[index]) /
                interpolated_scattering_per_km;
        } else {
            coefficients[index] =
                left_weight * left_phase_coefficients[index] +
                right_weight * right_phase_coefficients[index];
        }
    }
    return coefficients;
}

fn interpolateQuadratureStateBetweenSublayers(
    left: PreparedSublayer,
    right: PreparedSublayer,
    altitude_km: f64,
) InterpolatedQuadratureState {
    const interpolation_span_km = right.altitude_km - left.altitude_km;
    const fraction = if (interpolation_span_km > 0.0)
        (altitude_km - left.altitude_km) / interpolation_span_km
    else
        0.0;
    const clamped_fraction = std.math.clamp(fraction, 0.0, 1.0);
    const left_weight = 1.0 - fraction;
    const right_weight = fraction;

    const left_aerosol_per_km = opticalDepthPerKilometer(left.aerosol_optical_depth, left.path_length_cm);
    const right_aerosol_per_km = opticalDepthPerKilometer(right.aerosol_optical_depth, right.path_length_cm);
    const left_cloud_per_km = opticalDepthPerKilometer(left.cloud_optical_depth, left.path_length_cm);
    const right_cloud_per_km = opticalDepthPerKilometer(right.cloud_optical_depth, right.path_length_cm);
    const left_aerosol_scattering_per_km = left_aerosol_per_km * left.aerosol_single_scatter_albedo;
    const right_aerosol_scattering_per_km = right_aerosol_per_km * right.aerosol_single_scatter_albedo;
    const left_cloud_scattering_per_km = left_cloud_per_km * left.cloud_single_scatter_albedo;
    const right_cloud_scattering_per_km = right_cloud_per_km * right.cloud_single_scatter_albedo;

    return .{
        .pressure_hpa = @max(left_weight * left.pressure_hpa + right_weight * right.pressure_hpa, 0.0),
        .temperature_k = @max(left_weight * left.temperature_k + right_weight * right.temperature_k, 0.0),
        .number_density_cm3 = @max(left_weight * left.number_density_cm3 + right_weight * right.number_density_cm3, 0.0),
        .oxygen_number_density_cm3 = @max(left_weight * left.oxygen_number_density_cm3 + right_weight * right.oxygen_number_density_cm3, 0.0),
        .absorber_number_density_cm3 = @max(left_weight * left.absorber_number_density_cm3 + right_weight * right.absorber_number_density_cm3, 0.0),
        .aerosol_optical_depth_per_km = @max(left_weight * left_aerosol_per_km + right_weight * right_aerosol_per_km, 0.0),
        .cloud_optical_depth_per_km = @max(left_weight * left_cloud_per_km + right_weight * right_cloud_per_km, 0.0),
        .aerosol_single_scatter_albedo = std.math.clamp(
            left_weight * left.aerosol_single_scatter_albedo + right_weight * right.aerosol_single_scatter_albedo,
            0.0,
            1.0,
        ),
        .cloud_single_scatter_albedo = std.math.clamp(
            left_weight * left.cloud_single_scatter_albedo + right_weight * right.cloud_single_scatter_albedo,
            0.0,
            1.0,
        ),
        .aerosol_phase_coefficients = interpolatePhaseCoefficientsByScattering(
            left_aerosol_scattering_per_km,
            right_aerosol_scattering_per_km,
            left.aerosol_phase_coefficients,
            right.aerosol_phase_coefficients,
            clamped_fraction,
        ),
        .cloud_phase_coefficients = interpolatePhaseCoefficientsByScattering(
            left_cloud_scattering_per_km,
            right_cloud_scattering_per_km,
            left.cloud_phase_coefficients,
            right.cloud_phase_coefficients,
            clamped_fraction,
        ),
    };
}

fn interpolateQuadratureStateAtAltitude(
    sublayers: []const PreparedSublayer,
    altitude_km: f64,
) ?InterpolatedQuadratureState {
    if (sublayers.len == 0) return null;

    if (sublayers.len == 1) {
        const sublayer = sublayers[0];
        return .{
            .pressure_hpa = sublayer.pressure_hpa,
            .temperature_k = sublayer.temperature_k,
            .number_density_cm3 = sublayer.number_density_cm3,
            .oxygen_number_density_cm3 = sublayer.oxygen_number_density_cm3,
            .absorber_number_density_cm3 = sublayer.absorber_number_density_cm3,
            .aerosol_optical_depth_per_km = opticalDepthPerKilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
            .cloud_optical_depth_per_km = opticalDepthPerKilometer(sublayer.cloud_optical_depth, sublayer.path_length_cm),
            .aerosol_single_scatter_albedo = sublayer.aerosol_single_scatter_albedo,
            .cloud_single_scatter_albedo = sublayer.cloud_single_scatter_albedo,
            .aerosol_phase_coefficients = sublayer.aerosol_phase_coefficients,
            .cloud_phase_coefficients = sublayer.cloud_phase_coefficients,
        };
    }

    const first = sublayers[0];
    const last = sublayers[sublayers.len - 1];
    if (altitude_km <= first.altitude_km) {
        return interpolateQuadratureStateBetweenSublayers(first, sublayers[1], altitude_km);
    }
    if (altitude_km >= last.altitude_km) {
        return interpolateQuadratureStateBetweenSublayers(sublayers[sublayers.len - 2], last, altitude_km);
    }
    for (sublayers[0 .. sublayers.len - 1], sublayers[1..]) |left, right| {
        if (altitude_km > right.altitude_km) continue;
        return interpolateQuadratureStateBetweenSublayers(left, right, altitude_km);
    }

    return null;
}

fn quadratureCarrierAtAltitude(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
) PreparedQuadratureCarrier {
    const carrier = sharedOpticalCarrierAtAltitude(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        altitude_km,
    );
    return .{
        .ksca = carrier.totalScatteringOpticalDepthPerKm(),
        .phase_coefficients = carrier.phase_coefficients,
    };
}

fn sharedOpticalCarrierAtAltitude(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
) SharedOpticalCarrier {
    const state = interpolateQuadratureStateAtAltitude(sublayers, altitude_km) orelse return .{};
    const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };
    const continuum_sigma = if (self.cross_section_absorbers.len == 0)
        continuum_table.interpolateSigma(wavelength_nm)
    else
        0.0;
    const prepared_state = State.PreparedOpticalState.preparedStrongLineStateAtAltitude(
        sublayers,
        strong_line_states,
        altitude_km,
    );
    const spectroscopy_sigma = if (self.line_absorbers.len != 0)
        self.weightedSpectroscopyEvaluationAtAltitude(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
            sublayers,
            altitude_km,
            state.oxygen_number_density_cm3,
        ).total_sigma_cm2_per_molecule
    else
        self.spectroscopySigmaAtWavelength(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
            prepared_state,
        );
    var cross_section_density_cm3: f64 = 0.0;
    var cross_section_absorption_optical_depth_per_km: f64 = 0.0;
    for (self.cross_section_absorbers) |cross_section_absorber| {
        const absorber_density_cm3 = State.PreparedOpticalState.interpolatePreparedScalarAtAltitude(
            sublayers,
            cross_section_absorber.number_densities_cm3,
            altitude_km,
        );
        if (absorber_density_cm3 <= 0.0) continue;
        cross_section_density_cm3 += absorber_density_cm3;
        cross_section_absorption_optical_depth_per_km +=
            cross_section_absorber.sigmaAt(
                wavelength_nm,
                state.temperature_k,
                state.pressure_hpa,
            ) *
            absorber_density_cm3 *
            centimeters_per_kilometer;
    }
    const line_absorber_density_cm3 = self.lineSpectroscopyCarrierDensity(
        state.absorber_number_density_cm3,
        state.oxygen_number_density_cm3,
        cross_section_density_cm3,
    );
    const continuum_density_cm3 = if (self.cross_section_absorbers.len == 0)
        self.continuumCarrierDensityAtAltitude(
            sublayers,
            altitude_km,
            state.absorber_number_density_cm3,
            state.oxygen_number_density_cm3,
        )
    else
        0.0;
    const gas_absorption_optical_depth_per_km =
        continuum_sigma *
        continuum_density_cm3 *
        centimeters_per_kilometer +
        cross_section_absorption_optical_depth_per_km +
        spectroscopy_sigma *
            line_absorber_density_cm3 *
            centimeters_per_kilometer;
    const gas_scattering_optical_depth_per_km =
        Rayleigh.crossSectionCm2(wavelength_nm) *
        state.number_density_cm3 *
        centimeters_per_kilometer;
    const cia_optical_depth_per_km =
        self.ciaSigmaAtWavelength(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
        ) *
        state.oxygen_number_density_cm3 *
        state.oxygen_number_density_cm3 *
        centimeters_per_kilometer;
    const aerosol_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        state.aerosol_optical_depth_per_km,
        self.aerosol_reference_wavelength_nm,
        self.aerosol_angstrom_exponent,
        wavelength_nm,
    );
    const cloud_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        state.cloud_optical_depth_per_km,
        self.cloud_reference_wavelength_nm,
        self.cloud_angstrom_exponent,
        wavelength_nm,
    );
    const aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * state.aerosol_single_scatter_albedo;
    const cloud_scattering_optical_depth_per_km =
        cloud_optical_depth_per_km * state.cloud_single_scatter_albedo;

    return .{
        .gas_absorption_optical_depth_per_km = gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
        .cloud_optical_depth_per_km = cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = cloud_scattering_optical_depth_per_km,
        .phase_coefficients = PhaseFunctions.combinePhaseCoefficients(
            gas_scattering_optical_depth_per_km,
            aerosol_scattering_optical_depth_per_km,
            cloud_scattering_optical_depth_per_km,
            state.aerosol_phase_coefficients,
            state.cloud_phase_coefficients,
        ),
    };
}

/// Purpose:
///   Materialize RTM quadrature levels at one wavelength.
pub fn fillRtmQuadratureAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
) bool {
    const sublayers = self.sublayers orelse return false;
    if (layer_inputs.len != sublayers.len or rtm_levels.len != layer_inputs.len + 1) return false;

    if (usesSharedRtmGrid(self, layer_inputs.len)) {
        if (cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
            var has_active_quadrature = false;
            for (rtm_levels, geometry.levels) |*rtm_level, level_geometry| {
                const support_start_index: usize = @intCast(level_geometry.support_start_index);
                const support_count: usize = @intCast(level_geometry.support_count);
                const support = sharedSupportSlices(
                    self,
                    sublayers,
                    support_start_index,
                    support_count,
                );
                const carrier = sharedOpticalCarrierAtAltitude(
                    self,
                    wavelength_nm,
                    support.sublayers,
                    support.strong_line_states,
                    level_geometry.altitude_km,
                );
                const ksca = if (level_geometry.weight_km > 0.0)
                    carrier.totalScatteringOpticalDepthPerKm()
                else
                    0.0;
                rtm_level.* = .{
                    .altitude_km = level_geometry.altitude_km,
                    .weight = level_geometry.weight_km,
                    .ksca = ksca,
                    .phase_coefficients = carrier.phase_coefficients,
                };
                has_active_quadrature = has_active_quadrature or
                    (level_geometry.weight_km > 0.0 and ksca > 0.0);
            }
            return has_active_quadrature;
        }

        for (rtm_levels) |*rtm_level| {
            rtm_level.* = .{
                .altitude_km = 0.0,
                .weight = 0.0,
                .ksca = 0.0,
                .phase_coefficients = PhaseFunctions.zeroPhaseCoefficients(),
            };
        }

        var has_active_quadrature = false;
        var interval_rule_scratch: GaussRuleScratch = .{};
        for (self.layers) |layer| {
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const count: usize = @intCast(layer.sublayer_count);
            if (count == 0) continue;

            const interval = sharedRtmInterval(self, sublayers, layer);
            const level_node_count = count - 1;
            const level_rule = if (level_node_count > 0)
                resolveGaussRule(level_node_count, &interval_rule_scratch)
            else
                null;

            const lower_carrier = sharedOpticalCarrierAtAltitude(
                self,
                wavelength_nm,
                interval.support_sublayers,
                interval.strong_line_states,
                interval.lower_altitude_km,
            );
            rtm_levels[start_index] = .{
                .altitude_km = interval.lower_altitude_km,
                .weight = 0.0,
                .ksca = 0.0,
                .phase_coefficients = lower_carrier.phase_coefficients,
            };

            for (0..level_node_count) |node_index| {
                const altitude_km = intervalAltitudeAtNode(
                    interval.lower_altitude_km,
                    interval.upper_altitude_km,
                    level_rule.?.nodes[node_index],
                );
                const weight_km = intervalWeightKm(
                    interval.lower_altitude_km,
                    interval.upper_altitude_km,
                    level_rule.?.weights[node_index],
                );
                const carrier = sharedOpticalCarrierAtAltitude(
                    self,
                    wavelength_nm,
                    interval.support_sublayers,
                    interval.strong_line_states,
                    altitude_km,
                );
                rtm_levels[start_index + 1 + node_index] = .{
                    .altitude_km = altitude_km,
                    .weight = weight_km,
                    .ksca = carrier.totalScatteringOpticalDepthPerKm(),
                    .phase_coefficients = carrier.phase_coefficients,
                };
                has_active_quadrature = has_active_quadrature or weight_km > 0.0 and carrier.totalScatteringOpticalDepthPerKm() > 0.0;
            }

            const stop_index = start_index + count;
            const upper_carrier = sharedOpticalCarrierAtAltitude(
                self,
                wavelength_nm,
                interval.support_sublayers,
                interval.strong_line_states,
                interval.upper_altitude_km,
            );
            rtm_levels[stop_index] = .{
                .altitude_km = interval.upper_altitude_km,
                .weight = 0.0,
                .ksca = 0.0,
                .phase_coefficients = upper_carrier.phase_coefficients,
            };
        }

        return has_active_quadrature;
    }

    for (rtm_levels, 0..) |*rtm_level, level| {
        rtm_level.* = .{
            .altitude_km = levelAltitudeFromSublayers(sublayers, level),
            .weight = 0.0,
            .ksca = 0.0,
            .phase_coefficients = PhaseFunctions.zeroPhaseCoefficients(),
        };
    }

    var has_active_quadrature = false;
    for (self.layers) |layer| {
        const start: usize = @intCast(layer.sublayer_start_index);
        const count: usize = @intCast(layer.sublayer_count);
        if (count == 0) continue;
        const stop = start + count;
        if (stop >= rtm_levels.len) return false;

        const active_count = if (count > 0) count - 1 else 0;
        if (active_count == 0) continue;
        const rule = gauss_legendre.rule(@intCast(active_count)) catch return false;
        const lower_altitude_km = rtm_levels[start].altitude_km;
        const upper_altitude_km = rtm_levels[stop].altitude_km;
        const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);

        var total_span_km: f64 = 0.0;
        var total_scattering: f64 = 0.0;
        for (sublayers[start..stop], layer_inputs[start..stop]) |sublayer, layer_input| {
            total_span_km += @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
            total_scattering += @max(layer_input.scattering_optical_depth, 0.0);
        }
        if (total_span_km <= 0.0) continue;

        // DECISION:
        //   Quadrature nodes are normalized to the layer span, then the
        //   scattering weights are renormalized back to the transport grid.
        var raw_scattering_sum: f64 = 0.0;
        for (0..active_count) |node_index| {
            const level = start + 1 + node_index;
            const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
            const node_altitude_km = lower_altitude_km + normalized_position * altitude_span_km;
            const carrier = quadratureCarrierAtAltitude(
                self,
                wavelength_nm,
                sublayers[start..stop],
                if (self.strong_line_states) |states| states[start..stop] else null,
                node_altitude_km,
            );
            rtm_levels[level].altitude_km = node_altitude_km;
            rtm_levels[level].weight = 0.5 * rule.weights[node_index] * total_span_km;
            rtm_levels[level].ksca = carrier.ksca;
            rtm_levels[level].phase_coefficients = carrier.phase_coefficients;
            raw_scattering_sum += rtm_levels[level].weightedScattering();
        }

        if (total_scattering <= 0.0) {
            for (start + 1..stop) |level| {
                rtm_levels[level].ksca = 0.0;
            }
            continue;
        }

        if (raw_scattering_sum > 0.0) {
            const scale = total_scattering / raw_scattering_sum;
            for (start + 1..stop) |level| {
                rtm_levels[level].ksca *= scale;
            }
            has_active_quadrature = true;
        } else {
            for (start + 1..stop) |level| {
                rtm_levels[level].weight = 0.0;
                rtm_levels[level].ksca = 0.0;
            }
        }
    }

    return has_active_quadrature;
}

/// Purpose:
///   Materialize pseudo-spherical samples from already prepared shared-grid
///   layer inputs.
///
/// Physics:
///   Reuses the explicit shared-grid layer optical depths so the
///   pseudo-spherical attenuation path does not re-evaluate the same midpoint
///   carriers that already define the transport layers.
///
/// Vendor:
///   `pseudo-spherical attenuation on the shared RTM grid`
///
/// Validation:
///   Shared-grid measurement-space tests and O2A forward profiles.
pub fn fillSharedPseudoSphericalGridFromLayerInputs(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    layer_inputs: []const transport_common.LayerInput,
    attenuation_layers: []transport_common.LayerInput,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
) bool {
    const geometry = cachedSharedRtmGeometry(self, layer_inputs.len) orelse return false;
    const subgrid_divisions = @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
    const sample_count = layer_inputs.len * subgrid_divisions;
    if (attenuation_samples.len < sample_count or
        level_sample_starts.len != layer_inputs.len + 1 or
        level_altitudes_km.len != layer_inputs.len + 1)
    {
        return false;
    }

    for (level_altitudes_km, geometry.levels) |*altitude_km, level_geometry| {
        altitude_km.* = level_geometry.altitude_km;
    }

    var sample_index: usize = 0;
    for (geometry.layers, layer_inputs, 0..) |layer_geometry, layer_input, layer_index| {
        level_sample_starts[layer_index] = sample_index;
        if (subgrid_divisions <= 1) {
            attenuation_samples[sample_index] = .{
                .altitude_km = layer_geometry.midpoint_altitude_km,
                .thickness_km = layer_geometry.thickness_km,
                .optical_depth = layer_input.optical_depth,
            };
            if (sample_index < attenuation_layers.len) {
                attenuation_layers[sample_index] = .{ .optical_depth = layer_input.optical_depth };
            }
            sample_index += 1;
            continue;
        }

        attenuation_samples[sample_index] = .{
            .altitude_km = layer_geometry.lower_altitude_km,
            .thickness_km = 0.0,
            .optical_depth = 0.0,
        };
        if (sample_index < attenuation_layers.len) attenuation_layers[sample_index] = .{};
        sample_index += 1;

        attenuation_samples[sample_index] = .{
            .altitude_km = layer_geometry.midpoint_altitude_km,
            .thickness_km = layer_geometry.thickness_km,
            .optical_depth = layer_input.optical_depth,
        };
        if (sample_index < attenuation_layers.len) {
            attenuation_layers[sample_index] = .{ .optical_depth = layer_input.optical_depth };
        }
        sample_index += 1;

        for (2..subgrid_divisions) |_| {
            attenuation_samples[sample_index] = .{
                .altitude_km = layer_geometry.upper_altitude_km,
                .thickness_km = 0.0,
                .optical_depth = 0.0,
            };
            if (sample_index < attenuation_layers.len) attenuation_layers[sample_index] = .{};
            sample_index += 1;
        }
    }

    level_sample_starts[layer_inputs.len] = sample_index;
    return true;
}

/// Purpose:
///   Materialize pseudo-spherical samples at one wavelength.
pub fn fillPseudoSphericalGridAtWavelength(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    solver_layer_count: usize,
    attenuation_layers: []transport_common.LayerInput,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
) bool {
    const sublayers = self.sublayers orelse return false;
    const subgrid_divisions = @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
    const sample_count = solver_layer_count * subgrid_divisions;
    if (attenuation_samples.len < sample_count or
        level_sample_starts.len != solver_layer_count + 1 or
        level_altitudes_km.len != solver_layer_count + 1)
    {
        return false;
    }

    if (solver_layer_count != sublayers.len and solver_layer_count != self.layers.len) {
        return false;
    }

    if (usesSharedRtmGrid(self, solver_layer_count)) {
        if (cachedSharedRtmGeometry(self, solver_layer_count)) |geometry| {
            for (level_altitudes_km, geometry.levels) |*altitude_km, level_geometry| {
                altitude_km.* = level_geometry.altitude_km;
            }

            var sample_index: usize = 0;
            var subgrid_rule_scratch: GaussRuleScratch = .{};
            for (geometry.layers, 0..) |layer_geometry, layer_index| {
                level_sample_starts[layer_index] = sample_index;
                const support_start_index: usize = @intCast(layer_geometry.support_start_index);
                const support_count: usize = @intCast(layer_geometry.support_count);
                const support = sharedSupportSlices(
                    self,
                    sublayers,
                    support_start_index,
                    support_count,
                );
                sample_index = fillSharedPseudoSphericalSamplesOnSubgrid(
                    self,
                    scene,
                    wavelength_nm,
                    support.sublayers,
                    support.strong_line_states,
                    layer_geometry,
                    attenuation_layers,
                    attenuation_samples,
                    sample_index,
                    &subgrid_rule_scratch,
                );
            }

            level_sample_starts[solver_layer_count] = sample_index;
            return true;
        }

        var sample_index: usize = 0;
        var interval_rule_scratch: GaussRuleScratch = .{};
        var subgrid_rule_scratch: GaussRuleScratch = .{};

        for (self.layers) |layer| {
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const count: usize = @intCast(layer.sublayer_count);
            if (count == 0) return false;

            const interval = sharedRtmInterval(self, sublayers, layer);
            const level_node_count = count - 1;
            const level_rule = if (level_node_count > 0)
                resolveGaussRule(level_node_count, &interval_rule_scratch)
            else
                null;

            level_altitudes_km[start_index] = interval.lower_altitude_km;

            for (0..count) |local_layer_index| {
                const lower_altitude_km = if (local_layer_index == 0)
                    interval.lower_altitude_km
                else
                    intervalAltitudeAtNode(
                        interval.lower_altitude_km,
                        interval.upper_altitude_km,
                        level_rule.?.nodes[local_layer_index - 1],
                    );
                const upper_altitude_km = if (local_layer_index + 1 == count)
                    interval.upper_altitude_km
                else
                    intervalAltitudeAtNode(
                        interval.lower_altitude_km,
                        interval.upper_altitude_km,
                        level_rule.?.nodes[local_layer_index],
                    );
                const global_layer_index = start_index + local_layer_index;
                level_sample_starts[global_layer_index] = sample_index;
                level_altitudes_km[global_layer_index + 1] = upper_altitude_km;
                sample_index = fillSharedPseudoSphericalSamplesOnSubgrid(
                    self,
                    scene,
                    wavelength_nm,
                    interval.support_sublayers,
                    interval.strong_line_states,
                    .{
                        .lower_altitude_km = lower_altitude_km,
                        .upper_altitude_km = upper_altitude_km,
                        .midpoint_altitude_km = 0.5 * (lower_altitude_km + upper_altitude_km),
                        .thickness_km = @max(upper_altitude_km - lower_altitude_km, 0.0),
                        .support_start_index = @intCast(start_index),
                        .support_count = @intCast(count),
                    },
                    attenuation_layers,
                    attenuation_samples,
                    sample_index,
                    &subgrid_rule_scratch,
                );
            }
        }

        level_sample_starts[solver_layer_count] = sample_index;
        return true;
    }

    var sample_index: usize = 0;
    if (solver_layer_count == sublayers.len) {
        level_altitudes_km[0] = levelAltitudeFromSublayers(sublayers, 0);
        for (1..solver_layer_count + 1) |ilevel| {
            level_altitudes_km[ilevel] = levelAltitudeFromSublayers(sublayers, ilevel);
        }
    } else {
        level_altitudes_km[0] = levelAltitudeFromSublayers(sublayers, 0);
        for (1..solver_layer_count) |ilevel| {
            const start_index: usize = @intCast(self.layers[ilevel].sublayer_start_index);
            level_altitudes_km[ilevel] = levelAltitudeFromSublayers(sublayers, start_index);
        }
        level_altitudes_km[solver_layer_count] = levelAltitudeFromSublayers(sublayers, sublayers.len);
    }

    for (0..solver_layer_count) |solver_level| {
        const interval = if (solver_layer_count == sublayers.len)
            PseudoSphericalInterval{
                .support_sublayers = sublayers[solver_level .. solver_level + 1],
                .strong_line_states = if (self.strong_line_states) |states|
                    states[solver_level .. solver_level + 1]
                else
                    null,
                .lower_altitude_km = levelAltitudeFromSublayers(sublayers, solver_level),
                .upper_altitude_km = levelAltitudeFromSublayers(sublayers, solver_level + 1),
            }
        else blk: {
            const layer = self.layers[solver_level];
            const start: usize = @intCast(layer.sublayer_start_index);
            const count: usize = @intCast(layer.sublayer_count);
            if (count == 0) return false;
            const stop = start + count;
            break :blk PseudoSphericalInterval{
                .support_sublayers = sublayers[start..stop],
                .strong_line_states = if (self.strong_line_states) |states|
                    states[start..stop]
                else
                    null,
                .lower_altitude_km = levelAltitudeFromSublayers(sublayers, start),
                .upper_altitude_km = levelAltitudeFromSublayers(sublayers, stop),
            };
        };
        const altitude_span_km = @max(interval.upper_altitude_km - interval.lower_altitude_km, 0.0);
        const active_count = subgrid_divisions - 1;

        level_sample_starts[solver_level] = sample_index;
        if (active_count == 0) {
            const sample_altitude_km = if (altitude_span_km > 0.0)
                interval.lower_altitude_km + 0.5 * altitude_span_km
            else
                interval.lower_altitude_km;
            const optical_depth = sharedOpticalCarrierAtAltitude(
                self,
                wavelength_nm,
                interval.support_sublayers,
                interval.strong_line_states,
                sample_altitude_km,
            ).totalOpticalDepthPerKm() * altitude_span_km;
            attenuation_samples[sample_index] = .{
                .altitude_km = sample_altitude_km,
                .thickness_km = altitude_span_km,
                .optical_depth = optical_depth,
            };
            if (sample_index < attenuation_layers.len) {
                attenuation_layers[sample_index] = .{ .optical_depth = optical_depth };
            }
            sample_index += 1;
            continue;
        }

        attenuation_samples[sample_index] = .{
            .altitude_km = interval.lower_altitude_km,
            .thickness_km = 0.0,
            .optical_depth = 0.0,
        };
        // Keep the retained layer scratch deterministic even though the
        // pseudo-spherical contract is carried by the sample grid below.
        if (sample_index < attenuation_layers.len) {
            attenuation_layers[sample_index] = .{};
        }
        sample_index += 1;

        if (altitude_span_km <= 0.0) {
            for (0..active_count) |_| {
                attenuation_samples[sample_index] = .{
                    .altitude_km = interval.lower_altitude_km,
                    .thickness_km = 0.0,
                    .optical_depth = 0.0,
                };
                if (sample_index < attenuation_layers.len) {
                    attenuation_layers[sample_index] = .{};
                }
                sample_index += 1;
            }
            continue;
        }

        const rule = gauss_legendre.rule(@intCast(active_count)) catch return false;
        for (0..active_count) |node_index| {
            const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
            const node_altitude_km = interval.lower_altitude_km + normalized_position * altitude_span_km;
            const weight_km = 0.5 * rule.weights[node_index] * altitude_span_km;
            const optical_depth = sharedOpticalCarrierAtAltitude(
                self,
                wavelength_nm,
                interval.support_sublayers,
                interval.strong_line_states,
                node_altitude_km,
            ).totalOpticalDepthPerKm() * weight_km;
            attenuation_samples[sample_index] = .{
                .altitude_km = node_altitude_km,
                .thickness_km = weight_km,
                .optical_depth = optical_depth,
            };
            if (sample_index < attenuation_layers.len) {
                attenuation_layers[sample_index] = .{ .optical_depth = optical_depth };
            }
            sample_index += 1;
        }
    }

    level_sample_starts[solver_layer_count] = sample_index;
    return true;
}
