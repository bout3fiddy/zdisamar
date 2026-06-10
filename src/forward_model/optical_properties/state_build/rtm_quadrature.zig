const std = @import("std");
const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");
const transport_common = @import("../../radiative_transfer/root.zig");
const State = @import("state.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedOpticalState = State.PreparedOpticalState;

// rtm_quadrature.zig ----------------------------------------------------------------------------------------|
// Builds RTM source-function quadrature rows from prepared optical state and per-wavelength carriers.        |
//                                                                                                            |
// called by                                                                                                  |
//   forward_input.configuredForwardInput after forward_layers fills LayerInput for the same wavelength.      |
//   The RtmQuadratureLevel slice is attached to ForwardInput, then read by LABOS reflectance code.           |
//                                                                                                            |
// main paths                                                                                                 |
//   shared grid route : use cached SharedRtmGeometry level rows and carrier caches for explicit intervals.   |
//   fallback route    : place Gauss nodes inside each PreparedLayer support span and sample carriers there.  |
//   Jacobian route    : spread aerosol source derivatives over active quadrature levels.                     |
//                                                                                                            |
// row handoff                                                                                                |
//   LayerInput rows come from forward_layers and stay in the same order as transport layers.                 |
//   PreparedLayer supplies support-row spans; the same wide row also carries altitude/aerosol fields nearby. |
//   RtmQuadratureLevel is a one-cache-line transport row consumed later by source-integration loops.         |
//                                                                                                            |
// hot path                                                                                                   |
//   Runs per high-resolution wavelength. The caller owns rtm_levels; this refreshes rows without allocating. |
//   Narrow scans use pointer capture, so they stride 176 B LayerInput and 208 B PreparedLayer rows without   |
//   copying them by value. The narrow reads are support-span fields at PreparedLayer [192..207], Jacobian    |
//   vectors at LayerInput [88..111], and aerosol k_sca slots in the 64 B RtmQuadratureLevel rows.            |
//                                                                                                            |
// math                                                                                                       |
//   weighted source = RTM weight * k_sca.                                                                    |
//   fallback quadrature rescales raw weighted k_sca so its sum matches layer scattering optical depth.       |
// -----------------------------------------------------------------------------------------------------------|

// RtmQuadratureSpectroscopyRequest --------------------------------------------------------------------------|
// Borrowed inputs and caller-owned output rows for one wavelength RTM quadrature fill without carrier cache. |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 64 B (0.062 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] prepared          : *const PreparedOpticalState                                                   |
// [ 8..23] layer_inputs      : []const LayerInput                                                            |
// [24..39] rtm_levels        : []RtmQuadratureLevel                                                          |
// [40..47] profile_cache     : ?*const ProfileNodeSpectroscopyCache                                          |
// [48..55] wavelength_nm     : f64                                                                           |
// [56..56] compute_jacobian  : bool                                                                          |
// [57..63] padding           : 7 B                                                                           |
//                                                                                                            |
// out-of-line                                                                                                |
//   prepared and profile_cache are borrowed. layer_inputs is borrowed; rtm_levels is caller-owned output.    |
//                                                                                                            |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                   |
// cache span: 1 cache line at 64 B per line                                                                  |
// footprint: per instance = 64 B plus borrowed input and caller-owned output storage                         |
pub const RtmQuadratureSpectroscopyRequest = struct {
    prepared: *const PreparedOpticalState,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    wavelength_nm: f64,
    compute_jacobian: bool,
};
// -----------------------------------------------------------------------------------------------------------|

// RtmQuadratureCarrierRequest -------------------------------------------------------------------------------|
// Borrowed inputs and caller-owned output rows for one wavelength RTM quadrature fill with carrier cache.    |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 64 B (0.062 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] prepared          : *const PreparedOpticalState                                                   |
// [ 8..23] layer_inputs      : []const LayerInput                                                            |
// [24..39] rtm_levels        : []RtmQuadratureLevel                                                          |
// [40..47] wavelength_cache  : *WavelengthCarrierCache                                                       |
// [48..55] wavelength_nm     : f64                                                                           |
// [56..56] compute_jacobian  : bool                                                                          |
// [57..63] padding           : 7 B                                                                           |
//                                                                                                            |
// out-of-line                                                                                                |
//   prepared and wavelength_cache are borrowed. layer_inputs is borrowed; rtm_levels is caller-owned output. |
//                                                                                                            |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                   |
// cache span: 1 cache line at 64 B per line                                                                  |
// footprint: per instance = 64 B plus borrowed input and caller-owned output storage                         |
pub const RtmQuadratureCarrierRequest = struct {
    prepared: *const PreparedOpticalState,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
    wavelength_nm: f64,
    compute_jacobian: bool,
};
// -----------------------------------------------------------------------------------------------------------|

fn fillAerosolSourceJacobian(
    self: *const PreparedOpticalState,
    rtm_level: *transport_common.RtmQuadratureLevel,
    aerosol_scattering_optical_depth_per_km: f64,
) void {
    // fillAerosolSourceJacobian -----------------------------------------------------------------------------|
    // Write the aerosol source Jacobian scale for one RTM quadrature level.                                  |
    //                                                                                                        |
    // boundary                                                                                               |
    //   This is source-function Jacobian weighting, not the layer optical-depth Jacobian itself. The caller  |
    //   has already evaluated the local aerosol scattering carrier for this level.                           |
    //                                                                                                        |
    // math                                                                                                   |
    //   aerosol_ksca_jacobian                                                                                |
    //     = local aerosol scattering optical depth per km / total aerosol optical depth                      |
    //                                                                                                        |
    // memory                                                                                                 |
    //   Writes only aerosol_ksca_jacobian at [40..47] in the 64 B RtmQuadratureLevel row.                    |
    // -------------------------------------------------------------------------------------------------------|

    if (self.aerosol_optical_depth <= 0.0 or aerosol_scattering_optical_depth_per_km <= 0.0) return;

    const derivative_scale = aerosol_scattering_optical_depth_per_km / self.aerosol_optical_depth;
    rtm_level.aerosol_ksca_jacobian = derivative_scale;
}

fn clearRtmQuadratureLevels(rtm_levels: []transport_common.RtmQuadratureLevel) void {
    // clearRtmQuadratureLevels ------------------------------------------------------------------------------|
    // Clear caller-owned RTM quadrature rows when a shared-grid route was requested but no compatible cached |
    // geometry exists. This prevents stale level rows from leaking into ForwardInput after a failed fill.    |
    //                                                                                                        |
    // memory                                                                                                 |
    //   RtmQuadratureLevel default values are all zero, so `.{}` clears altitude, weight, k_sca, aerosol     |
    //   Jacobian, and phase weights in one row assignment.                                                   |
    // -------------------------------------------------------------------------------------------------------|

    for (rtm_levels) |*rtm_level| rtm_level.* = .{};
}

fn fillSharedAerosolSourceJacobianFromLayers(
    self: *const PreparedOpticalState,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
) void {
    // fillSharedAerosolSourceJacobianFromLayers -------------------------------------------------------------|
    // Spread the shared-grid aerosol source Jacobian over active RTM quadrature levels.                      |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Runs only when integrated-source aerosol Jacobians are requested. It makes three short passes:       |
    //     1. sum aerosol scattering derivative from LayerInput Jacobian vectors                              |
    //     2. sum weights for RTM levels adjacent to derivative-active layers                                 |
    //     3. write one derivative-per-km value into active RtmQuadratureLevel rows                           |
    //                                                                                                        |
    // memory                                                                                                 |
    //   LayerInput is 176 B. This reads scattering_optical_depth_jacobian at [88..111] by pointer.           |
    //   RtmQuadratureLevel is 64 B. This reads weight at [8..15] and writes aerosol_ksca_jacobian at         |
    //   [40..47] by pointer. A side column would have to stay synchronized with both layer order and RTM     |
    //   level order, so it needs retained benchmark proof before it is simpler than the row walk.            |
    //                                                                                                        |
    // math                                                                                                   |
    //   derivative per km = total aerosol scattering derivative / active quadrature weight                   |
    // -------------------------------------------------------------------------------------------------------|

    var total_weight: f64 = 0.0;
    var total_scattering_derivative: f64 = 0.0;

    for (layer_inputs) |*layer| {
        const derivative = transport_common.Jacobian.get(
            layer.scattering_optical_depth_jacobian,
            .aerosol_optical_depth,
        );

        if (derivative <= 0.0) continue;

        total_scattering_derivative += derivative;
    }

    // No active derivative, or no aerosol phase support. The shared-grid source Jacobian only contributes
    // when aerosol phase participates in the source term.
    if (total_scattering_derivative <= 0.0 or self.aerosol_phase_coefficients[0] == 0.0) return;

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

        level.aerosol_ksca_jacobian = derivative_per_km;
    }
}

