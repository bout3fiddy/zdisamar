const std = @import("std");
const transport_common = @import("../../transport/common.zig");
const State = @import("state.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");
const Rayleigh = @import("../../../model/reference/rayleigh.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedOpticalState = State.PreparedOpticalState;

pub fn fillSourceInterfacesAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
) void {
    var profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    fillSourceInterfacesAtWavelengthWithLayersAndSpectroscopyCache(
        self,
        wavelength_nm,
        layer_inputs,
        source_interfaces,
        &profile_cache,
    );
}

pub fn fillSourceInterfacesAtWavelengthWithLayersAndSpectroscopyCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) void {
    if (layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1) return;

    if (self.sublayers) |sublayers| {
        if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
            if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                for (source_interfaces, geometry.levels) |*source_interface, level_geometry| {
                    if (level_geometry.weight_km > 0.0) {
                        const boundary_carrier = carrier_eval.sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
                            self,
                            wavelength_nm,
                            sublayers,
                            if (self.strong_line_states) |states| states else null,
                            level_geometry,
                            profile_cache,
                        );
                        source_interface.* = .{
                            .source_weight = 0.0,
                            .rtm_weight = level_geometry.weight_km,
                            .gas_ksca = boundary_carrier.gas_scattering_optical_depth_per_km,
                            .particle_ksca_above = boundary_carrier.particle_scattering_optical_depth_above_per_km,
                            .particle_ksca_below = boundary_carrier.particle_scattering_optical_depth_below_per_km,
                            .ksca_above = boundary_carrier.ksca_above,
                            .ksca_below = boundary_carrier.ksca_below,
                            .gas_phase_coefficients = boundary_carrier.gas_phase_coefficients,
                            .phase_coefficients_above = boundary_carrier.phase_coefficients_above,
                            .phase_coefficients_below = boundary_carrier.phase_coefficients_below,
                        };
                    } else {
                        const boundary_carrier = carrier_eval.sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
                            self,
                            wavelength_nm,
                            sublayers,
                            if (self.strong_line_states) |states| states else null,
                            level_geometry,
                            profile_cache,
                        );
                        source_interface.* = .{
                            .source_weight = 0.0,
                            .rtm_weight = level_geometry.weight_km,
                            .gas_ksca = boundary_carrier.gas_scattering_optical_depth_per_km,
                            .particle_ksca_above = boundary_carrier.particle_scattering_optical_depth_above_per_km,
                            .particle_ksca_below = boundary_carrier.particle_scattering_optical_depth_below_per_km,
                            .ksca_above = boundary_carrier.ksca_above,
                            .ksca_below = boundary_carrier.ksca_below,
                            .gas_phase_coefficients = boundary_carrier.gas_phase_coefficients,
                            .phase_coefficients_above = boundary_carrier.phase_coefficients_above,
                            .phase_coefficients_below = boundary_carrier.phase_coefficients_below,
                        };
                    }
                }
                return;
            }
            for (source_interfaces) |*source_interface| source_interface.* = .{};
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
