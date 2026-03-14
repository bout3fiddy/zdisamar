const std = @import("std");

pub const Error = error{
    InvalidAxis,
    IndexOutOfRange,
};

pub const SpectralAxis = struct {
    start_nm: f64,
    end_nm: f64,
    sample_count: u32,

    pub fn validate(self: SpectralAxis) Error!void {
        if (self.sample_count < 2) return Error.InvalidAxis;
        if (self.end_nm <= self.start_nm) return Error.InvalidAxis;
    }

    pub fn stepNm(self: SpectralAxis) Error!f64 {
        try self.validate();
        return (self.end_nm - self.start_nm) / @as(f64, @floatFromInt(self.sample_count - 1));
    }

    pub fn wavelengthNm(self: SpectralAxis, sample_index: u32) Error!f64 {
        try self.validate();
        if (sample_index >= self.sample_count) return Error.IndexOutOfRange;
        return self.start_nm + (try self.stepNm()) * @as(f64, @floatFromInt(sample_index));
    }
};

pub const LayerAxis = struct {
    layer_count: u32,

    pub fn validate(self: LayerAxis) Error!void {
        if (self.layer_count == 0) return Error.InvalidAxis;
    }
};

pub const StateAxis = struct {
    parameter_count: u32,

    pub fn validate(self: StateAxis) Error!void {
        if (self.parameter_count == 0) return Error.InvalidAxis;
    }
};

test "spectral axis exposes deterministic step and wavelengths" {
    const axis = SpectralAxis{
        .start_nm = 400.0,
        .end_nm = 410.0,
        .sample_count = 6,
    };

    const step_nm = try axis.stepNm();
    try std.testing.expectApproxEqRel(@as(f64, 2.0), step_nm, 1e-12);

    const wavelength_3 = try axis.wavelengthNm(3);
    try std.testing.expectApproxEqRel(@as(f64, 406.0), wavelength_3, 1e-12);
}
