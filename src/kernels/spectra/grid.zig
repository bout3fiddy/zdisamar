const std = @import("std");

pub const Error = error{
    InvalidSampleCount,
    InvalidBounds,
    IndexOutOfRange,
    InvalidExplicitSamples,
};

pub const SpectralGrid = struct {
    start_nm: f64,
    end_nm: f64,
    sample_count: u32,

    pub fn validate(self: SpectralGrid) Error!void {
        if (self.sample_count < 2) return Error.InvalidSampleCount;
        if (self.end_nm <= self.start_nm) return Error.InvalidBounds;
    }

    pub fn sampleAt(self: SpectralGrid, index: u32) Error!f64 {
        try self.validate();
        if (index >= self.sample_count) return Error.IndexOutOfRange;
        const step = (self.end_nm - self.start_nm) / @as(f64, @floatFromInt(self.sample_count - 1));
        return self.start_nm + step * @as(f64, @floatFromInt(index));
    }
};

pub const ResolvedAxis = struct {
    base: SpectralGrid,
    explicit_wavelengths_nm: []const f64 = &.{},

    pub fn validate(self: ResolvedAxis) Error!void {
        try self.base.validate();
        if (self.explicit_wavelengths_nm.len == 0) return;
        if (self.explicit_wavelengths_nm.len != self.base.sample_count) return Error.InvalidExplicitSamples;
        try validateExplicitSamples(self.explicit_wavelengths_nm);
    }

    pub fn sampleAt(self: ResolvedAxis, index: u32) Error!f64 {
        try self.validate();
        if (self.explicit_wavelengths_nm.len != 0) return sampleAtExplicit(self.explicit_wavelengths_nm, index);
        return self.base.sampleAt(index);
    }
};

test "spectral grid validates and resolves sample coordinates" {
    const grid = SpectralGrid{
        .start_nm = 405.0,
        .end_nm = 465.0,
        .sample_count = 7,
    };
    try grid.validate();
    try std.testing.expectApproxEqRel(@as(f64, 405.0), try grid.sampleAt(0), 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 465.0), try grid.sampleAt(6), 1e-12);
}

pub fn validateExplicitSamples(wavelengths_nm: []const f64) Error!void {
    if (wavelengths_nm.len == 0) return error.InvalidExplicitSamples;

    var previous: ?f64 = null;
    for (wavelengths_nm) |wavelength_nm| {
        if (!std.math.isFinite(wavelength_nm)) return error.InvalidExplicitSamples;
        if (previous) |earlier| {
            if (wavelength_nm <= earlier) return error.InvalidExplicitSamples;
        }
        previous = wavelength_nm;
    }
}

pub fn sampleAtExplicit(wavelengths_nm: []const f64, index: u32) Error!f64 {
    try validateExplicitSamples(wavelengths_nm);
    if (index >= wavelengths_nm.len) return error.IndexOutOfRange;
    return wavelengths_nm[index];
}

test "explicit spectral axes validate strict monotonic measured-channel wavelengths" {
    try validateExplicitSamples(&.{ 760.8, 761.02, 761.31 });
    try std.testing.expectApproxEqAbs(@as(f64, 761.02), try sampleAtExplicit(&.{ 760.8, 761.02, 761.31 }, 1), 1.0e-12);
    try std.testing.expectError(error.InvalidExplicitSamples, validateExplicitSamples(&.{ 761.0, 760.9 }));
}

test "resolved spectral axes unify native and measured-channel addressing" {
    const native_axis: ResolvedAxis = .{
        .base = .{
            .start_nm = 760.0,
            .end_nm = 761.0,
            .sample_count = 3,
        },
    };
    try std.testing.expectApproxEqAbs(@as(f64, 760.5), try native_axis.sampleAt(1), 1.0e-12);

    const measured_axis: ResolvedAxis = .{
        .base = native_axis.base,
        .explicit_wavelengths_nm = &.{ 760.02, 760.41, 760.93 },
    };
    try std.testing.expectApproxEqAbs(@as(f64, 760.41), try measured_axis.sampleAt(1), 1.0e-12);
}
