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
// Builds the direct-beam attenuation support grid used when LABOS runs with pseudo-spherical correction.     |
// The forward input still carries ordinary transport layers; this file adds the extra altitude samples that  |
// let attenuation.zig integrate the curved solar/view path instead of using one layer-wide direction cosine. |
//                                                                                                            |
// called by                                                                                                  |
//   instrument_grid/grid_calculation/forward_input.zig calls the carrier-cache route for each RTM wavelength |
//   when rtm_controls.use_spherical_correction is enabled. It then attaches a borrowed PseudoSphericalGrid   |
//   to ForwardInput. LABOS attenuation builders read that grid while computing top-to-level direct-beam      |
//   attenuation.                                                                                             |
//                                                                                                            |
// route order                                                                                                |
//   shared layer inputs : reuse cached SharedRtmGeometry plus already-filled LayerInput optical depths.      |
//   wavelength route    : evaluate PreparedSublayer support rows with a ProfileNodeSpectroscopyCache.        |
//   carrier route       : reuse WavelengthCarrierCache built by forward_input, falling back to the           |
//                         spectroscopy-cache route only when the solver is not using a shared RTM grid.      |
//                                                                                                            |
// grid shape                                                                                                 |
//   level_altitudes_km[level] is the altitude of each solver boundary.                                       |
//   level_sample_starts[level] points into attenuation_samples; the final entry is the live sample count.    |
//   attenuation_samples[start[level]..start[level+1]] are the support samples used for that level interval.  |
//   PseudoSphericalSample stores only altitude, thickness, and optical depth; geometry factors are applied   |
//   later by LABOS using Earth radius and the local direction cosine.                                        |
//                                                                                                            |
// row handoff                                                                                                |
//   LayerInput optical_depth is used only after forward_layers has filled the same layer order consumed by   |
//   LABOS. Shared geometry supplies level altitudes and support spans. Output arrays are caller-owned worker |
//   scratch from spectral_forward/storage and are borrowed by ForwardInput for one RTM solve.                |
//                                                                                                            |
// hot path                                                                                                   |
//   Runs per integrated-source wavelength when spherical correction is enabled; no allocation or file I/O.   |
//   The shared-layer route reads one field from each 176 B LayerInput by pointer. The row is not split here  |
//   because the same caller already needs the full transport row for LABOS, and the carrier route reuses the |
//   wavelength cache that forward_input has already populated.                                               |
//                                                                                                            |
// math                                                                                                       |
//   sample_tau_i = k_ext(lambda, z_i) * dz_i                                                                 |
//   shared midpoint route uses the transport layer optical depth already integrated by forward_layers.       |
//   non-shared subgrid route maps Gauss nodes from [-1, 1] onto the support interval [z_low, z_high].        |
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

// PseudoSphericalSpectroscopyRequest ------------------------------------------------------------------------|
// Borrowed input and caller-owned output rows for one wavelength pseudo-spherical fill without carrier cache.|
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 88 B (0.086 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] prepared            : *const PreparedOpticalState                                                 |
// [ 8..15] scene               : *const Scene                                                                |
// [16..31] attenuation_samples : []PseudoSphericalSample                                                     |
// [32..47] level_sample_starts : []usize                                                                     |
// [48..63] level_altitudes_km  : []f64                                                                       |
// [64..71] profile_cache       : ?*const ProfileNodeSpectroscopyCache                                        |
// [72..79] wavelength_nm       : f64                                                                         |
// [80..87] solver_layer_count  : usize                                                                       |
//                                                                                                            |
// out-of-line                                                                                                |
//   prepared, scene, and profile_cache are borrowed. Output slices are caller-owned worker scratch rows.     |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 2 cache lines at 64 B per line                                                                 |
// footprint: per instance = 88 B plus borrowed input and caller-owned output storage                         |
pub const PseudoSphericalSpectroscopyRequest = struct {
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    wavelength_nm: f64,
    solver_layer_count: usize,
};
// -----------------------------------------------------------------------------------------------------------|

