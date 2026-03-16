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
        (units.AngleDeg{ .value = self.solar_zenith_deg }).validate() catch return errors.Error.InvalidRequest;
        (units.AngleDeg{ .value = self.viewing_zenith_deg }).validate() catch return errors.Error.InvalidRequest;
        (units.AngleDeg{ .value = self.relative_azimuth_deg }).validate() catch return errors.Error.InvalidRequest;
    }
};
