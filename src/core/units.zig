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
