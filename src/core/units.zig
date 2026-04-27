const std = @import("std");

pub const Error = error{
    InvalidRange,
    InvalidValue,
};

pub const WavelengthRange = struct {
    // UNITS:
    //   Both bounds are stored in nanometers because the public scene model expresses
    //   spectral coverage on that grid before any wavenumber-space transforms.
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

pub const AngleDeg = struct {
    // UNITS:
    //   Stored in degrees to match the geometry parameters used by the canonical scene
    //   model and vendor-facing adapter layers.
    value: f64 = 0.0,

    pub fn validate(self: AngleDeg) Error!void {
        if (!std.math.isFinite(self.value)) {
            return Error.InvalidValue;
        }
    }
};

pub const ZenithAngleDeg = struct {
    value: f64 = 0.0,

    pub fn validate(self: ZenithAngleDeg) Error!void {
        try (AngleDeg{ .value = self.value }).validate();
        if (self.value < 0.0 or self.value > 180.0) {
            return Error.InvalidRange;
        }
    }
};

pub const AzimuthAngleDeg = struct {
    value: f64 = 0.0,

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

test "altitude and pressure ranges enforce physical ordering" {
    try (AltitudeRangeKm{ .bottom_km = 0.0, .top_km = 2.5 }).validate();
    try (PressureRangeHpa{ .top_hpa = 150.0, .bottom_hpa = 900.0 }).validate();
    try std.testing.expectError(Error.InvalidRange, (AltitudeRangeKm{
        .bottom_km = 3.0,
        .top_km = 2.0,
    }).validate());
    try std.testing.expectError(Error.InvalidRange, (PressureRangeHpa{
        .top_hpa = 900.0,
        .bottom_hpa = 150.0,
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
