const std = @import("std");
const Placement = @import("../../input/Atmosphere.zig").IntervalPlacement;

pub fn aerosolPlacement(aerosol: anytype) Placement {
    if (aerosol.placement.enabled()) return aerosol.placement;
    return .{
        .semantics = .altitude_center_width_approximation,
        .top_altitude_km = aerosol.layer_center_km + 0.5 * aerosol.layer_width_km,
        .bottom_altitude_km = @max(aerosol.layer_center_km - 0.5 * aerosol.layer_width_km, 0.0),
    };
}

pub fn cloudPlacement(cloud: anytype) Placement {
    if (cloud.placement.enabled()) return cloud.placement;
    return .{
        .semantics = .altitude_center_width_approximation,
        .top_altitude_km = cloud.top_altitude_km,
        .bottom_altitude_km = @max(cloud.top_altitude_km - cloud.thickness_km, 0.0),
    };
}

pub fn resolvedParticleSingleScatterAlbedos(
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    effective_single_scatter_albedo: f64,
) struct {
    aerosol: f64,
    cloud: f64,
} {
    return .{
        .aerosol = std.math.clamp(
            if (aerosol_single_scatter_albedo >= 0.0)
                aerosol_single_scatter_albedo
            else
                effective_single_scatter_albedo,
            0.0,
            1.0,
        ),
        .cloud = std.math.clamp(
            if (cloud_single_scatter_albedo >= 0.0)
                cloud_single_scatter_albedo
            else
                effective_single_scatter_albedo,
            0.0,
            1.0,
        ),
    };
}
