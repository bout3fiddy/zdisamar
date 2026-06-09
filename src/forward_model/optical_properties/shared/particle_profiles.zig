const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const AtmosphereModel = @import("../../../input/Atmosphere.zig");
const Allocator = std.mem.Allocator;

// particle_profiles.zig -------------------------------------------------------------------------------------   |
// Builds aerosol optical-depth distributions over prepared layer and sublayer grids.                            |
//                                                                                                               |
// called by                                                                                                     |
//   vertical_grid.zig exposes the prepared layer/sublayer grid slices                                           |
//   layer_accumulation.zig builds profile aerosol properties during optical-state preparation                   |
//   forward_layers.zig, carrier_eval.zig, and state_scalar.zig read the prepared particle distribution          |
//                                                                                                               |
// main paths                                                                                                    |
//   buildAerosolSublayerDistribution                                                                            |
//     -> choose explicit-interval placement or altitude-bound placement from Scene controls                     |
//     -> allocate one optical-depth weight per prepared sublayer                                                |
//                                                                                                               |
//   buildIntervalMatchedDistribution                                                                            |
//     -> put all aerosol depth on sublayers belonging to one explicit interval                                  |
//                                                                                                               |
//   buildFiniteLayerSublayerDistribution                                                                        |
//     -> distribute aerosol depth by vertical overlap with an altitude interval                                 |
//                                                                                                               |
// hot path                                                                                                      |
//   Layer accumulation and carrier evaluation read the prepared distribution repeatedly at wavelength time.     |
//   This file keeps placement work in setup and stores only per-sublayer weights for the hot reads.             |
//                                                                                                               |
// memory                                                                                                        |
//   PreparedVerticalGrid borrows vertical-grid arrays from state_build. Distribution builders allocate only     |
//   the returned []f64 weights; callers own and free those weights with the prepared optical state.             |
// ------------------------------------------------------------------------------------------------------------  |

// PreparedVerticalGrid --------------------------------------------------------------------------------------   |
// Borrowed layer and sublayer grid slices used to place aerosol optical depth.                                  |
//                                                                                                               |
// layout(64-bit)                                                                                                |
// size: 128 B (0.125 KiB), align: 8 B                                                                           |
//                                                                                                               |
// memory                                                                                                        |
// [  0.. 15] layer_top_altitudes_km                      : []const f64                                          |
// [ 16.. 31] layer_bottom_altitudes_km                   : []const f64                                          |
// [ 32.. 47] layer_interval_indices_1based               : []const u32                                          |
// [ 48.. 63] sublayer_top_altitudes_km                   : []const f64                                          |
// [ 64.. 79] sublayer_bottom_altitudes_km                : []const f64                                          |
// [ 80.. 95] sublayer_mid_altitudes_km                   : []const f64                                          |
// [ 96..111] sublayer_support_weights_km                 : []const f64                                          |
// [112..127] sublayer_parent_interval_indices_1based     : []const u32                                          |
//                                                                                                               |
// out-of-line                                                                                                   |
//   all slices borrow prepared vertical-grid arrays; referenced storage is not included in size.                |
//                                                                                                               |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                        |
// cache span: 2 cache lines at 64 B per line                                                                    |
// footprint: per instance = 128 B plus borrowed grid storage                                                    |
pub const PreparedVerticalGrid = struct {
    layer_top_altitudes_km: []const f64,
    layer_bottom_altitudes_km: []const f64,
    layer_interval_indices_1based: []const u32,
    sublayer_top_altitudes_km: []const f64,
    sublayer_bottom_altitudes_km: []const f64,
    sublayer_mid_altitudes_km: []const f64,
    sublayer_support_weights_km: []const f64,
    sublayer_parent_interval_indices_1based: []const u32,
};
// ------------------------------------------------------------------------------------------------------------  |

pub fn scaleOpticalDepth(
    optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    wavelength_nm: f64,
) f64 {
    // scaleOpticalDepth --------------------------------------------------------------------------------------- |
    // Applies the Angstrom wavelength scaling used for aerosol reference optical depth.                         |
    //                                                                                                           |
    // math                                                                                                      |
    //   tau(lambda) = tau_ref * (lambda_ref / lambda) ^ Angstrom exponent                                       |
    // --------------------------------------------------------------------------------------------------------  |

    if (optical_depth == 0.0) return 0.0;
    if (angstrom_exponent == 0.0) return optical_depth;
    if (reference_wavelength_nm == wavelength_nm) return optical_depth;

    const safe_wavelength = @max(wavelength_nm, 1.0);
    const safe_reference = @max(reference_wavelength_nm, 1.0);

    return optical_depth * std.math.pow(f64, safe_reference / safe_wavelength, angstrom_exponent);
}

