const std = @import("std");
const errors = @import("../common/errors.zig");

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: albedo=8 B, pressure_hpa=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const Surface = struct {
    // UNITS:
    //   `albedo` is a unitless hemispherical reflectance in the normalized `[0, 1]`
    //   range.
    albedo: f64 = 0.0,
    // UNITS:
    //   Optional surface pressure is expressed in hectopascals so canonical
    //   surface metadata can preserve the boundary pressure used by vendor-like
    //   interval configurations.
    pressure_hpa: f64 = 0.0,

    pub fn validate(self: Surface) errors.Error!void {
        if (self.albedo < 0.0 or self.albedo > 1.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.pressure_hpa != 0.0 and (!std.math.isFinite(self.pressure_hpa) or self.pressure_hpa <= 0.0)) {
            return errors.Error.InvalidRequest;
        }
    }
};
