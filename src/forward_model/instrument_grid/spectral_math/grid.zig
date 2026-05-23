const std = @import("std");

pub const Error = error{
    InvalidSampleCount,
    InvalidBounds,
    IndexOutOfRange,
    InvalidExplicitSamples,
};

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: start_nm=8 B, end_nm=8 B, sample_count=4 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count
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
        // math: lambda_i = start_nm + i * (end_nm - start_nm) / (sample_count - 1)
        const step = (self.end_nm - self.start_nm) / @as(f64, @floatFromInt(self.sample_count - 1));
        return self.start_nm + step * @as(f64, @floatFromInt(index));
    }
};

// layout(64-bit):
//   size: 40 B, align: 8 B
//   field storage: base=24 B, explicit_wavelengths_nm=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: explicit_wavelengths_nm carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 40 B (0.039 KiB); total also includes referenced storage above
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
