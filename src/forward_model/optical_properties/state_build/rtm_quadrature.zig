const std = @import("std");
const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");
const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedOpticalState = State.PreparedOpticalState;
const LevelCarrier = struct {
    ksca: f64,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),
    phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
};

fn fillAerosolSourceJacobian(
    self: *const PreparedOpticalState,
    rtm_level: *transport_common.RtmQuadratureLevel,
    aerosol_scattering_optical_depth_per_km: f64,
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
) void {
    if (self.aerosol_optical_depth <= 0.0 or aerosol_scattering_optical_depth_per_km <= 0.0) return;
    const state_index = transport_common.Jacobian.stateIndex(.aerosol_optical_depth);
    const derivative_scale = aerosol_scattering_optical_depth_per_km / self.aerosol_optical_depth;
    for (0..PhaseFunctions.phase_coefficient_count) |index| {
        rtm_level.ksca_phase_coefficient_jacobian[state_index][index] =
            derivative_scale * aerosol_phase_coefficients[index];
    }
}

fn scaledAerosolPhasePerKm(
    aerosol_scattering_optical_depth_per_km: f64,
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
) [PhaseFunctions.phase_coefficient_count]f64 {
    var scaled = PhaseFunctions.zeroPhaseCoefficients();
    if (aerosol_scattering_optical_depth_per_km <= 0.0) return scaled;
    for (0..PhaseFunctions.phase_coefficient_count) |index| {
        scaled[index] = aerosol_scattering_optical_depth_per_km * aerosol_phase_coefficients[index];
    }
    return scaled;
}

fn fillSharedAerosolSourceJacobianFromLayers(
    sublayers: []const State.PreparedSublayer,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
) void {
    const state_index = transport_common.Jacobian.stateIndex(.aerosol_optical_depth);
    var total_weight: f64 = 0.0;
    var total_scattering_derivative: f64 = 0.0;
    const phase_coefficients = blk: {
        for (sublayers) |sublayer| {
            if (sublayer.aerosol_optical_depth > 0.0) {
                break :blk sublayer.aerosol_phase_coefficients;
            }
        }
        break :blk PhaseFunctions.zeroPhaseCoefficients();
    };

    for (layer_inputs) |layer| {
        const derivative = transport_common.Jacobian.get(
            layer.scattering_optical_depth_jacobian,
            .aerosol_optical_depth,
        );
        if (derivative <= 0.0) continue;
        total_scattering_derivative += derivative;
    }
    if (total_scattering_derivative <= 0.0 or phase_coefficients[0] == 0.0) return;

    for (rtm_levels, 0..) |level, level_index| {
        if (level.weight <= 0.0) continue;
        const below_active = level_index > 0 and
            transport_common.Jacobian.get(
                layer_inputs[level_index - 1].scattering_optical_depth_jacobian,
                .aerosol_optical_depth,
            ) > 0.0;
        const above_active = level_index < layer_inputs.len and
            transport_common.Jacobian.get(
                layer_inputs[level_index].scattering_optical_depth_jacobian,
                .aerosol_optical_depth,
            ) > 0.0;
        if (below_active or above_active) total_weight += level.weight;
    }
    if (total_weight <= 0.0) return;

    const derivative_per_km = total_scattering_derivative / total_weight;
    for (rtm_levels, 0..) |*level, level_index| {
        if (level.weight <= 0.0) continue;
        const below_active = level_index > 0 and
            transport_common.Jacobian.get(
                layer_inputs[level_index - 1].scattering_optical_depth_jacobian,
                .aerosol_optical_depth,
            ) > 0.0;
        const above_active = level_index < layer_inputs.len and
            transport_common.Jacobian.get(
                layer_inputs[level_index].scattering_optical_depth_jacobian,
                .aerosol_optical_depth,
            ) > 0.0;
        if (!below_active and !above_active) continue;
        for (0..PhaseFunctions.phase_coefficient_count) |index| {
            level.ksca_phase_coefficient_jacobian[state_index][index] =
                derivative_per_km * phase_coefficients[index];
        }
    }
}

pub fn fillRtmQuadratureAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
) bool {
    var profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    return fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(
        self,
        wavelength_nm,
        layer_inputs,
        rtm_levels,
        &profile_cache,
    );
}

