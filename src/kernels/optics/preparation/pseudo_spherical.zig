const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const gauss_legendre = @import("../../quadrature/gauss_legendre.zig");
const transport_common = @import("../../transport/common.zig");
const State = @import("state.zig");
const shared_geometry = @import("shared_geometry.zig");
const shared_carrier = @import("shared_carrier.zig");
const carrier_eval = @import("carrier_eval.zig");

const PreparedOpticalState = State.PreparedOpticalState;

const PseudoSphericalInterval = struct {
    support_sublayers: []const State.PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState = null,
    lower_altitude_km: f64,
    upper_altitude_km: f64,
};

pub fn fillSharedPseudoSphericalGridFromLayerInputs(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    layer_inputs: []const transport_common.LayerInput,
    attenuation_layers: []transport_common.LayerInput,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
) bool {
    const geometry = shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len) orelse return false;
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

    if (shared_geometry.usesSharedRtmGrid(self, solver_layer_count)) {
        if (shared_geometry.cachedSharedRtmGeometry(self, solver_layer_count)) |geometry| {
            for (level_altitudes_km, geometry.levels) |*altitude_km, level_geometry| {
                altitude_km.* = level_geometry.altitude_km;
            }

            var sample_index: usize = 0;
            var subgrid_rule_scratch: shared_geometry.GaussRuleScratch = .{};
            for (geometry.layers, 0..) |layer_geometry, layer_index| {
                level_sample_starts[layer_index] = sample_index;
                const support_start_index: usize = @intCast(layer_geometry.support_start_index);
                const support_count: usize = @intCast(layer_geometry.support_count);
                const support = shared_geometry.sharedSupportSlices(
                    self,
                    sublayers,
                    support_start_index,
                    support_count,
                );
                sample_index = shared_carrier.fillSharedPseudoSphericalSamplesOnSubgrid(
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
        var interval_rule_scratch: shared_geometry.GaussRuleScratch = .{};
        var subgrid_rule_scratch: shared_geometry.GaussRuleScratch = .{};

        for (self.layers) |layer| {
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const count: usize = @intCast(layer.sublayer_count);
            if (count == 0) return false;

            const interval = shared_geometry.sharedRtmInterval(self, sublayers, layer);
            const level_node_count = count - 1;
            const level_rule = if (level_node_count > 0)
                shared_geometry.resolveGaussRule(level_node_count, &interval_rule_scratch)
            else
                null;

            level_altitudes_km[start_index] = interval.lower_altitude_km;

            for (0..count) |local_layer_index| {
                const lower_altitude_km = if (local_layer_index == 0)
                    interval.lower_altitude_km
                else
                    shared_geometry.intervalAltitudeAtNode(
                        interval.lower_altitude_km,
                        interval.upper_altitude_km,
                        level_rule.?.nodes[local_layer_index - 1],
                    );
                const upper_altitude_km = if (local_layer_index + 1 == count)
                    interval.upper_altitude_km
                else
                    shared_geometry.intervalAltitudeAtNode(
                        interval.lower_altitude_km,
                        interval.upper_altitude_km,
                        level_rule.?.nodes[local_layer_index],
                    );
                const global_layer_index = start_index + local_layer_index;
                level_sample_starts[global_layer_index] = sample_index;
                level_altitudes_km[global_layer_index + 1] = upper_altitude_km;
                sample_index = shared_carrier.fillSharedPseudoSphericalSamplesOnSubgrid(
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
        level_altitudes_km[0] = shared_geometry.levelAltitudeFromSublayers(sublayers, 0);
        for (1..solver_layer_count + 1) |ilevel| {
            level_altitudes_km[ilevel] = shared_geometry.levelAltitudeFromSublayers(sublayers, ilevel);
        }
    } else {
        level_altitudes_km[0] = shared_geometry.levelAltitudeFromSublayers(sublayers, 0);
        for (1..solver_layer_count) |ilevel| {
            const start_index: usize = @intCast(self.layers[ilevel].sublayer_start_index);
            level_altitudes_km[ilevel] = shared_geometry.levelAltitudeFromSublayers(sublayers, start_index);
        }
        level_altitudes_km[solver_layer_count] = shared_geometry.levelAltitudeFromSublayers(sublayers, sublayers.len);
    }

    for (0..solver_layer_count) |solver_level| {
        const interval = if (solver_layer_count == sublayers.len)
            PseudoSphericalInterval{
                .support_sublayers = sublayers[solver_level .. solver_level + 1],
                .strong_line_states = if (self.strong_line_states) |states|
                    states[solver_level .. solver_level + 1]
                else
                    null,
                .lower_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, solver_level),
                .upper_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, solver_level + 1),
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
                .lower_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, start),
                .upper_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, stop),
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
            const optical_depth = carrier_eval.sharedOpticalCarrierAtAltitude(
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
            const optical_depth = carrier_eval.sharedOpticalCarrierAtAltitude(
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
