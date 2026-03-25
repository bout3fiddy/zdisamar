const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const AtmosphereModel = @import("../../../model/Atmosphere.zig");
const Allocator = std.mem.Allocator;

pub const PreparedVerticalGrid = struct {
    layer_top_altitudes_km: []const f64,
    layer_bottom_altitudes_km: []const f64,
    layer_interval_indices_1based: []const u32,
    sublayer_top_altitudes_km: []const f64,
    sublayer_bottom_altitudes_km: []const f64,
    sublayer_mid_altitudes_km: []const f64,
    sublayer_parent_interval_indices_1based: []const u32,
};

pub fn scaleOpticalDepth(
    optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    wavelength_nm: f64,
) f64 {
    if (optical_depth == 0.0) return 0.0;
    const safe_wavelength = @max(wavelength_nm, 1.0);
    const safe_reference = @max(reference_wavelength_nm, 1.0);
    return optical_depth * std.math.pow(f64, safe_reference / safe_wavelength, angstrom_exponent);
}

pub fn buildAerosolSublayerDistribution(
    allocator: Allocator,
    scene: *const Scene,
    grid: PreparedVerticalGrid,
) ![]f64 {
    const total_optical_depth = scene.aerosol.optical_depth;
    if (scene.aerosol.placement.semantics == .explicit_interval_bounds) {
        return buildPlacementBoundDistribution(
            allocator,
            grid,
            scene.atmosphere.has_aerosols and scene.aerosol.enabled and total_optical_depth > 0.0,
            total_optical_depth,
            scene.aerosol.placement,
        );
    }
    if (scene.aerosol.aerosol_type == .hg_scattering) {
        const placement = scene.aerosol.resolvedPlacement();
        return buildFiniteLayerSublayerDistribution(
            allocator,
            grid,
            scene.atmosphere.has_aerosols and scene.aerosol.enabled and total_optical_depth > 0.0,
            total_optical_depth,
            placement.bottom_altitude_km,
            placement.top_altitude_km,
        );
    }
    return buildGaussianSublayerDistribution(
        allocator,
        grid,
        scene.atmosphere.has_aerosols and scene.aerosol.enabled and total_optical_depth > 0.0,
        total_optical_depth,
        scene.aerosol.layer_center_km,
        scene.aerosol.layer_width_km,
    );
}

pub fn buildCloudSublayerDistribution(
    allocator: Allocator,
    scene: *const Scene,
    grid: PreparedVerticalGrid,
) ![]f64 {
    const total_optical_depth = scene.cloud.optical_thickness;
    const placement = scene.cloud.resolvedPlacement();
    if (scene.cloud.placement.semantics == .explicit_interval_bounds) {
        return buildPlacementBoundDistribution(
            allocator,
            grid,
            scene.atmosphere.has_clouds and scene.cloud.enabled and total_optical_depth > 0.0,
            total_optical_depth,
            scene.cloud.placement,
        );
    }
    return buildFiniteLayerSublayerDistribution(
        allocator,
        grid,
        scene.atmosphere.has_clouds and scene.cloud.enabled and total_optical_depth > 0.0,
        total_optical_depth,
        placement.bottom_altitude_km,
        placement.top_altitude_km,
    );
}

pub fn buildPlacementBoundDistribution(
    allocator: Allocator,
    grid: PreparedVerticalGrid,
    enabled: bool,
    total_optical_depth: f64,
    placement: AtmosphereModel.IntervalPlacement,
) ![]f64 {
    if (placement.interval_index_1based != 0) {
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
    );
}

pub fn buildIntervalMatchedDistribution(
    allocator: Allocator,
    grid: PreparedVerticalGrid,
    enabled: bool,
    total_optical_depth: f64,
    interval_index_1based: u32,
) ![]f64 {
    const weights = try allocator.alloc(f64, grid.sublayer_mid_altitudes_km.len);
    errdefer allocator.free(weights);

    if (!enabled or total_optical_depth == 0.0 or interval_index_1based == 0) {
        @memset(weights, 0.0);
        return weights;
    }

    var total_weight: f64 = 0.0;
    for (weights, grid.sublayer_parent_interval_indices_1based, grid.sublayer_top_altitudes_km, grid.sublayer_bottom_altitudes_km) |*slot, parent_interval_index_1based, top_altitude_km, bottom_altitude_km| {
        if (parent_interval_index_1based != interval_index_1based) {
            slot.* = 0.0;
            continue;
        }
        const weight = @max(top_altitude_km - bottom_altitude_km, 0.0);
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
) ![]f64 {
    const weights = try allocator.alloc(f64, grid.sublayer_mid_altitudes_km.len);
    errdefer allocator.free(weights);

    if (!enabled or total_optical_depth == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }

    const layer_bottom_km = @max(bottom_altitude_km, 0.0);
    const layer_top_km = @max(top_altitude_km, layer_bottom_km);

    var total_weight: f64 = 0.0;
    for (weights, grid.sublayer_top_altitudes_km, grid.sublayer_bottom_altitudes_km) |*slot, slot_top_km, slot_bottom_km| {
        const slot_height_km = @max(slot_top_km - slot_bottom_km, 1.0e-9);
        const overlap_km = @max(
            0.0,
            @min(slot_top_km, layer_top_km) - @max(slot_bottom_km, layer_bottom_km),
        );
        const weight = overlap_km / slot_height_km;
        slot.* = weight;
        total_weight += weight;
    }

    if (total_weight == 0.0) {
        const nearest_index = nearestSublayerIndex(grid.sublayer_mid_altitudes_km, 0.5 * (layer_top_km + layer_bottom_km));
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
    const weights = try allocator.alloc(f64, grid.sublayer_mid_altitudes_km.len);
    errdefer allocator.free(weights);

    if (!enabled or total_optical_depth == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }

    var total_weight: f64 = 0.0;
    for (weights, grid.sublayer_mid_altitudes_km) |*slot, altitude_km| {
        const delta = (altitude_km - center_km) / @max(width_km, 0.25);
        const weight = @exp(-0.5 * delta * delta);
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
