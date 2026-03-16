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
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    layer_count: u32,
    sublayer_divisions: u32,
) ![]f64 {
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
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    layer_count: u32,
    sublayer_divisions: u32,
) ![]f64 {
    const cloud_center_km = scene.cloud.top_altitude_km - 0.5 * scene.cloud.thickness_km;
    return buildGaussianSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
        scene.atmosphere.has_clouds and scene.cloud.enabled and scene.cloud.optical_thickness > 0.0,
        scene.cloud.optical_thickness,
        cloud_center_km,
        @max(scene.cloud.thickness_km * 0.5, 0.25),
    );
}

pub fn buildGaussianSublayerDistribution(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
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