// hot path:
//   when: integrated source-function routes fill RTM quadrature without a wavelength carrier cache
//   work: evaluates boundary carriers, phase data, and aerosol source Jacobian rows at RTM levels
//   data: layer input array, shared RTM levels, profile spectroscopy cache, quadrature output
//   follow: sharedBoundaryCarrierAtLevelWithSpectroscopyCache and fillAerosolSourceJacobian
pub fn fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) bool {
    const sublayers = self.sublayers orelse return false;
    if (rtm_levels.len != layer_inputs.len + 1) return false;

    if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
        if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
            for (rtm_levels, geometry.levels) |*rtm_level, level_geometry| {
                const boundary_carrier = carrier_eval.sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
                    self,
                    wavelength_nm,
                    sublayers,
                    if (self.strong_line_states) |states| states else null,
                    level_geometry,
                    profile_cache,
                );
                const level_carrier = LevelCarrier{
                    .ksca = boundary_carrier.ksca_above,
                    .aerosol_scattering_optical_depth_per_km = boundary_carrier.aerosol_scattering_optical_depth_above_per_km,
                    .aerosol_phase_coefficients = boundary_carrier.aerosol_phase_coefficients_above,
                    .phase_coefficients = boundary_carrier.phase_coefficients_above,
                };
                rtm_level.* = .{
                    .altitude_km = level_geometry.altitude_km,
                    .weight = level_geometry.weight_km,
                    .ksca = level_carrier.ksca,
                    .phase_coefficients = level_carrier.phase_coefficients,
                    .aerosol_ksca_phase_above_per_km = scaledAerosolPhasePerKm(
                        boundary_carrier.aerosol_scattering_optical_depth_above_per_km,
                        boundary_carrier.aerosol_phase_coefficients_above,
                    ),
                    .aerosol_ksca_phase_below_per_km = scaledAerosolPhasePerKm(
                        boundary_carrier.aerosol_scattering_optical_depth_below_per_km,
                        boundary_carrier.aerosol_phase_coefficients_below,
                    ),
                };
                fillAerosolSourceJacobian(
                    self,
                    rtm_level,
                    level_carrier.aerosol_scattering_optical_depth_per_km,
                    level_carrier.aerosol_phase_coefficients,
                );
            }
            // PARITY:
            //   DISAMAR's integrated-source reflectance uses RTMweight(level)
            //   multiplied by the scattering carrier sampled at that coarse
            //   RTM level. The source quadrature is not renormalized back to
            //   the sublayer-integrated layer scattering totals.
            var has_active_quadrature = false;
            for (rtm_levels) |rtm_level| {
                if (rtm_level.weightedScattering() > 0.0) {
                    has_active_quadrature = true;
                    break;
                }
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
            const carrier = carrier_eval.quadratureCarrierAtAltitudeWithSpectroscopyCache(
                self,
                wavelength_nm,
                sublayers[start..stop],
                if (self.strong_line_states) |states| states[start..stop] else null,
                node_altitude_km,
                profile_cache,
            );
            rtm_levels[level].altitude_km = node_altitude_km;
            rtm_levels[level].weight = 0.5 * rule.weights[node_index] * total_span_km;
            rtm_levels[level].ksca = carrier.ksca;
            rtm_levels[level].phase_coefficients = carrier.phase_coefficients;
            rtm_levels[level].aerosol_ksca_phase_above_per_km = scaledAerosolPhasePerKm(
                carrier.aerosol_scattering_optical_depth_per_km,
                carrier.aerosol_phase_coefficients,
            );
            rtm_levels[level].aerosol_ksca_phase_below_per_km = rtm_levels[level].aerosol_ksca_phase_above_per_km;
            fillAerosolSourceJacobian(
                self,
                &rtm_levels[level],
                carrier.aerosol_scattering_optical_depth_per_km,
                carrier.aerosol_phase_coefficients,
            );
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
                for (&rtm_levels[level].aerosol_ksca_phase_above_per_km) |*value| value.* *= scale;
                for (&rtm_levels[level].aerosol_ksca_phase_below_per_km) |*value| value.* *= scale;
                for (&rtm_levels[level].ksca_phase_coefficient_jacobian) |*state_row| {
                    for (state_row) |*value| value.* *= scale;
                }
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

// hot path:
//   when: integrated source-function routes fill RTM quadrature for a cached wavelength solve
//   work: evaluates boundary carriers through WavelengthCarrierCache and writes RTM level rows
//   data: layer input array, shared RTM levels, carrier cache, quadrature output
//   follow: sharedBoundaryCarrierAtLevelWithCarrierCache and aerosol source Jacobian fields
pub fn fillRtmQuadratureAtWavelengthWithLayersAndCarrierCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
) bool {
    const sublayers = self.sublayers orelse return false;
    if (rtm_levels.len != layer_inputs.len + 1) return false;

    if (!shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
        return fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(
            self,
            wavelength_nm,
            layer_inputs,
            rtm_levels,
            wavelength_cache.profile_cache,
        );
    }

    const geometry = shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len) orelse {
        for (rtm_levels) |*rtm_level| {
            rtm_level.* = .{
                .altitude_km = 0.0,
                .weight = 0.0,
                .ksca = 0.0,
                .phase_coefficients = PhaseFunctions.zeroPhaseCoefficients(),
            };
        }
        return false;
    };

    for (rtm_levels, geometry.levels) |*rtm_level, level_geometry| {
        const boundary_carrier = carrier_eval.sharedBoundaryCarrierAtLevelWithCarrierCache(
            self,
            wavelength_nm,
            sublayers,
            if (self.strong_line_states) |states| states else null,
            level_geometry,
            wavelength_cache,
        );
        rtm_level.* = .{
            .altitude_km = level_geometry.altitude_km,
            .weight = level_geometry.weight_km,
            .ksca = boundary_carrier.ksca_above,
            .phase_coefficients = boundary_carrier.phase_coefficients_above,
            .aerosol_ksca_phase_above_per_km = scaledAerosolPhasePerKm(
                boundary_carrier.aerosol_scattering_optical_depth_above_per_km,
                boundary_carrier.aerosol_phase_coefficients_above,
            ),
            .aerosol_ksca_phase_below_per_km = scaledAerosolPhasePerKm(
                boundary_carrier.aerosol_scattering_optical_depth_below_per_km,
                boundary_carrier.aerosol_phase_coefficients_below,
            ),
        };
        fillAerosolSourceJacobian(
            self,
            rtm_level,
            boundary_carrier.aerosol_scattering_optical_depth_above_per_km,
            boundary_carrier.aerosol_phase_coefficients_above,
        );
    }
    fillSharedAerosolSourceJacobianFromLayers(sublayers, layer_inputs, rtm_levels);

    var has_active_quadrature = false;
    for (rtm_levels) |rtm_level| {
        if (rtm_level.weightedScattering() > 0.0) {
            has_active_quadrature = true;
            break;
        }
    }
    return has_active_quadrature;
}
