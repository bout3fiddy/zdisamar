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

// SourceInterfaceSpectroscopyRequest ------------------------------------------------------------------------|
// Borrowed inputs for source-interface rows that evaluate carriers through a profile spectroscopy cache.     |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 56 B (0.055 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] prepared          : *const PreparedOpticalState                                                   |
// [ 8..15] wavelength_nm     : f64                                                                           |
// [16..31] layer_inputs      : []const LayerInput                                                            |
// [32..47] source_interfaces : []SourceInterfaceInput                                                        |
// [48..55] profile_cache     : ?*const ProfileNodeSpectroscopyCache                                          |
//                                                                                                            |
// referenced storage                                                                                         |
//   Prepared optical rows, layer inputs, source-interface output rows, and optional profile cache are        |
//   borrowed. The caller owns source_interfaces and this file only refreshes that slice in place.            |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 1 cache line at 64 B per line                                                                  |
// footprint: per fill call = 56 B (0.055 KiB); referenced storage stays with the caller                      |
const SourceInterfaceSpectroscopyRequest = struct {
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
};
// -----------------------------------------------------------------------------------------------------------|

// SourceInterfaceCarrierRequest -----------------------------------------------------------------------------|
// Borrowed inputs for source-interface rows that reuse a wavelength carrier cache.                           |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 56 B (0.055 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] prepared          : *const PreparedOpticalState                                                   |
// [ 8..15] wavelength_nm     : f64                                                                           |
// [16..31] layer_inputs      : []const LayerInput                                                            |
// [32..47] source_interfaces : []SourceInterfaceInput                                                        |
// [48..55] wavelength_cache  : *WavelengthCarrierCache                                                       |
//                                                                                                            |
// referenced storage                                                                                         |
//   Prepared optical rows, layer inputs, source-interface output rows, and the wavelength cache are          |
//   borrowed. The cache remains owned by the forward-input worker scratch.                                   |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 1 cache line at 64 B per line                                                                  |
// footprint: per fill call = 56 B (0.055 KiB); referenced storage stays with the caller                      |
const SourceInterfaceCarrierRequest = struct {
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
};
// -----------------------------------------------------------------------------------------------------------|

pub fn fillSourceInterfacesAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
) void {
    var profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    const request = SourceInterfaceSpectroscopyRequest{
        .prepared = self,
        .wavelength_nm = wavelength_nm,
        .layer_inputs = layer_inputs,
        .source_interfaces = source_interfaces,
        .profile_cache = &profile_cache,
    };
    fillSourceInterfacesAtWavelengthWithSpectroscopyRequest(&request);
}

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

    const request = SourceInterfaceSpectroscopyRequest{
        .prepared = self,
        .wavelength_nm = wavelength_nm,
        .layer_inputs = layer_inputs,
        .source_interfaces = source_interfaces,
        .profile_cache = profile_cache,
    };
    fillSourceInterfacesAtWavelengthWithSpectroscopyRequest(&request);
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

    const request = SourceInterfaceCarrierRequest{
        .prepared = self,
        .wavelength_nm = wavelength_nm,
        .layer_inputs = layer_inputs,
        .source_interfaces = source_interfaces,
        .wavelength_cache = wavelength_cache,
    };
    fillSourceInterfacesAtWavelengthWithCarrierRequest(&request);
}

fn fillSourceInterfacesAtWavelengthWithSpectroscopyRequest(
    request: *const SourceInterfaceSpectroscopyRequest,
) void {
    // fillSourceInterfacesAtWavelengthWithSpectroscopyRequest -----------------------------------------------|
    // Implements source-interface filling from a borrowed request row.                                       |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Runs once per wavelength when integrated-source RTM needs interface rows. Shared-grid routes call    |
    //   carrier_eval for boundary carrier scalars; fallback rows are derived from existing LayerInput rows.  |
    // -------------------------------------------------------------------------------------------------------|

    const prepared = request.prepared;
    const layer_inputs = request.layer_inputs;
    const source_interfaces = request.source_interfaces;
    if (layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1) return;

    if (prepared.sublayers) |sublayers| {
        if (shared_geometry.usesSharedRtmGrid(prepared, layer_inputs.len)) {
            if (shared_geometry.cachedSharedRtmGeometry(prepared, layer_inputs.len)) |geometry| {
                const strong_line_states = if (prepared.strong_line_states) |states| states else null;

                for (source_interfaces, geometry.levels) |*source_interface, level_geometry| {
                    carrier_eval.fillSourceInterfaceAtLevelWithSpectroscopyCache(
                        prepared,
                        request.wavelength_nm,
                        sublayers,
                        strong_line_states,
                        level_geometry,
                        level_geometry.weight_km,
                        request.profile_cache,
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

    if (prepared.sublayers) |sublayers| {
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

        if (prepared.layers.len != layer_inputs.len) return;
        for (1..layer_inputs.len) |ilevel| {
            const layer = &prepared.layers[ilevel];
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

fn fillSourceInterfacesAtWavelengthWithCarrierRequest(
    request: *const SourceInterfaceCarrierRequest,
) void {
    // fillSourceInterfacesAtWavelengthWithCarrierRequest ----------------------------------------------------|
    // Implements source-interface filling after WavelengthCarrierCache has prepared wavelength-local rows.   |
    // -------------------------------------------------------------------------------------------------------|

    const prepared = request.prepared;
    const layer_inputs = request.layer_inputs;
    const source_interfaces = request.source_interfaces;
    if (layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1) return;

    if (prepared.sublayers) |sublayers| {
        if (shared_geometry.usesSharedRtmGrid(prepared, layer_inputs.len)) {
            if (shared_geometry.cachedSharedRtmGeometry(prepared, layer_inputs.len)) |geometry| {
                const strong_line_states = if (prepared.strong_line_states) |states| states else null;

                for (source_interfaces, geometry.levels) |*source_interface, level_geometry| {
                    carrier_eval.fillSourceInterfaceAtLevelWithCarrierCache(
                        prepared,
                        request.wavelength_nm,
                        sublayers,
                        strong_line_states,
                        level_geometry,
                        level_geometry.weight_km,
                        request.wavelength_cache,
                        source_interface,
                    );
                }
                return;
            }

            for (source_interfaces) |*source_interface| source_interface.* = .{};
            return;
        }
    }

    const spectroscopy_request = SourceInterfaceSpectroscopyRequest{
        .prepared = prepared,
        .wavelength_nm = request.wavelength_nm,
        .layer_inputs = layer_inputs,
        .source_interfaces = source_interfaces,
        .profile_cache = request.wavelength_cache.profile_cache,
    };
    fillSourceInterfacesAtWavelengthWithSpectroscopyRequest(&spectroscopy_request);
}
