//! Purpose:
//!   Define the observation geometry model and the cosine transforms needed by transport
//!   preparation and path-length evaluation.
//!
//! Physics:
//!   This file maps solar/viewing zenith angles and relative azimuth into local
//!   propagation cosines under plane-parallel, pseudo-spherical, and spherical geometry
//!   assumptions.
//!
//! Vendor:
//!   `geometry cosine preparation stage`
//!
//! Design:
//!   The Zig model keeps geometry as a small typed value with explicit helper methods
//!   rather than relying on shared mutable angle buffers threaded through kernels.
//!
//! Invariants:
//!   Angles are expressed in degrees, zenith and azimuth ranges are validated through the
//!   core unit wrappers, and cosine helpers clamp to a nonzero floor to avoid singular
//!   path lengths.
//!
//! Validation:
//!   Unit tests below exercise angle-range checks and the altitude-dependent cosine
//!   behavior for plane-parallel and pseudo-spherical modes.
const errors = @import("../core/errors.zig");
const units = @import("../core/units.zig");
const std = @import("std");

const earth_radius_km = 6371.0;

/// Purpose:
///   Select which geometric approximation the transport path uses.
pub const Model = enum {
    plane_parallel,
    pseudo_spherical,
    spherical,
};

/// Purpose:
///   Describe the observation geometry shared by forward and retrieval execution.
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

    /// Purpose:
    ///   Ensure the geometry parameters remain within physically valid angle ranges.
    pub fn validate(self: Geometry) errors.Error!void {
        (units.ZenithAngleDeg{ .value = self.solar_zenith_deg }).validate() catch return errors.Error.InvalidRequest;
        (units.ZenithAngleDeg{ .value = self.viewing_zenith_deg }).validate() catch return errors.Error.InvalidRequest;
        (units.AzimuthAngleDeg{ .value = self.relative_azimuth_deg }).validate() catch return errors.Error.InvalidRequest;
        if (!std.math.isFinite(self.surface_altitude_km) or self.surface_altitude_km < 0.0) {
            return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Compute the solar-beam propagation cosine at the requested altitude.
    pub fn solarCosineAtAltitude(self: Geometry, altitude_km: f64) f64 {
        return self.propagationCosineAtAltitude(self.solar_zenith_deg, altitude_km);
    }

    /// Purpose:
    ///   Compute the viewing-beam propagation cosine at the requested altitude.
    pub fn viewingCosineAtAltitude(self: Geometry, altitude_km: f64) f64 {
        return self.propagationCosineAtAltitude(self.viewing_zenith_deg, altitude_km);
    }

    /// Purpose:
    ///   Convert the top-of-atmosphere zenith angle into a local propagation cosine.
    ///
    /// Physics:
    ///   Pseudo-spherical and spherical modes contract the sine of the ray angle by the
    ///   Earth-radius ratio to approximate curvature effects with altitude.
    ///
    /// Units:
    ///   `zenith_deg` is in degrees and `altitude_km` is in kilometers.
    ///
    /// Assumptions:
    ///   Negative altitudes are clamped to sea level and the returned cosine is floored
    ///   to avoid singular slant-path amplification.
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
        //   would let near-horizon rays explode transport path lengths upstream.
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
