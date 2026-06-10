const errors = @import("../common/errors.zig");
const units = @import("../common/units.zig");
const std = @import("std");

const earth_radius_km = 6371.0;

// Geometry.zig -----------------------------------------------------------------------------------------------|
// Observation geometry controls and altitude-adjusted propagation cosines for RTM preparation.                |
//                                                                                                             |
// used by                                                                                                     |
//   Scene validation and LUT compatibility keys store the public geometry angles                              |
//   pseudo-spherical optical-property builders sample propagation cosines by altitude                         |
//   spectral_forward.zig scales LABOS reflectance factors into radiance using solar cosine                    |
//   output diagnostics and budgets use the same angle row for airmass-style summaries                         |
//                                                                                                             |
// main paths                                                                                                  |
//   validate checks zenith/azimuth ranges and non-negative surface altitude                                   |
//   solarCosineAtAltitude and viewingCosineAtAltitude share propagationCosineAtAltitude                       |
//   plane_parallel keeps the base cosine; pseudo_spherical/spherical adjust for Earth radius and altitude     |
//                                                                                                             |
// runtime shape                                                                                               |
//   Geometry is a small value row stored inside Scene and copied into compatibility keys. It owns no buffers, |
//   allocates nothing, and leaves all altitude-dependent work as scalar math in the methods below.            |
//                                                                                                             |
// math                                                                                                        |
//   radius_ratio = R_earth / (R_earth + altitude). Near-horizon paths keep a cosine floor of 0.05 so path     |
//   lengths remain bounded and parity-sensitive long slant paths do not explode numerically.                  |
// ------------------------------------------------------------------------------------------------------------|

pub const Model = enum {
    plane_parallel,
    pseudo_spherical,
    spherical,
};

// Geometry ---------------------------------------------------------------------------------------------------|
// Public geometry header.                                                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] solar_zenith_deg     : f64                                                                         |
// [ 8..15] viewing_zenith_deg   : f64                                                                         |
// [16..23] relative_azimuth_deg : f64                                                                         |
// [24..31] surface_altitude_km  : f64                                                                         |
// [32..32] model                : Model                                                                       |
// [33..39] trailing padding     : 7 B                                                                         |
//                                                                                                             |
// unused bits: 56 padding + 6 enum-storage slack = 62 bits                                                    |
// footprint: per instance = 40 B (0.039 KiB); total = per instance * live geometry count                      |
pub const Geometry = struct {
    model: Model = .plane_parallel,
    solar_zenith_deg: f64 = 0.0,
    viewing_zenith_deg: f64 = 0.0,
    relative_azimuth_deg: f64 = 0.0,
    surface_altitude_km: f64 = 0.0,

    pub fn validate(self: Geometry) errors.Error!void {
        (units.ZenithAngleDeg{
            .value = self.solar_zenith_deg,
        }).validate() catch return errors.Error.InvalidRequest;
        (units.ZenithAngleDeg{
            .value = self.viewing_zenith_deg,
        }).validate() catch return errors.Error.InvalidRequest;
        (units.AzimuthAngleDeg{
            .value = self.relative_azimuth_deg,
        }).validate() catch return errors.Error.InvalidRequest;

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
        const sin_at_altitude = std.math.clamp(
            @sin(base_zenith_rad) * radius_ratio,
            -0.999999,
            0.999999,
        );
        const local_mu = @sqrt(@max(1.0 - (sin_at_altitude * sin_at_altitude), 0.0));

        // Keep the cosine floor for parity-sensitive long slant paths.
        return switch (self.model) {
            .plane_parallel => @max(base_mu, 0.05),
            .pseudo_spherical => @max(local_mu, 0.05),
            .spherical => @max(local_mu * radius_ratio, 0.05),
        };
    }
};
// ------------------------------------------------------------------------------------------------------------|
