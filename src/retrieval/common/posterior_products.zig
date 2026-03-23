//! Purpose:
//!   Shared posterior-product assembly for retrieval solvers.
//!
//! Physics:
//!   Build the averaging-kernel product from posterior covariance and
//!   measurement normal equations.
//!
//! Vendor:
//!   Posterior/averaging-kernel product assembly in OE and spectral-fit
//!   retrieval stages.
//!
//! Design:
//!   Keep this as a small matrix-multiplication helper so solver modules can
//!   stay focused on method-specific policy and diagnostic shaping.
//!
//! Invariants:
//!   All matrices must be square with the same state dimension.
//!
//! Validation:
//!   Retrieval solver tests exercise this through the public solver outputs.

const common = @import("contracts.zig");
const dense = @import("../../kernels/linalg/small_dense.zig");

/// Purpose:
///   Multiply posterior covariance by the measurement normal matrix to form
///   the averaging kernel.
pub fn buildAveragingKernel(
    posterior_covariance: []const f64,
    measurement_normal: []const f64,
    state_count: usize,
    out: []f64,
) common.Error!void {
    if (posterior_covariance.len != state_count * state_count or
        measurement_normal.len != state_count * state_count or
        out.len != state_count * state_count)
    {
        return common.Error.ShapeMismatch;
    }

    @memset(out, 0.0);
    for (0..state_count) |row| {
        for (0..state_count) |column| {
            var total: f64 = 0.0;
            for (0..state_count) |inner| {
                total += posterior_covariance[dense.index(row, inner, state_count)] *
                    measurement_normal[dense.index(inner, column, state_count)];
            }
            out[dense.index(row, column, state_count)] = total;
        }
    }
}
