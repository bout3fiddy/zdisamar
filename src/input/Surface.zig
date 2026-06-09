const std = @import("std");
const errors = @import("../common/errors.zig");

// Surface.zig ------------------------------------------------------------------------------------------------|
// Public lower-boundary surface row used by scene validation, LUT identity, and RTM surface reflection.       |
//                                                                                                             |
// called from                                                                                                 |
//   Scene.validate rejects invalid albedo or pressure before input preparation.                               |
//   Scene.lutCompatibilityKey includes surface albedo because generated reflectance LUTs depend on it.        |
//   input/o2a_reference/run.zig fills the row from resolved O2 A case metadata.                               |
//   forward_layers copies albedo into radiative-transfer layer input; LABOS uses it in directSurfaceOnly and  |
//   fillSurface, with the surface-albedo Jacobian only contributing to the zero-Fourier term.                 |
//                                                                                                             |
// row model                                                                                                   |
//   albedo is hemispherical lower-boundary reflectance in [0, 1].                                             |
//   pressure_hpa is an input-side lower-boundary pressure slot validated for adapters and O2 A metadata. The  |
//   current forward path carries surface pressure through the atmosphere/profile preparation path instead.    |
//                                                                                                             |
// runtime shape                                                                                               |
//   This file is validation only. It does not load surface models or own reference data; optical preparation  |
//   and RTM code consume the validated albedo, while pressure remains metadata at this boundary.              |
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
