const gauss_legendre = @import("../../quadrature/gauss_legendre.zig");
const transport_common = @import("../../transport/common.zig");
const State = @import("state.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");

const PreparedOpticalState = State.PreparedOpticalState;
const LevelCarrier = struct {
    ksca: f64,
    phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
};

pub fn fillRtmQuadratureAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
) bool {
    const sublayers = self.sublayers orelse return false;
    if (rtm_levels.len != layer_inputs.len + 1) return false;

    if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
        if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
            var has_active_quadrature = false;
            for (rtm_levels, geometry.levels) |*rtm_level, level_geometry| {
                const level_carrier: LevelCarrier = if (level_geometry.weight_km > 0.0) blk: {
                    const carrier = carrier_eval.sharedActiveCarrierAtLevel(
                        self,
                        wavelength_nm,
                        sublayers,
                        if (self.strong_line_states) |states| states else null,
                        level_geometry,
                    );
                    break :blk LevelCarrier{
                        .ksca = carrier.totalScatteringOpticalDepthPerKm(),
                        .phase_coefficients = carrier.phase_coefficients,
                    };
                } else blk: {
                    const boundary_carrier = carrier_eval.sharedBoundaryCarrierAtLevel(
                        self,
                        wavelength_nm,
                        sublayers,
                        if (self.strong_line_states) |states| states else null,
                        level_geometry,
                    );
                    break :blk LevelCarrier{
                        .ksca = boundary_carrier.ksca_above,
                        .phase_coefficients = boundary_carrier.phase_coefficients_above,
                    };
                };
                rtm_level.* = .{
                    .altitude_km = level_geometry.altitude_km,
                    .weight = level_geometry.weight_km,
                    .ksca = level_carrier.ksca,
                    .phase_coefficients = level_carrier.phase_coefficients,
                };
                has_active_quadrature = has_active_quadrature or
                    (level_geometry.weight_km > 0.0 and level_carrier.ksca > 0.0);
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

        return false;
    }

    if (layer_inputs.len != sublayers.len) return false;

    for (rtm_levels, 0..) |*rtm_level, level| {
        rtm_level.* = .{
            .altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, level),
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
            total_span_km += @max(sublayer.path_length_cm / 1.0e5, 0.0);
            total_scattering += @max(layer_input.scattering_optical_depth, 0.0);
        }
        if (total_span_km <= 0.0) continue;

        var raw_scattering_sum: f64 = 0.0;
        for (0..active_count) |node_index| {
            const level = start + 1 + node_index;
            const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
            const node_altitude_km = lower_altitude_km + normalized_position * altitude_span_km;
            const carrier = carrier_eval.quadratureCarrierAtAltitude(
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
