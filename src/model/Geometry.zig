const errors = @import("../core/errors.zig");
const units = @import("../core/units.zig");
const std = @import("std");

const earth_radius_km = 6371.0;

pub const Model = enum {
    plane_parallel,
    pseudo_spherical,
    spherical,
};

pub const Geometry = struct {
    model: Model = .plane_parallel,
    // UNITS:
    //   All angles are stored in degrees at the public model boundary.
    solar_zenith_deg: f64 = 0.0,
    viewing_zenith_deg: f64 = 0.0,
    relative_azimuth_deg: f64 = 0.0,
    // UNITS:
    //   Optional surface altitude is stored in kilometers so interval and
    //   subcolumn preparation can preserve the reference lower boundary used by
    //   pseudo-spherical paths.
    surface_altitude_km: f64 = 0.0,

    pub fn validate(self: Geometry) errors.Error!void {
        (units.ZenithAngleDeg{ .value = self.solar_zenith_deg }).validate() catch return errors.Error.InvalidRequest;
        (units.ZenithAngleDeg{ .value = self.viewing_zenith_deg }).validate() catch return errors.Error.InvalidRequest;
        (units.AzimuthAngleDeg{ .value = self.relative_azimuth_deg }).validate() catch return errors.Error.InvalidRequest;
        if (!std.math.isFinite(self.surface_altitude_km) or self.surface_altitude_km < 0.0) {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn solarCosineAtAltitude(self: Geometry, altitude_km: f64) f64 {
        return self.propagationCosineAtAltitude(self.solar_zenith_deg, altitude_km);
    }

    pub fn viewingCosineAtAltitude(self: Geometry, altitude_km: f64) f64 {
        return self.propagationCosineAtAltitude(self.viewing_zenith_deg, altitude_km);
    }

    fn propagationCosineAtAltitude(self: Geometry, zenith_deg: f64, altitude_km: f64) f64 {
        const base_zenith_rad = std.math.degreesToRadians(zenith_deg);
        const base_mu = @cos(base_zenith_rad);
        if (self.model == .plane_parallel) {
            return @max(base_mu, 0.05);
        }

        const safe_altitude_km = @max(altitude_km, 0.0);
        const radius_ratio = earth_radius_km / (earth_radius_km + safe_altitude_km);
        const sin_at_altitude = std.math.clamp(@sin(base_zenith_rad) * radius_ratio, -0.999999, 0.999999);
        const local_mu = @sqrt(@max(1.0 - (sin_at_altitude * sin_at_altitude), 0.0));

        // GOTCHA:
        //   The cosine floor is parity-sensitive for long slant paths because removing it
        //   would let near-horizon rays explode radiative transfer path lengths upstream.
        return switch (self.model) {
            .plane_parallel => @max(base_mu, 0.05),
            .pseudo_spherical => @max(local_mu, 0.05),
            .spherical => @max(local_mu * radius_ratio, 0.05),
        };
    }
};

test "geometry rejects out-of-range zenith and azimuth angles" {
    try (Geometry{
        .solar_zenith_deg = 32.0,
        .viewing_zenith_deg = 9.0,
        .relative_azimuth_deg = 145.0,
    }).validate();

    try @import("std").testing.expectError(
        errors.Error.InvalidRequest,
        (Geometry{ .solar_zenith_deg = 181.0 }).validate(),
    );
    try @import("std").testing.expectError(
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
    try @import("std").testing.expectApproxEqAbs(@cos(std.math.degreesToRadians(70.0)), plane_mu, 1.0e-12);
    try @import("std").testing.expect(pseudo_mu >= plane_mu);
    try @import("std").testing.expect(pseudo_spherical.viewingCosineAtAltitude(12.0) >= plane_parallel.viewingCosineAtAltitude(12.0));
}
