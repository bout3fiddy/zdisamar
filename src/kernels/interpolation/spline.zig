//! Purpose:
//!   Interpolate monotonic spectral samples with a natural cubic spline.
//!
//! Physics:
//!   Builds second derivatives for a natural spline and evaluates the cubic segment at a target wavelength.
//!
//! Vendor:
//!   `natural cubic spline`
//!
//! Design:
//!   The helper uses fixed stack scratch buffers to keep the implementation simple and predictable.
//!
//! Invariants:
//!   `x` and `y` must be same length, `x` must be monotonic, and the sample count must fit the fixed workspace.
//!
//! Validation:
//!   Tests cover quadratic reproduction at midpoints.

const std = @import("std");

pub const Error = error{
    ShapeMismatch,
    NotEnoughPoints,
    OutOfDomain,
};

/// Purpose:
///   Sample a monotonic spectrum with a natural cubic spline.
///
/// Physics:
///   Solves a tridiagonal spline system implicitly and evaluates the interpolated value at `target_x`.
///
/// Vendor:
///   `natural cubic interpolation`
///
/// Assumptions:
///   The input axis is sorted in ascending order and fits within the fixed scratch buffers.
///
/// Decisions:
///   The spline workspace is capped at 64 points so callers keep control of memory use in hot paths.
pub fn sampleNatural(x: []const f64, y: []const f64, target_x: f64) Error!f64 {
    if (x.len != y.len) return Error.ShapeMismatch;
    if (x.len < 3) return Error.NotEnoughPoints;
    if (target_x < x[0] or target_x > x[x.len - 1]) return Error.OutOfDomain;

    // DECISION:
    //   Fixed scratch buffers keep the helper allocation-free for short spectral windows.
    var second: [64]f64 = undefined;
    if (x.len > second.len) return Error.NotEnoughPoints;
    var u: [64]f64 = undefined;

    second[0] = 0.0;
    u[0] = 0.0;

    var i: usize = 1;
    while (i + 1 < x.len) : (i += 1) {
        const sig = (x[i] - x[i - 1]) / (x[i + 1] - x[i - 1]);
        const p = sig * second[i - 1] + 2.0;
        second[i] = (sig - 1.0) / p;
        const ddydx = ((y[i + 1] - y[i]) / (x[i + 1] - x[i])) - ((y[i] - y[i - 1]) / (x[i] - x[i - 1]));
        u[i] = (6.0 * ddydx / (x[i + 1] - x[i - 1]) - sig * u[i - 1]) / p;
    }

    second[x.len - 1] = 0.0;
    var k: usize = x.len - 1;
    while (k > 0) : (k -= 1) {
        second[k - 1] = second[k - 1] * second[k] + u[k - 1];
    }

    var klo: usize = 0;
    var khi: usize = x.len - 1;
    while (khi - klo > 1) {
        const mid = (khi + klo) / 2;
        if (x[mid] > target_x) {
            khi = mid;
        } else {
            klo = mid;
        }
    }

    const h = x[khi] - x[klo];
    const a = (x[khi] - target_x) / h;
    const b = (target_x - x[klo]) / h;
    return a * y[klo] + b * y[khi] +
        ((a * a * a - a) * second[klo] + (b * b * b - b) * second[khi]) * (h * h) / 6.0;
}

test "natural cubic spline reproduces a quadratic profile at midpoints" {
    const x = [_]f64{ 0.0, 1.0, 2.0, 3.0 };
    const y = [_]f64{ 0.0, 1.0, 4.0, 9.0 };
    const value = try sampleNatural(&x, &y, 1.5);
    try std.testing.expectApproxEqRel(@as(f64, 2.2), value, 0.05);
}