pub fn fillRtmQuadratureAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
) bool {
    // fillRtmQuadratureAtWavelengthWithLayers ---------------------------------------------------------------|
    // Convenience route for callers that do not already hold a profile spectroscopy cache. It builds one     |
    // cache for this wavelength and then uses the shared prepared implementation below.                      |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Avoid this wrapper when a caller is already filling forward layers or pseudo-spherical rows for the  |
    //   same wavelength; pass the existing cache so profile-node spectroscopy is not repeated.               |
    // -------------------------------------------------------------------------------------------------------|

    var profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    const request = RtmQuadratureSpectroscopyRequest{
        .prepared = self,
        .layer_inputs = layer_inputs,
        .rtm_levels = rtm_levels,
        .profile_cache = &profile_cache,
        .wavelength_nm = wavelength_nm,
        .compute_jacobian = true,
    };
    return fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(&request);
}

pub fn fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(
    request: *const RtmQuadratureSpectroscopyRequest,
) bool {
    // fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache -------------------------------------------|
    // Fill RTM quadrature levels when only the profile spectroscopy cache is available.                      |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Called once per integrated-source wavelength. Shared geometry writes one row per cached RTM level.   |
    //   The fallback places fresh Gauss nodes inside each PreparedLayer support span.                        |
    //                                                                                                        |
    // row handoff                                                                                            |
    //   layer_inputs has the same transport-layer order as forward_layers just wrote.                        |
    //   rtm_levels has exactly layer_inputs.len + 1 rows and becomes ForwardInput.rtm_quadrature.levels.     |
    //   The fallback reads support indexes and altitude bounds by pointer from the 208 B PreparedLayer row.  |
    //                                                                                                        |
    // memory                                                                                                 |
    //   No allocation here. The caller owns rtm_levels, LayerInput rows, and the optional profile cache.     |
    //   The fallback reads PreparedLayer.sublayer_start_index at [192..195] and sublayer_count at            |
    //   [204..207] from each 208 B row. A separate support-index column needs a retained benchmark showing   |
    //   this fallback dominates before it is worth another synchronized shape.                               |
    //                                                                                                        |
    // math                                                                                                   |
    //   non-shared fallback samples k_sca(lambda, z_i) at Gauss nodes and weights by dz_i.                   |
    //   It then rescales k_sca so sum(weight_i * k_sca_i) matches layer scattering tau.                      |
    //                                                                                                        |
    // calls                                                                                                  |
    //   carrier_eval.fillRtmQuadratureLevelAtLevelWithSpectroscopyCache                                      |
    //   fillAerosolSourceJacobian                                                                            |
    // -------------------------------------------------------------------------------------------------------|

    const sublayers = request.prepared.sublayers orelse return false;
    if (request.rtm_levels.len != request.layer_inputs.len + 1) return false;

    if (shared_geometry.usesSharedRtmGrid(request.prepared, request.layer_inputs.len)) {
        if (shared_geometry.cachedSharedRtmGeometry(request.prepared, request.layer_inputs.len)) |geometry| {
            for (request.rtm_levels, geometry.levels) |*rtm_level, level_geometry| {
                carrier_eval.fillRtmQuadratureLevelAtLevelWithSpectroscopyCache(
                    request.prepared,
                    request.wavelength_nm,
                    sublayers,
                    if (request.prepared.strong_line_states) |states| states else null,
                    level_geometry,
                    request.profile_cache,
                    rtm_level,
                    request.compute_jacobian,
                );
                if (request.compute_jacobian) {
                    fillAerosolSourceJacobian(
                        request.prepared,
                        rtm_level,
                        rtm_level.aerosol_ksca_above_per_km,
                    );
                }
            }

            // DISAMAR's integrated-source reflectance uses RTMweight(level) multiplied by the scattering
            // carrier sampled at that coarse RTM level. This route does not renormalize the source
            // quadrature back to the sublayer-integrated layer scattering totals.
            var has_active_quadrature = false;
            for (request.rtm_levels) |*rtm_level| {
                if (rtm_level.weightedScattering() > 0.0) {
                    has_active_quadrature = true;
                    break;
                }
            }
            return has_active_quadrature;
        }

        clearRtmQuadratureLevels(request.rtm_levels);
        return false;
    }

    if (request.layer_inputs.len != sublayers.len) return false;

    const rayleigh_phase_coefficient2 = PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(request.wavelength_nm);
    for (request.rtm_levels, 0..) |*rtm_level, level| {
        rtm_level.* = .{
            .altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, level),
            .weight = 0.0,
            .ksca = 0.0,
        };
        rtm_level.setPhaseMixture(rayleigh_phase_coefficient2, 0.0, 0.0);
    }

    var has_active_quadrature = false;
    const layers: []const State.PreparedLayer = request.prepared.layers;
    for (layers) |*layer| {

        // The fallback reads the PreparedLayer support tail only: sublayer_start_index at [192..195] and
        // sublayer_count at [204..207]. That span is the same layer identity used by forward-layer and
        // pseudo-spherical builders, so keep this as a pointer walk until a retained benchmark proves a side
        // span column improves this boundary.
        const start: usize = @intCast(layer.sublayer_start_index);
        const count: usize = @intCast(layer.sublayer_count);
        if (count == 0) continue;
        const stop = start + count;
        if (stop >= request.rtm_levels.len) return false;

        const active_count = if (count > 0) count - 1 else 0;
        if (active_count == 0) continue;
        const rule = gauss_legendre.rule(@intCast(active_count)) catch return false;
        const lower_altitude_km = request.rtm_levels[start].altitude_km;
        const upper_altitude_km = request.rtm_levels[stop].altitude_km;
        const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);

        var total_span_km: f64 = 0.0;
        var total_scattering: f64 = 0.0;
        for (start..stop) |row| {
            total_span_km += @max(sublayers[row].path_length_cm / 1.0e5, 0.0);
            total_scattering += @max(request.layer_inputs[row].scattering_optical_depth, 0.0);
        }
        if (total_span_km <= 0.0) continue;

        var raw_scattering_sum: f64 = 0.0;
        for (0..active_count) |node_index| {
            const level = start + 1 + node_index;
            const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
            const node_altitude_km = lower_altitude_km + normalized_position * altitude_span_km;
            const carrier = carrier_eval.quadratureCarrierAtAltitudeWithSpectroscopyCache(
                request.prepared,
                request.wavelength_nm,
                sublayers[start..stop],
                if (request.prepared.strong_line_states) |states| states[start..stop] else null,
                node_altitude_km,
                request.profile_cache,
            );
            request.rtm_levels[level].altitude_km = node_altitude_km;
            request.rtm_levels[level].weight = 0.5 * rule.weights[node_index] * total_span_km;
            request.rtm_levels[level].ksca = carrier.ksca;
            request.rtm_levels[level].aerosol_ksca_above_per_km = carrier.aerosol_scattering_optical_depth_per_km;
            request.rtm_levels[level].aerosol_ksca_below_per_km = request.rtm_levels[level].aerosol_ksca_above_per_km;
            request.rtm_levels[level].setPhaseMixture(
                rayleigh_phase_coefficient2,
                carrier.gas_scattering_optical_depth_per_km,
                carrier.aerosol_scattering_optical_depth_per_km,
            );
            if (request.compute_jacobian) {
                fillAerosolSourceJacobian(
                    request.prepared,
                    &request.rtm_levels[level],
                    carrier.aerosol_scattering_optical_depth_per_km,
                );
            }
            raw_scattering_sum += request.rtm_levels[level].weightedScattering();
        }

        if (total_scattering <= 0.0) {
            for (start + 1..stop) |level| {
                request.rtm_levels[level].ksca = 0.0;
            }
            continue;
        }

        if (raw_scattering_sum > 0.0) {
            const scale = total_scattering / raw_scattering_sum;
            for (start + 1..stop) |level| {
                request.rtm_levels[level].ksca *= scale;
                request.rtm_levels[level].aerosol_ksca_above_per_km *= scale;
                request.rtm_levels[level].aerosol_ksca_below_per_km *= scale;
                if (request.compute_jacobian) request.rtm_levels[level].aerosol_ksca_jacobian *= scale;
            }
            has_active_quadrature = true;
        } else {
            for (start + 1..stop) |level| {
                request.rtm_levels[level].weight = 0.0;
                request.rtm_levels[level].ksca = 0.0;
            }
        }
    }

    return has_active_quadrature;
}

