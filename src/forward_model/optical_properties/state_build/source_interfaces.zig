const std = @import("std");
const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");
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

// hot path:
//   when: forward input construction fills source interfaces without a wavelength carrier cache
//   work: evaluates boundary carriers or derives interfaces from adjacent layer inputs
//   data: layer input array, shared RTM level geometry, profile spectroscopy cache, source-interface output
//   follow: carrier_eval.fillSourceInterfaceAtLevelWithSpectroscopyCache
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
                    carrier_eval.fillSourceInterfaceAtLevelWithSpectroscopyCache(
                        self,
                        wavelength_nm,
                        sublayers,
                        if (self.strong_line_states) |states| states else null,
                        level_geometry,
                        level_geometry.weight_km,
                        profile_cache,
                        source_interface,
                    );
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

// hot path:
//   when: forward input construction fills source interfaces for a cached wavelength solve
//   work: evaluates boundary carriers through WavelengthCarrierCache and writes source-interface rows
//   data: layer input array, shared RTM level geometry, carrier cache, source-interface output
//   follow: carrier_eval.fillSourceInterfaceAtLevelWithCarrierCache
pub fn fillSourceInterfacesAtWavelengthWithLayersAndCarrierCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
) void {
    if (layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1) return;

    if (self.sublayers) |sublayers| {
        if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
            if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                for (source_interfaces, geometry.levels) |*source_interface, level_geometry| {
                    carrier_eval.fillSourceInterfaceAtLevelWithCarrierCache(
                        self,
                        wavelength_nm,
                        sublayers,
                        if (self.strong_line_states) |states| states else null,
                        level_geometry,
                        level_geometry.weight_km,
                        wavelength_cache,
                        source_interface,
                    );
                }
                return;
            }
            for (source_interfaces) |*source_interface| source_interface.* = .{};
            return;
        }
    }

    fillSourceInterfacesAtWavelengthWithLayersAndSpectroscopyCache(
        self,
        wavelength_nm,
        layer_inputs,
        source_interfaces,
        wavelength_cache.profile_cache,
    );
}
