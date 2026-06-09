const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");
const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");
const shared_geometry = @import("shared_geometry.zig");
const shared_carrier = @import("shared_carrier.zig");
const carrier_eval = @import("carrier_eval.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedOpticalState = State.PreparedOpticalState;

// pseudo_spherical.zig --------------------------------------------------------------------------------------|
// Builds pseudo-spherical attenuation samples for curved direct-beam paths in source-function RTM routes.    |
//                                                                                                            |
// called by                                                                                                  |
//   forward_input.configuredForwardInput when RTM controls request spherical correction.                     |
//   LABOS attenuation builders later read the attached PseudoSphericalGrid from ForwardInput.                |
//                                                                                                            |
// main paths                                                                                                 |
//   shared-layer route : reuse cached SharedRtmGeometry plus already-filled LayerInput optical depths.       |
//   wavelength route   : evaluate support rows at one wavelength with a ProfileNodeSpectroscopyCache.        |
//   carrier route      : reuse WavelengthCarrierCache when forward_input already built one.                  |
//                                                                                                            |
// row handoff                                                                                                |
//   LayerInput optical_depth is used only after forward_layers has filled the same layer order for LABOS.    |
//   Shared geometry supplies level altitudes and support spans; output arrays are caller-owned scratch rows. |
//   PseudoSphericalSample stores only altitude, thickness, and optical depth for attenuation lookup.         |
//                                                                                                            |
// hot path                                                                                                   |
//   Runs per integrated-source wavelength when spherical correction is enabled; no allocation or file I/O.   |
//   The narrow LayerInput scan is pointer-based; splitting an optical-depth column would add ownership.      |
//                                                                                                            |
// math                                                                                                       |
//   sample optical_depth = k_ext(lambda, z_i) * dz_i.                                                        |
//   shared midpoint route uses the layer optical depth already integrated for the transport layer.           |
// -----------------------------------------------------------------------------------------------------------|

// PseudoSphericalInterval -----------------------------------------------------------------------------------|
// Borrowed prepared support rows and altitude bounds for one attenuation interval.                           |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 48 B (0.047 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0..15] support_sublayers : []const PreparedSublayer                                                      |
// [16..31] strong_line_states: ?[]const StrongLinePreparedState                                              |
// [32..39] lower_altitude_km : f64                                                                           |
// [40..47] upper_altitude_km : f64                                                                           |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// footprint: per instance = 48 B; support row and strong-line storage are borrowed                           |
const PseudoSphericalInterval = struct {
    support_sublayers: []const State.PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState = null,
    lower_altitude_km: f64,
    upper_altitude_km: f64,
};
// -----------------------------------------------------------------------------------------------------------|

pub fn fillSharedPseudoSphericalGridFromLayerInputs(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    layer_inputs: []const transport_common.LayerInput,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
) bool {
    // fillSharedPseudoSphericalGridFromLayerInputs --------------------------------------------------------- |
    // Build a pseudo-spherical attenuation grid from already-filled transport LayerInput rows.               |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Called after shared RTM geometry and layer optical depths are available for this wavelength.         |
    //   The output is an attenuation grid for LABOS direct-beam attenuation, not a new layer model.          |
    //                                                                                                        |
    // row handoff                                                                                            |
    //   layer_inputs has the same order as SharedRtmGeometry.layers and the ForwardInput layer slice.        |
    //   This route reads only LayerInput.optical_depth because geometry carries altitude and thickness.      |
    //   output samples, level starts, and level altitudes are caller-owned worker scratch arrays.            |
    //                                                                                                        |
    // memory                                                                                                 |
    //   The LayerInput scan uses pointer capture; no 176 B transport row is copied.                          |
    //   A separate optical-depth column would have to be kept in lockstep with the transport slice.          |
    // -------------------------------------------------------------------------------------------------------|

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
    for (geometry.layers, layer_inputs, 0..) |*layer_geometry, *layer_input, layer_index| {
        level_sample_starts[layer_index] = sample_index;
        if (subgrid_divisions <= 1) {
            attenuation_samples[sample_index] = .{
                .altitude_km = layer_geometry.midpoint_altitude_km,
                .thickness_km = layer_geometry.thickness_km,
                .optical_depth = layer_input.optical_depth,
            };
            sample_index += 1;
            continue;
        }

        attenuation_samples[sample_index] = .{
            .altitude_km = layer_geometry.lower_altitude_km,
            .thickness_km = 0.0,
            .optical_depth = 0.0,
        };
        sample_index += 1;

        attenuation_samples[sample_index] = .{
            .altitude_km = layer_geometry.midpoint_altitude_km,
            .thickness_km = layer_geometry.thickness_km,
            .optical_depth = layer_input.optical_depth,
        };
        sample_index += 1;

        for (2..subgrid_divisions) |_| {
            attenuation_samples[sample_index] = .{
                .altitude_km = layer_geometry.upper_altitude_km,
                .thickness_km = 0.0,
                .optical_depth = 0.0,
            };
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
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
) bool {
    var profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    return fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache(
        self,
        scene,
        wavelength_nm,
        solver_layer_count,
        attenuation_samples,
        level_sample_starts,
        level_altitudes_km,
        &profile_cache,
    );
}

pub fn fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    solver_layer_count: usize,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) bool {
    // fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache --------------------------------------------- |
    // Build pseudo-spherical attenuation samples without a wavelength carrier cache.                         |
    //                                                                                                        |
    // hot path                                                                                               |
    // expands solver layers into altitude/attenuation samples over support rows or subgrid divisions.        |
    // data: prepared sublayers, profile spectroscopy cache, attenuation sample arrays.                       |
    //                                                                                                        |
    // math                                                                                                   |
    // sample optical_depth = k_ext(lambda, z_i) * dz_i                                                       |
    // non-shared subgrid: z_i = z_low + 0.5 * (x_i + 1) * span, dz_i = 0.5 * w_i * span                      |
    //                                                                                                        |
    // calls                                                                                                  |
    // shared_carrier.fillSharedPseudoSphericalSamplesFromSupportRows                                         |
    // carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache                                       |
    // -------------------------------------------------------------------------------------------------------|

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
                sample_index = shared_carrier.fillSharedPseudoSphericalSamplesFromSupportRows(
                    self,
                    wavelength_nm,
                    support.sublayers,
                    support.strong_line_states,
                    attenuation_samples,
                    sample_index,
                    profile_cache,
                );
            }

            level_sample_starts[solver_layer_count] = sample_index;
            return true;
        }
        return false;
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
            const layer = &self.layers[ilevel];
            const start_index: usize = @intCast(layer.sublayer_start_index);
            level_altitudes_km[ilevel] = shared_geometry.levelAltitudeFromSublayers(sublayers, start_index);
        }
        level_altitudes_km[solver_layer_count] = shared_geometry.levelAltitudeFromSublayers(sublayers, sublayers.len);
    }

    for (0..solver_layer_count) |solver_level| {
        const interval = choose_interval: {
            if (solver_layer_count == sublayers.len) {
                const strong_line_state = if (self.strong_line_states) |states|
                    states[solver_level .. solver_level + 1]
                else
                    null;

                break :choose_interval PseudoSphericalInterval{
                    .support_sublayers = sublayers[solver_level .. solver_level + 1],
                    .strong_line_states = strong_line_state,
                    .lower_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, solver_level),
                    .upper_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, solver_level + 1),
                };
            }

            const layer = &self.layers[solver_level];
            const start: usize = @intCast(layer.sublayer_start_index);
            const count: usize = @intCast(layer.sublayer_count);
            if (count == 0) return false;

            const stop = start + count;
            const strong_line_state = if (self.strong_line_states) |states|
                states[start..stop]
            else
                null;

            break :choose_interval PseudoSphericalInterval{
                .support_sublayers = sublayers[start..stop],
                .strong_line_states = strong_line_state,
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
            const altitude_request = carrier_eval.SharedAltitudeCarrierRequest{
                .prepared = self,
                .support_sublayers = interval.support_sublayers,
                .strong_line_states = interval.strong_line_states,
                .profile_cache = profile_cache,
                .wavelength_nm = wavelength_nm,
                .altitude_km = sample_altitude_km,
            };
            const optical_depth =
                carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
                    &altitude_request,
                ).totalOpticalDepthPerKm() * altitude_span_km;
            attenuation_samples[sample_index] = .{
                .altitude_km = sample_altitude_km,
                .thickness_km = altitude_span_km,
                .optical_depth = optical_depth,
            };
            sample_index += 1;
            continue;
        }

        attenuation_samples[sample_index] = .{
            .altitude_km = interval.lower_altitude_km,
            .thickness_km = 0.0,
            .optical_depth = 0.0,
        };
        sample_index += 1;

        if (altitude_span_km <= 0.0) {
            for (0..active_count) |_| {
                attenuation_samples[sample_index] = .{
                    .altitude_km = interval.lower_altitude_km,
                    .thickness_km = 0.0,
                    .optical_depth = 0.0,
                };
                sample_index += 1;
            }
            continue;
        }

        const rule = gauss_legendre.rule(@intCast(active_count)) catch return false;
        for (0..active_count) |node_index| {
            const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
            const node_altitude_km = interval.lower_altitude_km + normalized_position * altitude_span_km;
            const weight_km = 0.5 * rule.weights[node_index] * altitude_span_km;
            const altitude_request = carrier_eval.SharedAltitudeCarrierRequest{
                .prepared = self,
                .support_sublayers = interval.support_sublayers,
                .strong_line_states = interval.strong_line_states,
                .profile_cache = profile_cache,
                .wavelength_nm = wavelength_nm,
                .altitude_km = node_altitude_km,
            };
            const optical_depth =
                carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
                    &altitude_request,
                ).totalOpticalDepthPerKm() * weight_km;
            attenuation_samples[sample_index] = .{
                .altitude_km = node_altitude_km,
                .thickness_km = weight_km,
                .optical_depth = optical_depth,
            };
            sample_index += 1;
        }
    }

    level_sample_starts[solver_layer_count] = sample_index;
    return true;
}

