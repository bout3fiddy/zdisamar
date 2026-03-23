//! Purpose:
//!   Define wavelength grids and resolved axes used by spectra kernels and measured-channel alignment.
//!
//! Physics:
//!   Encodes spectral sample coordinates in nanometers and preserves monotonic channel ordering.
//!
//! Vendor:
//!   `spectral grid` / `measured-channel axis`
//!
//! Design:
//!   Zig keeps explicit uniform and resolved axis types instead of inferring channel coordinates from config blobs.
//!
//! Invariants:
//!   Uniform axes have at least two samples and explicit sample lists are strictly increasing and finite.
//!
//! Validation:
//!   Unit tests cover uniform spacing, explicit sample validation, and mixed resolved-axis lookup.

const std = @import("std");

pub const Error = error{
    InvalidSampleCount,
    InvalidBounds,
    IndexOutOfRange,
    InvalidExplicitSamples,
};

/// Purpose:
///   Describe a uniform spectral axis in nanometers.
pub const SpectralGrid = struct {
    start_nm: f64,
    end_nm: f64,
    sample_count: u32,

    /// Purpose:
    ///   Validate the uniform spectral span before it is used for interpolation or indexing.
    ///
    /// Physics:
    ///   Enforces a strictly increasing wavelength axis with at least two samples.
    ///
    /// Vendor:
    ///   `spectral grid validation`
    pub fn validate(self: SpectralGrid) Error!void {
        if (self.sample_count < 2) return Error.InvalidSampleCount;
        if (self.end_nm <= self.start_nm) return Error.InvalidBounds;
    }

    /// Purpose:
    ///   Return the wavelength at a zero-based sample index on the uniform axis.
    ///
    /// Physics:
    ///   Computes evenly spaced spectral coordinates in nanometers.
    ///
    /// Vendor:
    ///   `spectral grid sample lookup`
    pub fn sampleAt(self: SpectralGrid, index: u32) Error!f64 {
        try self.validate();
        if (index >= self.sample_count) return Error.IndexOutOfRange;
        const step = (self.end_nm - self.start_nm) / @as(f64, @floatFromInt(self.sample_count - 1));
        return self.start_nm + step * @as(f64, @floatFromInt(index));
    }
};

/// Purpose:
///   Pair a uniform spectral axis with optional explicit sample coordinates.
pub const ResolvedAxis = struct {
    base: SpectralGrid,
    explicit_wavelengths_nm: []const f64 = &.{},

    /// Purpose:
    ///   Validate a resolved spectral axis and any explicit per-channel coordinates.
    ///
    /// Physics:
    ///   Preserves a monotonic wavelength ordering whether the axis is uniform or externally supplied.
    ///
    /// Vendor:
    ///   `resolved spectral axis`
    pub fn validate(self: ResolvedAxis) Error!void {
        try self.base.validate();
        if (self.explicit_wavelengths_nm.len == 0) return;
        if (self.explicit_wavelengths_nm.len != self.base.sample_count) return Error.InvalidExplicitSamples;
        try validateExplicitSamples(self.explicit_wavelengths_nm);
    }

    /// Purpose:
    ///   Resolve the wavelength at a sample index using explicit coordinates when present.
    ///
    /// Physics:
    ///   Keeps measured-channel wavelengths authoritative when the axis is not uniformly generated.
    ///
    /// Vendor:
    ///   `resolved spectral axis sample lookup`
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

/// Purpose:
///   Validate an explicit wavelength list for measured-channel handling.
///
/// Physics:
///   Enforces finite, strictly increasing channel coordinates in nanometers.
///
/// Vendor:
///   `explicit spectral sample validation`
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

/// Purpose:
///   Return an explicit wavelength at a sample index.
///
/// Physics:
///   Preserves the measured-channel wavelength list without re-deriving spacing.
///
/// Vendor:
///   `explicit spectral sample lookup`
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