pub fn buildAerosolSublayerDistribution(
    allocator: Allocator,
    scene: *const Scene,
    grid: PreparedVerticalGrid,
) ![]f64 {
    // buildAerosolSublayerDistribution ----------------------------------------------------------------------   |
    // Chooses aerosol placement semantics and returns one per-sublayer optical-depth distribution.              |
    //                                                                                                           |
    // hot path                                                                                                  |
    //   Runs during optical-state preparation. The returned weights are read repeatedly by layer and carrier    |
    //   paths, so placement branches stay out of wavelength-time loops.                                         |
    // -------------------------------------------------------------------------------------------------------   |

    const total_optical_depth = scene.aerosol.optical_depth;
    return buildPlacementBoundDistribution(
        allocator,
        grid,
        scene.atmosphere.interval_grid.enabled(),
        scene.atmosphere.has_aerosols and scene.aerosol.enabled and total_optical_depth > 0.0,
        total_optical_depth,
        scene.aerosol.placement,
    );
}

pub fn buildPlacementBoundDistribution(
    allocator: Allocator,
    grid: PreparedVerticalGrid,
    has_explicit_interval_grid: bool,
    enabled: bool,
    total_optical_depth: f64,
    placement: AtmosphereModel.IntervalPlacement,
) ![]f64 {
    if (placement.interval_index_1based != 0) {
        if (!has_explicit_interval_grid) return error.InvalidRequest;
        return buildIntervalMatchedDistribution(
            allocator,
            grid,
            enabled,
            total_optical_depth,
            placement.interval_index_1based,
        );
    }
    return buildFiniteLayerSublayerDistribution(
        allocator,
        grid,
        enabled,
        total_optical_depth,
        placement.bottom_altitude_km,
        placement.top_altitude_km,
        false,
    );
}

pub fn buildIntervalMatchedDistribution(
    allocator: Allocator,
    grid: PreparedVerticalGrid,
    enabled: bool,
    total_optical_depth: f64,
    interval_index_1based: u32,
) ![]f64 {
    // buildIntervalMatchedDistribution ----------------------------------------------------------------------   |
    // Places all aerosol optical depth on sublayers belonging to one explicit interval.                         |
    //                                                                                                           |
    // math                                                                                                      |
    //   tau_i = total_tau * max(support_weight_i, 0) / sum_selected max(support_weight, 0)                      |
    // -------------------------------------------------------------------------------------------------------   |

    const weights = try allocator.alloc(f64, grid.sublayer_mid_altitudes_km.len);
    errdefer allocator.free(weights);

    if (!enabled or total_optical_depth == 0.0 or interval_index_1based == 0) {
        @memset(weights, 0.0);
        return weights;
    }

    var total_weight: f64 = 0.0;
    for (
        weights,
        grid.sublayer_parent_interval_indices_1based,
        grid.sublayer_support_weights_km,
    ) |*slot, parent_interval_index_1based, support_weight_km| {
        if (parent_interval_index_1based != interval_index_1based) {
            slot.* = 0.0;
            continue;
        }
        const weight = @max(support_weight_km, 0.0);
        slot.* = weight;
        total_weight += weight;
    }

    if (total_weight == 0.0) {
        return error.InvalidRequest;
    }
    for (weights) |*slot| slot.* = total_optical_depth * (slot.* / total_weight);
    return weights;
}