pub fn fillPseudoSphericalGridAtWavelengthWithCarrierCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    solver_layer_count: usize,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
) bool {
    // fillPseudoSphericalGridAtWavelengthWithCarrierCache ---------------------------------------------------|
    // Build pseudo-spherical attenuation samples for a cached wavelength solve.                              |
    //                                                                                                        |
    // hot path                                                                                               |
    // expands shared RTM support rows into altitude/attenuation samples through WavelengthCarrierCache.      |
    //                                                                                                        |
    // math                                                                                                   |
    // cached sample optical_depth_i = cached_total_k_ext_i * support_weight_km_i                             |
    //                                                                                                        |
    // calls                                                                                                  |
    // shared_carrier.fillSharedPseudoSphericalSamplesFromSupportRowsWithCarrierCache                         |
    // fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache fallback                                      |
    // -------------------------------------------------------------------------------------------------------|

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
    if (!shared_geometry.usesSharedRtmGrid(self, solver_layer_count)) {
        return fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache(
            self,
            scene,
            wavelength_nm,
            solver_layer_count,
            attenuation_samples,
            level_sample_starts,
            level_altitudes_km,
            wavelength_cache.profile_cache,
        );
    }

    const geometry = shared_geometry.cachedSharedRtmGeometry(self, solver_layer_count) orelse return false;
    for (level_altitudes_km, geometry.levels) |*altitude_km, level_geometry| {
        altitude_km.* = level_geometry.altitude_km;
    }

    var sample_index: usize = 0;
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
        sample_index = shared_carrier.fillSharedPseudoSphericalSamplesFromSupportRowsWithCarrierCache(
            self,
            wavelength_nm,
            support.sublayers,
            support.strong_line_states,
            attenuation_samples,
            sample_index,
            wavelength_cache,
        );
    }

    level_sample_starts[solver_layer_count] = sample_index;
    return true;
}
