const transport_common = @import("../../transport/common.zig");
const State = @import("state.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");

const PreparedOpticalState = State.PreparedOpticalState;

pub fn fillSourceInterfacesAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
) void {
    if (layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1) return;

    if (self.sublayers) |sublayers| {
        if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
            if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                for (source_interfaces, geometry.levels) |*source_interface, level_geometry| {
                    const support_start_index: usize = @intCast(level_geometry.support_start_index);
                    const support_count: usize = @intCast(level_geometry.support_count);
                    const support = shared_geometry.sharedSupportSlices(
                        self,
                        sublayers,
                        support_start_index,
                        support_count,
                    );
                    const carrier = carrier_eval.sharedOpticalCarrierAtAltitude(
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

            var interval_rule_scratch: shared_geometry.GaussRuleScratch = .{};
            for (self.layers) |layer| {
                const start_index: usize = @intCast(layer.sublayer_start_index);
                const count: usize = @intCast(layer.sublayer_count);
                if (count == 0) continue;

                const interval = shared_geometry.sharedRtmInterval(self, sublayers, layer);
                const level_node_count = count - 1;
                const level_rule = if (level_node_count > 0)
                    shared_geometry.resolveGaussRule(level_node_count, &interval_rule_scratch)
                else
                    null;

                const lower_carrier = carrier_eval.sharedOpticalCarrierAtAltitude(
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
                    const altitude_km = shared_geometry.intervalAltitudeAtNode(
                        interval.lower_altitude_km,
                        interval.upper_altitude_km,
                        level_rule.?.nodes[node_index],
                    );
                    const weight_km = shared_geometry.intervalWeightKm(
                        interval.lower_altitude_km,
                        interval.upper_altitude_km,
                        level_rule.?.weights[node_index],
                    );
                    const carrier = carrier_eval.sharedOpticalCarrierAtAltitude(
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
                const upper_carrier = carrier_eval.sharedOpticalCarrierAtAltitude(
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
                const sublayer = sublayers[ilevel];
                const scattering_optical_depth = @max(layer_inputs[ilevel].scattering_optical_depth, 0.0);
                const rtm_weight = @max(sublayer.path_length_cm / 1.0e5, 0.0);
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
                rtm_weight += @max(sublayer.path_length_cm / 1.0e5, 0.0);
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
