//! Purpose:
//!   Define canonical layout axes for spectral, layer, and state-vector dimensions.
//!
//! Physics:
//!   Encodes the coordinate counts used to map wavelength, altitude, and retrieval-parameter samples.
//!
//! Vendor:
//!   `layout axes`
//!
//! Design:
//!   Axes are lightweight typed records so higher layers can validate shape before touching storage.
//!
//! Invariants:
//!   Spectral axes are monotonic, and layer/state axes always have a positive count.
//!
//! Validation:
//!   Tests cover spectral stepping and wavelength lookup.

const std = @import("std");

pub const Error = error{
    InvalidAxis,
    IndexOutOfRange,
};

/// Purpose:
///   Describe a uniform spectral axis.
pub const SpectralAxis = struct {
    start_nm: f64,
    end_nm: f64,
    sample_count: u32,

    /// Purpose:
    ///   Validate the spectral axis.
    ///
    /// Physics:
    ///   Requires a monotonic wavelength range with at least two samples.
    pub fn validate(self: SpectralAxis) Error!void {
        if (self.sample_count < 2) return Error.InvalidAxis;
        if (self.end_nm <= self.start_nm) return Error.InvalidAxis;
    }

    /// Purpose:
    ///   Compute the spectral step in nanometers.
    pub fn stepNm(self: SpectralAxis) Error!f64 {
        try self.validate();
        return (self.end_nm - self.start_nm) / @as(f64, @floatFromInt(self.sample_count - 1));
    }

    /// Purpose:
    ///   Compute the wavelength at a spectral sample index.
    pub fn wavelengthNm(self: SpectralAxis, sample_index: u32) Error!f64 {
        try self.validate();
        if (sample_index >= self.sample_count) return Error.IndexOutOfRange;
        return self.start_nm + (try self.stepNm()) * @as(f64, @floatFromInt(sample_index));
    }
};

/// Purpose:
///   Describe the number of atmospheric layers in a layout.
pub const LayerAxis = struct {
    layer_count: u32,

    /// Purpose:
    ///   Validate the layer axis.
    pub fn validate(self: LayerAxis) Error!void {
        if (self.layer_count == 0) return Error.InvalidAxis;
    }
};

/// Purpose:
///   Describe the number of retrieval parameters in a state vector.
pub const StateAxis = struct {
    parameter_count: u32,

    /// Purpose:
    ///   Validate the state axis.
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