// PseudoSphericalCarrierRequest -----------------------------------------------------------------------------|
// Borrowed input and caller-owned output rows for one wavelength pseudo-spherical fill with carrier cache.   |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 88 B (0.086 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] prepared            : *const PreparedOpticalState                                                 |
// [ 8..15] scene               : *const Scene                                                                |
// [16..31] attenuation_samples : []PseudoSphericalSample                                                     |
// [32..47] level_sample_starts : []usize                                                                     |
// [48..63] level_altitudes_km  : []f64                                                                       |
// [64..71] wavelength_cache    : *WavelengthCarrierCache                                                     |
// [72..79] wavelength_nm       : f64                                                                         |
// [80..87] solver_layer_count  : usize                                                                       |
//                                                                                                            |
// out-of-line                                                                                                |
//   prepared, scene, and wavelength_cache are borrowed. Output slices are caller-owned worker scratch rows.  |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 2 cache lines at 64 B per line                                                                 |
// footprint: per instance = 88 B plus borrowed input and caller-owned output storage                         |
pub const PseudoSphericalCarrierRequest = struct {
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
    wavelength_nm: f64,
    solver_layer_count: usize,
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
    // Build the pseudo-spherical grid from already-filled transport LayerInput rows.                         |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Called after shared RTM geometry and layer optical depths are available for this wavelength. The     |
    //   output is an attenuation grid for LABOS direct-beam attenuation, not a new layer model.              |
    //                                                                                                        |
    // row handoff                                                                                            |
    //   layer_inputs has the same order as SharedRtmGeometry.layers and the ForwardInput layer slice.        |
    //   This route reads only LayerInput.optical_depth because geometry carries altitude and thickness.      |
    //   output samples, level starts, and level altitudes are caller-owned worker scratch arrays.            |
    //                                                                                                        |
    // memory                                                                                                 |
    //   This route reads one field from each 176 B LayerInput and uses pointer capture, so no transport row  |
    //   is copied. A separate optical-depth column would have to be kept in lockstep with the transport      |
    //   slice that LABOS already consumes.                                                                   |
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
    // fillPseudoSphericalGridAtWavelength ------------------------------------------------------------------ |
    // Convenience route for pseudo-spherical attenuation when the caller does not already hold a profile     |
    // spectroscopy cache. The delegated route owns the shared/direct geometry choice.                        |
    // -------------------------------------------------------------------------------------------------------|

    var profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    const request = PseudoSphericalSpectroscopyRequest{
        .prepared = self,
        .scene = scene,
        .attenuation_samples = attenuation_samples,
        .level_sample_starts = level_sample_starts,
        .level_altitudes_km = level_altitudes_km,
        .profile_cache = &profile_cache,
        .wavelength_nm = wavelength_nm,
        .solver_layer_count = solver_layer_count,
    };
    return fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache(&request);
}

