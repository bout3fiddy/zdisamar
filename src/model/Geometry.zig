const errors = @import("../core/errors.zig");
const units = @import("../core/units.zig");

pub const Model = enum {
    plane_parallel,
    pseudo_spherical,
    spherical,
};

pub const Geometry = struct {
    model: Model = .plane_parallel,
    solar_zenith_deg: f64 = 0.0,
    viewing_zenith_deg: f64 = 0.0,
    relative_azimuth_deg: f64 = 0.0,

    pub fn validate(self: Geometry) errors.Error!void {
        (units.ZenithAngleDeg{ .value = self.solar_zenith_deg }).validate() catch return errors.Error.InvalidRequest;
        (units.ZenithAngleDeg{ .value = self.viewing_zenith_deg }).validate() catch return errors.Error.InvalidRequest;
        (units.AzimuthAngleDeg{ .value = self.relative_azimuth_deg }).validate() catch return errors.Error.InvalidRequest;
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
