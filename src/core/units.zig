//! Purpose:
//!   Define lightweight typed unit wrappers and validation helpers shared across the
//!   canonical scene and request model.
//!
//! Physics:
//!   These types encode basic spectral and angular domains used by atmospheric geometry
//!   and measurement setup before more detailed kernels consume them.
//!
//! Vendor:
//!   `geometry and spectral domain validation stage`
//!
//! Design:
//!   The Zig port uses tiny validated wrapper structs instead of passing raw scalars
//!   through the pipeline, which keeps unit intent explicit at API boundaries.
//!
//! Invariants:
//!   Wavelength intervals must be finite and strictly increasing, zenith angles stay in
//!   `[0, 180]` degrees, and azimuth angles stay in `[0, 360]` degrees.
//!
//! Validation:
//!   Unit tests below cover inverted spectral intervals, NaN rejection, and physical
//!   angle range enforcement.
const std = @import("std");

/// Purpose:
///   Report validation failures for typed scalar and interval wrappers.
pub const Error = error{
    InvalidRange,
    InvalidValue,
};

/// Purpose:
///   Represent an interval on the wavelength axis.
pub const WavelengthRange = struct {
    // UNITS:
    //   Both bounds are stored in nanometers because the public scene model expresses
    //   spectral coverage on that grid before any wavenumber-space transforms.
    start_nm: f64 = 270.0,
    end_nm: f64 = 2400.0,

    /// Purpose:
    ///   Ensure the wavelength interval is finite and strictly increasing.
    pub fn validate(self: WavelengthRange) Error!void {
        if (!std.math.isFinite(self.start_nm) or !std.math.isFinite(self.end_nm)) {
            return Error.InvalidValue;
        }
        if (self.end_nm <= self.start_nm) {
            return Error.InvalidRange;
        }
    }
};

/// Purpose:
///   Represent a generic angle in degrees.
pub const AngleDeg = struct {
    // UNITS:
    //   Stored in degrees to match the geometry parameters used by the canonical scene
    //   model and vendor-facing adapter layers.
    value: f64 = 0.0,

    /// Purpose:
    ///   Ensure the angle is finite.
    pub fn validate(self: AngleDeg) Error!void {
        if (!std.math.isFinite(self.value)) {
            return Error.InvalidValue;
        }
    }
};

/// Purpose:
///   Represent a zenith angle constrained to the physical `[0, 180]` degree range.
pub const ZenithAngleDeg = struct {
    value: f64 = 0.0,

    /// Purpose:
    ///   Ensure the zenith angle is finite and physically valid.
    pub fn validate(self: ZenithAngleDeg) Error!void {
        try (AngleDeg{ .value = self.value }).validate();
        if (self.value < 0.0 or self.value > 180.0) {
            return Error.InvalidRange;
        }
    }
};

/// Purpose:
///   Represent an azimuth angle constrained to the physical `[0, 360]` degree range.
pub const AzimuthAngleDeg = struct {
    value: f64 = 0.0,

    /// Purpose:
    ///   Ensure the azimuth angle is finite and physically valid.
    pub fn validate(self: AzimuthAngleDeg) Error!void {
        try (AngleDeg{ .value = self.value }).validate();
        if (self.value < 0.0 or self.value > 360.0) {
            return Error.InvalidRange;
        }
    }
};

test "wavelength range rejects inverted intervals" {
    try std.testing.expectError(Error.InvalidRange, (WavelengthRange{
        .start_nm = 465.0,
        .end_nm = 405.0,
    }).validate());
}

test "angle validation rejects NaN" {
    try std.testing.expectError(Error.InvalidValue, (AngleDeg{
        .value = std.math.nan(f64),
    }).validate());
}

test "zenith and azimuth helpers enforce physical angle ranges" {
    try (ZenithAngleDeg{ .value = 95.0 }).validate();
    try (AzimuthAngleDeg{ .value = 270.0 }).validate();
    try std.testing.expectError(Error.InvalidRange, (ZenithAngleDeg{ .value = -1.0 }).validate());
    try std.testing.expectError(Error.InvalidRange, (AzimuthAngleDeg{ .value = 361.0 }).validate());
}
