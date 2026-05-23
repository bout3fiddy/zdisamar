const std = @import("std");
const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");
const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedOpticalState = State.PreparedOpticalState;

fn fillAerosolSourceJacobian(
    self: *const PreparedOpticalState,
    rtm_level: *transport_common.RtmQuadratureLevel,
    aerosol_scattering_optical_depth_per_km: f64,
) void {
    if (self.aerosol_optical_depth <= 0.0 or aerosol_scattering_optical_depth_per_km <= 0.0) return;
    // math: d(k_sca_aerosol)/d(tau_aerosol_column) = k_sca_aerosol_per_km / tau_aerosol_column
    const derivative_scale = aerosol_scattering_optical_depth_per_km / self.aerosol_optical_depth;
    rtm_level.aerosol_ksca_jacobian = derivative_scale;
}

fn fillSharedAerosolSourceJacobianFromLayers(
    self: *const PreparedOpticalState,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
) void {
    var total_weight: f64 = 0.0;
    var total_scattering_derivative: f64 = 0.0;

    for (layer_inputs) |layer| {
        const derivative = transport_common.Jacobian.get(
            layer.scattering_optical_depth_jacobian,
            .aerosol_optical_depth,
        );
        if (derivative <= 0.0) continue;
        total_scattering_derivative += derivative;
    }
    if (total_scattering_derivative <= 0.0 or self.aerosol_phase_coefficients[0] == 0.0) return;

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

    // math: distribute total aerosol scattering derivative uniformly over active RTM quadrature weight.
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
        level.aerosol_ksca_jacobian = derivative_per_km;
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
        true,
    );
}

// hot path:
//   when: integrated source-function routes fill RTM quadrature without a wavelength carrier cache
//   work: evaluates boundary carriers, phase data, and aerosol source Jacobian rows at RTM levels
//   data: layer input array, shared RTM levels, profile spectroscopy cache, quadrature output
//   math: non-shared fallback samples k_sca(lambda,z_i) at Gauss nodes, weights by dz_i, then rescales k_sca so sum(weight_i*k_sca_i) matches layer scattering tau
//   follow: carrier_eval.fillRtmQuadratureLevelAtLevelWithSpectroscopyCache and fillAerosolSourceJacobian
pub fn fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    compute_jacobian: bool,
) bool {
    const sublayers = self.sublayers orelse return false;
    if (rtm_levels.len != layer_inputs.len + 1) return false;

    if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
        if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
            for (rtm_levels, geometry.levels) |*rtm_level, level_geometry| {
                carrier_eval.fillRtmQuadratureLevelAtLevelWithSpectroscopyCache(
                    self,
                    wavelength_nm,
                    sublayers,
                    if (self.strong_line_states) |states| states else null,
                    level_geometry,
                    profile_cache,
                    rtm_level,
                    compute_jacobian,
                );
                if (compute_jacobian) {
                    fillAerosolSourceJacobian(
                        self,
                        rtm_level,
                        rtm_level.aerosol_ksca_above_per_km,
                    );
                }
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
            };
        }
        return false;
    }

    if (layer_inputs.len != sublayers.len) return false;

    const rayleigh_phase_coefficient2 = PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm);
    for (rtm_levels, 0..) |*rtm_level, level| {
        rtm_level.* = .{
            .altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, level),
            .weight = 0.0,
            .ksca = 0.0,
        };
        rtm_level.setPhaseMixture(rayleigh_phase_coefficient2, 0.0, 0.0);
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
            rtm_levels[level].aerosol_ksca_above_per_km = carrier.aerosol_scattering_optical_depth_per_km;
            rtm_levels[level].aerosol_ksca_below_per_km = rtm_levels[level].aerosol_ksca_above_per_km;
            rtm_levels[level].setPhaseMixture(
                rayleigh_phase_coefficient2,
                carrier.gas_scattering_optical_depth_per_km,
                carrier.aerosol_scattering_optical_depth_per_km,
            );
            if (compute_jacobian) {
                fillAerosolSourceJacobian(
                    self,
                    &rtm_levels[level],
                    carrier.aerosol_scattering_optical_depth_per_km,
                );
            }
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
                rtm_levels[level].aerosol_ksca_above_per_km *= scale;
                rtm_levels[level].aerosol_ksca_below_per_km *= scale;
                if (compute_jacobian) rtm_levels[level].aerosol_ksca_jacobian *= scale;
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
//   math: cached path uses the same weighted scattering source terms, reading k(lambda,z) from WavelengthCarrierCache
//   follow: carrier_eval.fillRtmQuadratureLevelAtLevelWithCarrierCache and aerosol source Jacobian fields
pub fn fillRtmQuadratureAtWavelengthWithLayersAndCarrierCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
    compute_jacobian: bool,
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
            compute_jacobian,
        );
    }

    const geometry = shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len) orelse {
        for (rtm_levels) |*rtm_level| {
            rtm_level.* = .{
                .altitude_km = 0.0,
                .weight = 0.0,
                .ksca = 0.0,
            };
        }
        return false;
    };

    for (rtm_levels, geometry.levels) |*rtm_level, level_geometry| {
        carrier_eval.fillRtmQuadratureLevelAtLevelWithCarrierCache(
            self,
            wavelength_nm,
            sublayers,
            if (self.strong_line_states) |states| states else null,
            level_geometry,
            wavelength_cache,
            rtm_level,
            compute_jacobian,
        );
        if (compute_jacobian) {
            fillAerosolSourceJacobian(
                self,
                rtm_level,
                rtm_level.aerosol_ksca_above_per_km,
            );
        }
    }
    if (compute_jacobian) fillSharedAerosolSourceJacobianFromLayers(self, layer_inputs, rtm_levels);

    var has_active_quadrature = false;
    for (rtm_levels) |rtm_level| {
        if (rtm_level.weightedScattering() > 0.0) {
            has_active_quadrature = true;
            break;
        }
    }
    return has_active_quadrature;
}
