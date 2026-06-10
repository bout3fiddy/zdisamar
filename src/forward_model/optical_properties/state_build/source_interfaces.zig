const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedOpticalState = State.PreparedOpticalState;

// source_interfaces.zig -------------------------------------------------------------------------------------|
// Builds source-interface transport rows for integrated-source RTM solves.                                   |
//                                                                                                            |
// called by                                                                                                  |
//   instrument_grid/grid_calculation/forward_input.zig calls this after forward_layers has filled the        |
//   LayerInput slice for the same wavelength and before the ForwardInput is handed to LABOS.                 |
//                                                                                                            |
// route map                                                                                                  |
//   profile-cache route : build or borrow ProfileNodeSpectroscopyCache, then evaluate carriers on cached     |
//                         SharedRtmGeometry boundary levels.                                                 |
//   carrier-cache route : reuse WavelengthCarrierCache so boundary carrier scalars share the same            |
//                         wavelength-local constants as forward layers and RTM quadrature.                   |
//   layer fallback      : copy boundary rows from adjacent LayerInput values, then replace interior weights  |
//                         from PreparedSublayer spans when shared geometry is unavailable.                   |
//                                                                                                            |
// row contract                                                                                               |
//   source_interfaces must have layer_inputs.len + 1 rows. Storage is caller-owned and refreshed in place.   |
//   If a shared-grid route was requested but the cached geometry is missing, rows are zeroed so stale output |
//   cannot leak into the transport input.                                                                    |
//                                                                                                            |
// hot path and memory                                                                                        |
//   Runs per high-resolution wavelength only for integrated-source solves. This file allocates nothing; it   |
//   borrows prepared sublayers, shared geometry, spectroscopy/cache rows, and the caller's output slice.     |
// -----------------------------------------------------------------------------------------------------------|

pub fn fillSourceInterfacesAtWavelengthWithLayersAndSpectroscopyCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) void {
    // fillSourceInterfacesAtWavelengthWithLayersAndSpectroscopyCache --------------------------------------- |
    // Fill source-interface rows without a wavelength carrier cache.                                         |
    //                                                                                                        |
    // hot path                                                                                               |
    // forward input construction calls this for integrated-source RTM inputs that need boundary carriers.    |
    // data: layer input array, shared RTM level geometry, profile spectroscopy cache, output rows.           |
    //                                                                                                        |
    // calls                                                                                                  |
    // carrier_eval.fillSourceInterfaceAtLevelWithSpectroscopyCache                                           |
    // transport_common.fillSourceInterfacesFromLayers fallback                                               |
    // -------------------------------------------------------------------------------------------------------|

    const invalid_output_shape = layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1;
    if (invalid_output_shape) return;

    if (self.sublayers) |sublayers| {
        const use_shared_grid = shared_geometry.usesSharedRtmGrid(self, layer_inputs.len);
        if (use_shared_grid) {
            if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                const strong_line_states = if (self.strong_line_states) |states| states else null;

                for (source_interfaces, geometry.levels) |*source_interface, level_geometry| {
                    carrier_eval.fillSourceInterfaceAtLevelWithSpectroscopyCache(
                        self,
                        wavelength_nm,
                        sublayers,
                        strong_line_states,
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
                const layer_input = layer_inputs[ilevel];
                const sublayer = sublayers[ilevel];
                const rtm_weight = @max(sublayer.path_length_cm / 1.0e5, 0.0);

                const scattering_optical_depth = @max(layer_input.scattering_optical_depth, 0.0);
                const ksca_above = choose_ksca_above: {
                    if (rtm_weight <= 0.0) break :choose_ksca_above 0.0;
                    break :choose_ksca_above scattering_optical_depth / rtm_weight;
                };

                source_interfaces[ilevel] = .{
                    .source_weight = 0.0,
                    .rtm_weight = rtm_weight,
                    .ksca_above = ksca_above,
                    .phase_above = layer_input.phase,
                    .phase_max_index_above = layer_input.phase.maxIndex(),
                };
            }
            return;
        }

        if (layer_inputs.len == 1) {
            return;
        }

        if (self.layers.len != layer_inputs.len) return;
        for (1..layer_inputs.len) |ilevel| {
            const layer = &self.layers[ilevel];
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const sublayer_count: usize = @intCast(layer.sublayer_count);

            if (sublayer_count == 0) {
                source_interfaces[ilevel] = .{
                    .source_weight = 0.0,
                    .phase_above = layer_inputs[ilevel].phase,
                    .phase_max_index_above = layer_inputs[ilevel].phase.maxIndex(),
                };
                continue;
            }

            const stop_index = start_index + sublayer_count;
            var rtm_weight: f64 = 0.0;
            for (sublayers[start_index..stop_index]) |sublayer| {
                rtm_weight += @max(sublayer.path_length_cm / 1.0e5, 0.0);
            }

            const scattering_optical_depth = @max(layer_inputs[ilevel].scattering_optical_depth, 0.0);
            const ksca_above = if (rtm_weight > 0.0)
                scattering_optical_depth / rtm_weight
            else
                0.0;

            source_interfaces[ilevel] = .{
                .source_weight = 0.0,
                .rtm_weight = rtm_weight,
                .ksca_above = ksca_above,
                .phase_above = layer_inputs[ilevel].phase,
                .phase_max_index_above = layer_inputs[ilevel].phase.maxIndex(),
            };
        }
        return;
    }
}

pub fn fillSourceInterfacesAtWavelengthWithLayersAndCarrierCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
) void {
    // fillSourceInterfacesAtWavelengthWithLayersAndCarrierCache -------------------------------------------- |
    // Fill source-interface rows for a cached wavelength solve.                                              |
    //                                                                                                        |
    // hot path                                                                                               |
    // shared-grid routes evaluate boundary carriers through WavelengthCarrierCache.                          |
    // fallback: profile-cache route above when the transport layers cannot use shared RTM geometry.          |
    //                                                                                                        |
    // calls                                                                                                  |
    // carrier_eval.fillSourceInterfaceAtLevelWithCarrierCache                                                |
    // fillSourceInterfacesAtWavelengthWithLayersAndSpectroscopyCache fallback                                |
    // -------------------------------------------------------------------------------------------------------|

    const invalid_output_shape = layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1;
    if (invalid_output_shape) return;

    if (self.sublayers) |sublayers| {
        const use_shared_grid = shared_geometry.usesSharedRtmGrid(self, layer_inputs.len);
        if (use_shared_grid) {
            if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                const strong_line_states = if (self.strong_line_states) |states| states else null;

                for (source_interfaces, geometry.levels) |*source_interface, level_geometry| {
                    carrier_eval.fillSourceInterfaceAtLevelWithCarrierCache(
                        self,
                        wavelength_nm,
                        sublayers,
                        strong_line_states,
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
