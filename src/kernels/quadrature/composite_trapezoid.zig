//! Purpose:
//!   Integrate uniformly sampled spectra with the composite trapezoid rule.
//!
//! Physics:
//!   Approximates the integral of a uniformly spaced spectral profile.
//!
//! Vendor:
//!   `composite trapezoid`
//!
//! Design:
//!   The implementation uses the axis type so the sample spacing is derived from the validated layout contract.
//!
//! Invariants:
//!   The values slice must match the axis sample count and the axis must be monotonic.
//!
//! Validation:
//!   Tests cover a linear profile whose trapezoid integral is exact.

const std = @import("std");
const layout = @import("model_layout");

pub const Error = error{
    ShapeMismatch,
} || layout.Axes.Error;

/// Purpose:
///   Integrate a uniformly sampled spectral profile using the trapezoid rule.
///
/// Physics:
///   Returns the approximate area under the spectrum in the same units as `values * nanometers`.
///
/// Vendor:
///   `uniform trapezoid integration`
pub fn integrateUniform(axis: layout.Axes.SpectralAxis, values: []const f64) Error!f64 {
    try axis.validate();
    if (values.len != axis.sample_count) return Error.ShapeMismatch;

    const step = try axis.stepNm();
    var sum: f64 = 0.0;

    var i: usize = 1;
    while (i + 1 < values.len) : (i += 1) {
        sum += values[i];
    }

    return step * ((values[0] + values[values.len - 1]) * 0.5 + sum);
}

test "composite trapezoid integrates linear profile" {
    const axis = layout.Axes.SpectralAxis{
        .start_nm = 0.0,
        .end_nm = 10.0,
        .sample_count = 11,
    };

    var values: [11]f64 = undefined;
    for (&values, 0..) |*value, idx| {
        value.* = @floatFromInt(idx);
    }

    const integral = try integrateUniform(axis, &values);
    try std.testing.expectApproxEqRel(@as(f64, 50.0), integral, 1e-12);
}