pub fn fillRtmQuadratureAtWavelengthWithLayersAndCarrierCache(
    request: *const RtmQuadratureCarrierRequest,
) bool {
    // fillRtmQuadratureAtWavelengthWithLayersAndCarrierCache ------------------------------------------------|
    // Fill RTM quadrature levels for a cached wavelength solve.                                              |
    //                                                                                                        |
    // hot path                                                                                               |
    // called by integrated-source routes after WavelengthCarrierCache has already prepared carrier values.   |
    // work: read cached boundary carriers and write the same RTM level row layout as the uncached path.      |
    //                                                                                                        |
    // memory                                                                                                 |
    // The shared-grid loop reads aerosol_ksca_above_per_km at [24..31] from each RtmQuadratureLevel after    |
    // carrier_eval has filled the same 64 B row. Keeping the full row avoids a side column that would have   |
    // to be synchronized with RTM level altitude, weight, k_sca, and phase weights.                          |
    //                                                                                                        |
    // calls                                                                                                  |
    // carrier_eval.fillRtmQuadratureLevelAtLevelWithCarrierCache                                             |
    // fillAerosolSourceJacobian                                                                              |
    // fillSharedAerosolSourceJacobianFromLayers                                                              |
    // -------------------------------------------------------------------------------------------------------|

    const sublayers = request.prepared.sublayers orelse return false;
    if (request.rtm_levels.len != request.layer_inputs.len + 1) return false;

    if (!shared_geometry.usesSharedRtmGrid(request.prepared, request.layer_inputs.len)) {
        const spectroscopy_request = RtmQuadratureSpectroscopyRequest{
            .prepared = request.prepared,
            .layer_inputs = request.layer_inputs,
            .rtm_levels = request.rtm_levels,
            .profile_cache = request.wavelength_cache.profile_cache,
            .wavelength_nm = request.wavelength_nm,
            .compute_jacobian = request.compute_jacobian,
        };
        return fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(&spectroscopy_request);
    }

    const geometry = shared_geometry.cachedSharedRtmGeometry(
        request.prepared,
        request.layer_inputs.len,
    ) orelse {
        clearRtmQuadratureLevels(request.rtm_levels);
        return false;
    };

    for (request.rtm_levels, geometry.levels) |*rtm_level, level_geometry| {
        carrier_eval.fillRtmQuadratureLevelAtLevelWithCarrierCache(
            request.prepared,
            request.wavelength_nm,
            sublayers,
            if (request.prepared.strong_line_states) |states| states else null,
            level_geometry,
            request.wavelength_cache,
            rtm_level,
            request.compute_jacobian,
        );
        if (request.compute_jacobian) {
            fillAerosolSourceJacobian(
                request.prepared,
                rtm_level,
                rtm_level.aerosol_ksca_above_per_km,
            );
        }
    }
    if (request.compute_jacobian) {
        fillSharedAerosolSourceJacobianFromLayers(
            request.prepared,
            request.layer_inputs,
            request.rtm_levels,
        );
    }

    var has_active_quadrature = false;
    for (request.rtm_levels) |*rtm_level| {
        if (rtm_level.weightedScattering() > 0.0) {
            has_active_quadrature = true;
            break;
        }
    }
    return has_active_quadrature;
}
