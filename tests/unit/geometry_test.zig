const std = @import("std");
const internal = @import("internal");

const geometry = internal.geometry;
const Geometry = geometry.Geometry;
const errors = internal.core.errors;

test "geometry rejects out-of-range zenith and azimuth angles" {
    try (Geometry{
        .solar_zenith_deg = 32.0,
        .viewing_zenith_deg = 9.0,
        .relative_azimuth_deg = 145.0,
    }).validate();

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (Geometry{ .solar_zenith_deg = 181.0 }).validate(),
    );
    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (Geometry{ .relative_azimuth_deg = 400.0 }).validate(),
    );
}

test "geometry models produce propagation cosines with altitude consequences" {
    const plane_parallel = Geometry{
        .model = .plane_parallel,
        .solar_zenith_deg = 70.0,
        .viewing_zenith_deg = 55.0,
    };
    const pseudo_spherical = Geometry{
        .model = .pseudo_spherical,
        .solar_zenith_deg = 70.0,
        .viewing_zenith_deg = 55.0,
    };

    const plane_mu = plane_parallel.solarCosineAtAltitude(12.0);
    const pseudo_mu = pseudo_spherical.solarCosineAtAltitude(12.0);
    try std.testing.expectApproxEqAbs(@cos(std.math.degreesToRadians(70.0)), plane_mu, 1.0e-12);
    try std.testing.expect(pseudo_mu >= plane_mu);
    try std.testing.expect(pseudo_spherical.viewingCosineAtAltitude(12.0) >= plane_parallel.viewingCosineAtAltitude(12.0));
}
