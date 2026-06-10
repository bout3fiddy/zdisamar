const std = @import("std");
const errors = @import("../common/errors.zig");

// Surface.zig ------------------------------------------------------------------------------------------------|
// Public lower-boundary surface row. It keeps the user-facing Lambertian albedo beside optional surface       |
// pressure metadata, then Scene and preparation code decide which parts affect the forward run.               |
//                                                                                                             |
// route                                                                                                       |
//   Scene.surface                                                                                             |
//     -> Scene.validate calls Surface.validate before optical preparation                                     |
//     -> Scene.lutCompatibilityKey hashes albedo because generated reflectance LUTs depend on the lower       |
//        boundary reflectance                                                                                 |
//     -> input/o2a_reference/run.zig fills the row from resolved O2 A case metadata                           |
//     -> forward_layers copies albedo into radiative_transfer.ForwardInput                                    |
//     -> LABOS directSurfaceOnly / fillSurface use albedo as the surface reflection boundary                  |
//                                                                                                             |
// row model                                                                                                   |
//   albedo is hemispherical lower-boundary reflectance in [0, 1]. RTM code clamps again at the transport      |
//   handoff as a last guard, but invalid public input is rejected here.                                       |
//                                                                                                             |
//   pressure_hpa is an input-side lower-boundary pressure slot used by adapters and O2 A metadata. The        |
//   current forward path gets physical surface pressure through Atmosphere.surface_pressure_hpa and profile   |
//   preparation, so this row validates pressure metadata without feeding RTM pressure directly.               |
//                                                                                                             |
// Jacobian note                                                                                               |
//   LABOS surface-albedo sensitivity contributes only through the zero-Fourier surface term. This file does   |
//   not request Jacobians; it only protects the scalar albedo that later RTM code consumes.                   |
//                                                                                                             |
// memory                                                                                                      |
//   Surface is a 16 B value row with no referenced storage, ownership flag, or deinit path. It is copied as   |
//   part of Scene, LUT keys, and setup structs; no repeated spectral loop calls back into this file.          |
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
        // Surface.validate -----------------------------------------------------------------------------------|
        // Validate scalar lower-boundary metadata before Scene can be prepared.                               |
        //                                                                                                     |
        // checks                                                                                              |
        //   albedo       : finite Lambertian reflectance in [0, 1]                                            |
        //   pressure_hpa : 0 means absent metadata; otherwise finite and positive hPa                         |
        //                                                                                                     |
        // behavior                                                                                            |
        //   pressure_hpa is accepted as metadata even though Atmosphere owns the current forward pressure     |
        //   route. Keeping the validation here prevents adapters from carrying an invalid pressure value      |
        //   through Scene.                                                                                    |
        // ----------------------------------------------------------------------------------------------------|

        if (!std.math.isFinite(self.albedo) or self.albedo < 0.0 or self.albedo > 1.0) {
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
