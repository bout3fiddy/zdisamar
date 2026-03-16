const std = @import("std");

pub const Error = error{
    InvalidSampleCount,
    InvalidBounds,
    IndexOutOfRange,
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
