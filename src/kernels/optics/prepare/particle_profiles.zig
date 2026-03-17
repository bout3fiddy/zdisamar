const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const Allocator = std.mem.Allocator;

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
    profile: *const ReferenceData.ClimatologyProfile,
    layer_count: u32,
    sublayer_divisions: u32,
) ![]f64 {
    if (std.mem.eql(u8, scene.aerosol.model, "hg_layer")) {
        return buildFiniteLayerSublayerDistribution(
            allocator,
            profile,
            layer_count,
            sublayer_divisions,
            scene.atmosphere.has_aerosols and scene.aerosol.enabled and scene.aerosol.optical_depth > 0.0,
            scene.aerosol.optical_depth,
            scene.aerosol.layer_center_km,
            scene.aerosol.layer_width_km,
        );
    }
    return buildGaussianSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
        scene.atmosphere.has_aerosols and scene.aerosol.enabled and scene.aerosol.optical_depth > 0.0,
        scene.aerosol.optical_depth,
        scene.aerosol.layer_center_km,
        scene.aerosol.layer_width_km,
    );
}

pub fn buildCloudSublayerDistribution(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    layer_count: u32,
    sublayer_divisions: u32,
) ![]f64 {
    const cloud_center_km = scene.cloud.top_altitude_km - 0.5 * scene.cloud.thickness_km;
    return buildFiniteLayerSublayerDistribution(
        allocator,
        profile,
        layer_count,
        sublayer_divisions,
        scene.atmosphere.has_clouds and scene.cloud.enabled and scene.cloud.optical_thickness > 0.0,
        scene.cloud.optical_thickness,
        cloud_center_km,
        scene.cloud.thickness_km,
    );
}

pub fn buildFiniteLayerSublayerDistribution(
    allocator: Allocator,
    profile: *const ReferenceData.ClimatologyProfile,
    layer_count: u32,
    sublayer_divisions: u32,
    enabled: bool,
    total_optical_depth: f64,
    center_km: f64,
    thickness_km: f64,
) ![]f64 {
    const weights = try allocator.alloc(f64, @as(usize, layer_count) * @as(usize, sublayer_divisions));
    errdefer allocator.free(weights);

    if (!enabled or total_optical_depth == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }

    const altitude_span = @max(profile.maxAltitude(), 1.0);
    const total_slots = @as(usize, layer_count) * @as(usize, sublayer_divisions);
    const slot_height_km = altitude_span / @as(f64, @floatFromInt(total_slots));
    const half_thickness_km = 0.5 * @max(thickness_km, slot_height_km);
    const layer_bottom_km = @max(center_km - half_thickness_km, 0.0);
    const layer_top_km = @min(center_km + half_thickness_km, altitude_span);

    var total_weight: f64 = 0.0;
    for (weights, 0..) |*slot, index| {
        const slot_bottom_km = slot_height_km * @as(f64, @floatFromInt(index));
        const slot_top_km = slot_bottom_km + slot_height_km;
        const overlap_km = @max(
            0.0,
            @min(slot_top_km, layer_top_km) - @max(slot_bottom_km, layer_bottom_km),
        );
        const weight = overlap_km / slot_height_km;
        slot.* = weight;
        total_weight += weight;
    }

    if (total_weight == 0.0) {
        const nearest_index = std.math.clamp(
            @as(isize, @intFromFloat(@round(center_km / slot_height_km - 0.5))),
            0,
            @as(isize, @intCast(total_slots - 1)),
        );
        weights[@as(usize, @intCast(nearest_index))] = 1.0;
        total_weight = 1.0;
    }

    for (weights) |*slot| slot.* = total_optical_depth * (slot.* / total_weight);
    return weights;
}

pub fn buildGaussianSublayerDistribution(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    layer_count: u32,
    sublayer_divisions: u32,
    enabled: bool,
    total_optical_depth: f64,
    center_km: f64,
    width_km: f64,
) ![]f64 {
    _ = scene;
    const weights = try allocator.alloc(f64, @as(usize, layer_count) * @as(usize, sublayer_divisions));
    errdefer allocator.free(weights);

    if (!enabled or total_optical_depth == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }

    var total_weight: f64 = 0.0;
    const altitude_span = @max(profile.maxAltitude(), 1.0);
    const total_slots = @as(usize, layer_count) * @as(usize, sublayer_divisions);
    for (weights, 0..) |*slot, index| {
        const altitude_fraction = (@as(f64, @floatFromInt(index)) + 0.5) / @as(f64, @floatFromInt(total_slots));
        const altitude_km = altitude_span * altitude_fraction;
        const delta = (altitude_km - center_km) / @max(width_km, 0.25);
        const weight = @exp(-0.5 * delta * delta);
        slot.* = weight;
        total_weight += weight;
    }
    if (total_weight == 0.0) total_weight = 1.0;
    for (weights) |*slot| slot.* = total_optical_depth * (slot.* / total_weight);
    return weights;
}
