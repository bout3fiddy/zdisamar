//! Purpose:
//!   Interpolate spectral samples on a uniform axis with linear weighting.
//!
//! Physics:
//!   Computes a first-order interpolation between neighboring wavelength samples.
//!
//! Vendor:
//!   `linear interpolation`
//!
//! Design:
//!   The axis validation is delegated to the layout type so this helper can remain focused on interpolation math.
//!
//! Invariants:
//!   Axis bounds must be monotonic and the values slice must match the axis sample count.
//!
//! Validation:
//!   Tests cover in-bounds interpolation on a uniform spectral axis.

const std = @import("std");
const layout = @import("model_layout");

pub const Error = error{
    ShapeMismatch,
    OutOfDomain,
} || layout.Axes.Error;

/// Purpose:
///   Sample a uniform spectral axis at a target wavelength using linear interpolation.
///
/// Physics:
///   Returns a linearly interpolated sample in the same units as the input values.
///
/// Vendor:
///   `uniform spectral interpolation`
pub fn sampleUniform(
    axis: layout.Axes.SpectralAxis,
    values: []const f64,
    wavelength_nm: f64,
) Error!f64 {
    try axis.validate();
    if (values.len != axis.sample_count) return Error.ShapeMismatch;

    if (wavelength_nm < axis.start_nm or wavelength_nm > axis.end_nm) {
        return Error.OutOfDomain;
    }

    const step = try axis.stepNm();
    const normalized = (wavelength_nm - axis.start_nm) / step;

    const left_index_f = @floor(normalized);
    const left_index: u32 = @intFromFloat(left_index_f);
    const right_index: u32 = @min(left_index + 1, axis.sample_count - 1);
    const alpha = normalized - left_index_f;

    const left_value = values[left_index];
    const right_value = values[right_index];
    return (1.0 - alpha) * left_value + alpha * right_value;
}

test "linear interpolation samples inside spectral axis bounds" {
    const axis = layout.Axes.SpectralAxis{
        .start_nm = 400.0,
        .end_nm = 410.0,
        .sample_count = 6,
    };
    const values = [_]f64{ 0.0, 10.0, 20.0, 30.0, 40.0, 50.0 };

    const v = try sampleUniform(axis, &values, 405.0);
    try std.testing.expectApproxEqRel(@as(f64, 25.0), v, 1e-12);
}
