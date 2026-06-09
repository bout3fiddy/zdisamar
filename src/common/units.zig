const std = @import("std");

pub const Error = error{
    InvalidRange,
    InvalidValue,
};

// units.zig --------------------------------------------------------------------------------------------------|
// Shared scalar range and angle wrappers used by scene input, adapters, and validation code.                  |
//                                                                                                             |
// names                                                                                                       |
//   WavelengthRange  : nanometer spectral interval                                                            |
//   AltitudeRangeKm  : kilometer altitude interval                                                            |
//   PressureRangeHpa : pressure interval in hPa, ordered top then bottom                                      |
//   AngleDeg         : finite angle wrapper without range limits                                              |
//   ZenithAngleDeg   : angle constrained to [0, 180] degrees                                                  |
//   AzimuthAngleDeg  : angle constrained to [0, 360] degrees                                                  |
//                                                                                                             |
// memory                                                                                                      |
//   These wrappers are small value types. Arrays, owning structs, and stack locals decide the live count.     |
// ------------------------------------------------------------------------------------------------------------|

// WavelengthRange --------------------------------------------------------------------------------------------|
// Stores the spectral interval used before any wavenumber-space transform.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] start_nm : f64                                                                                     |
// [ 8..15] end_nm   : f64                                                                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                      |
pub const WavelengthRange = struct {

    // Both bounds stay in nanometers because the public scene model expresses spectral coverage on that grid.
    start_nm: f64 = 270.0,
    end_nm: f64 = 2400.0,

    pub fn validate(self: WavelengthRange) Error!void {
        if (!std.math.isFinite(self.start_nm) or !std.math.isFinite(self.end_nm)) {
            return Error.InvalidValue;
        }
        if (self.end_nm <= self.start_nm) {
            return Error.InvalidRange;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|

// AltitudeRangeKm --------------------------------------------------------------------------------------------|
// Stores the altitude interval used by atmosphere and aerosol-layer inputs.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] bottom_km : f64                                                                                    |
// [ 8..15] top_km    : f64                                                                                    |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                      |
pub const AltitudeRangeKm = struct {
    bottom_km: f64 = 0.0,
    top_km: f64 = 0.0,

    pub fn validate(self: AltitudeRangeKm) Error!void {
        if (!std.math.isFinite(self.bottom_km) or !std.math.isFinite(self.top_km)) {
            return Error.InvalidValue;
        }
        if (self.bottom_km < 0.0 or self.top_km < self.bottom_km) {
            return Error.InvalidRange;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|

// PressureRangeHpa -------------------------------------------------------------------------------------------|
// Stores a pressure interval in the top-to-bottom order used by vertical-grid code.                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] top_hpa    : f64                                                                                   |
// [ 8..15] bottom_hpa : f64                                                                                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                      |
pub const PressureRangeHpa = struct {
    top_hpa: f64 = 0.0,
    bottom_hpa: f64 = 0.0,

    pub fn validate(self: PressureRangeHpa) Error!void {
        if (!std.math.isFinite(self.top_hpa) or !std.math.isFinite(self.bottom_hpa)) {
            return Error.InvalidValue;
        }
        if (self.top_hpa <= 0.0 or self.bottom_hpa <= 0.0 or self.bottom_hpa < self.top_hpa) {
            return Error.InvalidRange;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|

// AngleDeg ---------------------------------------------------------------------------------------------------|
// Stores one finite angle value in degrees without applying a physical range limit.                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] value : f64                                                                                          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 8 B (0.008 KiB); total = per instance * live instance count                       |
pub const AngleDeg = struct {

    // Degrees match the geometry parameters used by the scene model and vendor-facing adapters.
    value: f64 = 0.0,

    pub fn validate(self: AngleDeg) Error!void {
        if (!std.math.isFinite(self.value)) {
            return Error.InvalidValue;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|

// ZenithAngleDeg ---------------------------------------------------------------------------------------------|
// Stores a zenith angle constrained to the inclusive physical range used by scene geometry.                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] value : f64                                                                                          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 8 B (0.008 KiB); total = per instance * live instance count                       |
pub const ZenithAngleDeg = struct {
    value: f64 = 0.0,

    pub fn validate(self: ZenithAngleDeg) Error!void {
        try (AngleDeg{ .value = self.value }).validate();
        if (self.value < 0.0 or self.value > 180.0) {
            return Error.InvalidRange;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|

// AzimuthAngleDeg --------------------------------------------------------------------------------------------|
// Stores an azimuth angle constrained to the inclusive scene-geometry range.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] value : f64                                                                                          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 8 B (0.008 KiB); total = per instance * live instance count                       |
pub const AzimuthAngleDeg = struct {
    value: f64 = 0.0,

    pub fn validate(self: AzimuthAngleDeg) Error!void {
        try (AngleDeg{ .value = self.value }).validate();
        if (self.value < 0.0 or self.value > 360.0) {
            return Error.InvalidRange;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|