pub fn fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache(
    request: *const PseudoSphericalSpectroscopyRequest,
) bool {
    // fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache --------------------------------------------- |
    // Build pseudo-spherical attenuation samples without a wavelength carrier cache.                         |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Expands solver layers into altitude/attenuation samples over support rows or subgrid divisions.      |
    //   Uses prepared sublayers, the optional profile spectroscopy cache, and caller-owned output arrays.    |
    //                                                                                                        |
    // math                                                                                                   |
    // sample optical_depth = k_ext(lambda, z_i) * dz_i                                                       |
    // non-shared subgrid: z_i = z_low + 0.5 * (x_i + 1) * span, dz_i = 0.5 * w_i * span                      |
    //                                                                                                        |
    // calls                                                                                                  |
    //   shared_carrier.fillSharedPseudoSphericalSamplesFromSupportRows                                       |
    //   carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache                                     |
    // -------------------------------------------------------------------------------------------------------|

    const sublayers = request.prepared.sublayers orelse return false;
    const subgrid_divisions = @max(@as(usize, request.scene.atmosphere.sublayer_divisions), 1);
    const sample_count = request.solver_layer_count * subgrid_divisions;
    if (request.attenuation_samples.len < sample_count or
        request.level_sample_starts.len != request.solver_layer_count + 1 or
        request.level_altitudes_km.len != request.solver_layer_count + 1)
    {
        return false;
    }

    if (request.solver_layer_count != sublayers.len and request.solver_layer_count != request.prepared.layers.len) {
        return false;
    }
    if (shared_geometry.usesSharedRtmGrid(request.prepared, request.solver_layer_count)) {
        if (shared_geometry.cachedSharedRtmGeometry(request.prepared, request.solver_layer_count)) |geometry| {
            for (request.level_altitudes_km, geometry.levels) |*altitude_km, level_geometry| {
                altitude_km.* = level_geometry.altitude_km;
            }

            var sample_index: usize = 0;
            for (geometry.layers, 0..) |layer_geometry, layer_index| {
                request.level_sample_starts[layer_index] = sample_index;
                const support_start_index: usize = @intCast(layer_geometry.support_start_index);
                const support_count: usize = @intCast(layer_geometry.support_count);
                const support = shared_geometry.sharedSupportSlices(
                    request.prepared,
                    sublayers,
                    support_start_index,
                    support_count,
                );
                sample_index = shared_carrier.fillSharedPseudoSphericalSamplesFromSupportRows(
                    request.prepared,
                    request.wavelength_nm,
                    support.sublayers,
                    support.strong_line_states,
                    request.attenuation_samples,
                    sample_index,
                    request.profile_cache,
                );
            }

            request.level_sample_starts[request.solver_layer_count] = sample_index;
            return true;
        }
        return false;
    }

    var sample_index: usize = 0;
    if (request.solver_layer_count == sublayers.len) {
        request.level_altitudes_km[0] = shared_geometry.levelAltitudeFromSublayers(sublayers, 0);
        for (1..request.solver_layer_count + 1) |ilevel| {
            request.level_altitudes_km[ilevel] = shared_geometry.levelAltitudeFromSublayers(sublayers, ilevel);
        }
    } else {
        request.level_altitudes_km[0] = shared_geometry.levelAltitudeFromSublayers(sublayers, 0);
        for (1..request.solver_layer_count) |ilevel| {
            const layer = &request.prepared.layers[ilevel];

            // Solver-level boundaries come from PreparedLayer support spans. This is an index-only read, but
            // keeping the span on PreparedLayer keeps pseudo-spherical, forward-layer, and RTM quadrature
            // fallback routes aligned to the same support-row contract.
            const start_index: usize = @intCast(layer.sublayer_start_index);
            request.level_altitudes_km[ilevel] = shared_geometry.levelAltitudeFromSublayers(sublayers, start_index);
        }
        request.level_altitudes_km[request.solver_layer_count] =
            shared_geometry.levelAltitudeFromSublayers(sublayers, sublayers.len);
    }

    for (0..request.solver_layer_count) |solver_level| {
        const interval = choose_interval: {
            if (request.solver_layer_count == sublayers.len) {
                const strong_line_state = if (request.prepared.strong_line_states) |states|
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

            const layer = &request.prepared.layers[solver_level];

            // The direct fallback expands one PreparedLayer support span into attenuation samples. The wide
            // row is read by pointer and is not copied; a separate span column would need to be kept in sync
            // with the exact same layer order used by forward_layers and rtm_quadrature.
            const start: usize = @intCast(layer.sublayer_start_index);
            const count: usize = @intCast(layer.sublayer_count);
            if (count == 0) return false;

            const stop = start + count;
            const strong_line_state = if (request.prepared.strong_line_states) |states|
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

        request.level_sample_starts[solver_level] = sample_index;
        if (active_count == 0) {
            const sample_altitude_km = if (altitude_span_km > 0.0)
                interval.lower_altitude_km + 0.5 * altitude_span_km
            else
                interval.lower_altitude_km;
            const altitude_request = carrier_eval.SharedAltitudeCarrierRequest{
                .prepared = request.prepared,
                .support_sublayers = interval.support_sublayers,
                .strong_line_states = interval.strong_line_states,
                .profile_cache = request.profile_cache,
                .wavelength_nm = request.wavelength_nm,
                .altitude_km = sample_altitude_km,
            };
            const optical_depth =
                carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
                    &altitude_request,
                ).totalOpticalDepthPerKm() * altitude_span_km;
            request.attenuation_samples[sample_index] = .{
                .altitude_km = sample_altitude_km,
                .thickness_km = altitude_span_km,
                .optical_depth = optical_depth,
            };
            sample_index += 1;
            continue;
        }

        request.attenuation_samples[sample_index] = .{
            .altitude_km = interval.lower_altitude_km,
            .thickness_km = 0.0,
            .optical_depth = 0.0,
        };
        sample_index += 1;

        if (altitude_span_km <= 0.0) {
            for (0..active_count) |_| {
                request.attenuation_samples[sample_index] = .{
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
                .prepared = request.prepared,
                .support_sublayers = interval.support_sublayers,
                .strong_line_states = interval.strong_line_states,
                .profile_cache = request.profile_cache,
                .wavelength_nm = request.wavelength_nm,
                .altitude_km = node_altitude_km,
            };
            const optical_depth =
                carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
                    &altitude_request,
                ).totalOpticalDepthPerKm() * weight_km;
            request.attenuation_samples[sample_index] = .{
                .altitude_km = node_altitude_km,
                .thickness_km = weight_km,
                .optical_depth = optical_depth,
            };
            sample_index += 1;
        }
    }

    request.level_sample_starts[request.solver_layer_count] = sample_index;
    return true;
}

pub fn fillPseudoSphericalGridAtWavelengthWithCarrierCache(
    request: *const PseudoSphericalCarrierRequest,
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

    const sublayers = request.prepared.sublayers orelse return false;
    const subgrid_divisions = @max(@as(usize, request.scene.atmosphere.sublayer_divisions), 1);
    const sample_count = request.solver_layer_count * subgrid_divisions;
    if (request.attenuation_samples.len < sample_count or
        request.level_sample_starts.len != request.solver_layer_count + 1 or
        request.level_altitudes_km.len != request.solver_layer_count + 1)
    {
        return false;
    }

    if (request.solver_layer_count != sublayers.len and request.solver_layer_count != request.prepared.layers.len) {
        return false;
    }
    if (!shared_geometry.usesSharedRtmGrid(request.prepared, request.solver_layer_count)) {
        const spectroscopy_request = PseudoSphericalSpectroscopyRequest{
            .prepared = request.prepared,
            .scene = request.scene,
            .attenuation_samples = request.attenuation_samples,
            .level_sample_starts = request.level_sample_starts,
            .level_altitudes_km = request.level_altitudes_km,
            .profile_cache = request.wavelength_cache.profile_cache,
            .wavelength_nm = request.wavelength_nm,
            .solver_layer_count = request.solver_layer_count,
        };
        return fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache(&spectroscopy_request);
    }

    const geometry = shared_geometry.cachedSharedRtmGeometry(
        request.prepared,
        request.solver_layer_count,
    ) orelse return false;
    for (request.level_altitudes_km, geometry.levels) |*altitude_km, level_geometry| {
        altitude_km.* = level_geometry.altitude_km;
    }

    var sample_index: usize = 0;
    for (geometry.layers, 0..) |layer_geometry, layer_index| {
        request.level_sample_starts[layer_index] = sample_index;
        const support_start_index: usize = @intCast(layer_geometry.support_start_index);
        const support_count: usize = @intCast(layer_geometry.support_count);
        const support = shared_geometry.sharedSupportSlices(
            request.prepared,
            sublayers,
            support_start_index,
            support_count,
        );
        sample_index = shared_carrier.fillSharedPseudoSphericalSamplesFromSupportRowsWithCarrierCache(
            request.prepared,
            request.wavelength_nm,
            support.sublayers,
            support.strong_line_states,
            request.attenuation_samples,
            sample_index,
            request.wavelength_cache,
        );
    }

    request.level_sample_starts[request.solver_layer_count] = sample_index;
    return true;
}