pub fn buildFiniteLayerSublayerDistribution(
    allocator: Allocator,
    grid: PreparedVerticalGrid,
    enabled: bool,
    total_optical_depth: f64,
    bottom_altitude_km: f64,
    top_altitude_km: f64,
    pad_to_slot_height: bool,
) ![]f64 {
    // buildFiniteLayerSublayerDistribution ------------------------------------------------------------------   |
    // Distributes aerosol optical depth by vertical overlap with a finite altitude interval.                    |
    //                                                                                                           |
    // math                                                                                                      |
    //   weight_i = max(support_i, 0) * overlap(slot_i, layer) / slot_height_i                                   |
    //   tau_i   = total_tau * weight_i / sum(weight)                                                            |
    // -------------------------------------------------------------------------------------------------------   |

    const weights = try allocator.alloc(f64, grid.sublayer_mid_altitudes_km.len);
    errdefer allocator.free(weights);

    if (!enabled or total_optical_depth == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }

    var layer_bottom_km = @max(bottom_altitude_km, 0.0);
    var layer_top_km = @max(top_altitude_km, layer_bottom_km);
    if (pad_to_slot_height and grid.sublayer_top_altitudes_km.len != 0) {
        const center_km = 0.5 * (layer_top_km + layer_bottom_km);
        const slot_height_km = @max(
            grid.sublayer_top_altitudes_km[0] - grid.sublayer_bottom_altitudes_km[0],
            1.0e-9,
        );
        const padded_half_thickness_km = 0.5 * @max(layer_top_km - layer_bottom_km, slot_height_km);
        const grid_top_km = grid.sublayer_top_altitudes_km[grid.sublayer_top_altitudes_km.len - 1];
        layer_bottom_km = @max(center_km - padded_half_thickness_km, 0.0);
        layer_top_km = @min(center_km + padded_half_thickness_km, grid_top_km);
    }

    var total_weight: f64 = 0.0;
    for (
        weights,
        grid.sublayer_top_altitudes_km,
        grid.sublayer_bottom_altitudes_km,
        grid.sublayer_support_weights_km,
    ) |*slot, slot_top_km, slot_bottom_km, support_weight_km| {
        const slot_height_km = @max(slot_top_km - slot_bottom_km, 1.0e-9);
        const overlap_km = @max(
            0.0,
            @min(slot_top_km, layer_top_km) - @max(slot_bottom_km, layer_bottom_km),
        );
        const weight = @max(support_weight_km, 0.0) * (overlap_km / slot_height_km);
        slot.* = weight;
        total_weight += weight;
    }

    if (total_weight == 0.0) {
        const nearest_index = nearestSublayerIndex(
            grid.sublayer_mid_altitudes_km,
            0.5 * (layer_top_km + layer_bottom_km),
        );
        if (nearest_index) |index| {
            weights[index] = 1.0;
            total_weight = 1.0;
        }
    }

    if (total_weight == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }
    for (weights) |*slot| slot.* = total_optical_depth * (slot.* / total_weight);
    return weights;
}

pub fn buildGaussianSublayerDistribution(
    allocator: Allocator,
    grid: PreparedVerticalGrid,
    enabled: bool,
    total_optical_depth: f64,
    center_km: f64,
    width_km: f64,
) ![]f64 {
    // buildGaussianSublayerDistribution ---------------------------------------------------------------------   |
    // Distributes aerosol optical depth with a Gaussian altitude weight.                                        |
    //                                                                                                           |
    // math                                                                                                      |
    //   delta_i = (z_i - center) / max(width, 0.25)                                                             |
    //   weight_i = exp(-0.5 * delta_i^2) * max(support_i, 0)                                                    |
    //   tau_i = total_tau * weight_i / sum(weight)                                                              |
    // -------------------------------------------------------------------------------------------------------   |

    const weights = try allocator.alloc(f64, grid.sublayer_mid_altitudes_km.len);
    errdefer allocator.free(weights);

    if (!enabled or total_optical_depth == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }

    var total_weight: f64 = 0.0;
    for (
        weights,
        grid.sublayer_mid_altitudes_km,
        grid.sublayer_support_weights_km,
    ) |*slot, altitude_km, support_weight_km| {
        const delta = (altitude_km - center_km) / @max(width_km, 0.25);
        const weight = @exp(-0.5 * delta * delta) * @max(support_weight_km, 0.0);
        slot.* = weight;
        total_weight += weight;
    }
    if (total_weight == 0.0) total_weight = 1.0;
    for (weights) |*slot| slot.* = total_optical_depth * (slot.* / total_weight);
    return weights;
}

fn nearestSublayerIndex(altitudes_km: []const f64, target_altitude_km: f64) ?usize {
    if (altitudes_km.len == 0) return null;
    var best_index: usize = 0;
    var best_distance = std.math.inf(f64);
    for (altitudes_km, 0..) |altitude_km, index| {
        const distance = @abs(altitude_km - target_altitude_km);
        if (distance < best_distance) {
            best_distance = distance;
            best_index = index;
        }
    }
    return best_index;
}
