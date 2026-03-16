const std = @import("std");

pub const Error = error{
    InvalidRange,
    InvalidValue,
};

pub const WavelengthRange = struct {
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

pub const AngleDeg = struct {
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
