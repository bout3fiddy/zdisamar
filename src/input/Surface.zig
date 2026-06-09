const std = @import("std");
const errors = @import("../common/errors.zig");

// Surface.zig ------------------------------------------------------------------------------------------------|
// Public lower-boundary surface controls.                                                                     |
//                                                                                                             |
// data                                                                                                        |
//   Surface stores hemispherical albedo and an optional surface pressure in hPa.                              |
//                                                                                                             |
// validation                                                                                                  |
//   albedo is normalized to [0, 1]. Non-zero pressure must be finite and positive.                            |
// ------------------------------------------------------------------------------------------------------------|

// Surface ----------------------------------------------------------------------------------------------------|
// Scalar surface boundary header.                                                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] albedo       : f64                                                                                  |
// [8..15] pressure_hpa : f64                                                                                  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live surface count                       |
pub const Surface = struct {
    albedo: f64 = 0.0,
    pressure_hpa: f64 = 0.0,

    pub fn validate(self: Surface) errors.Error!void {
        if (self.albedo < 0.0 or self.albedo > 1.0) {
            return errors.Error.InvalidRequest;
        }

        if (self.pressure_hpa != 0.0 and
            (!std.math.isFinite(self.pressure_hpa) or self.pressure_hpa <= 0.0))
        {
            return errors.Error.InvalidRequest;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|
