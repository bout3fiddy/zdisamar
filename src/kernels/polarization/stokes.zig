//! Purpose:
//!   Represent and evaluate Stokes vectors for polarized spectral transport.
//!
//! Physics:
//!   Encodes the `I, Q, U, V` state used by the polarization kernels.
//!
//! Vendor:
//!   `Stokes vector`
//!
//! Design:
//!   The vector stays as a plain struct so callers can pass it through transport and Mueller layers without adapters.
//!
//! Invariants:
//!   `i` is the total intensity component and the linear-polarization ratio is guarded against zero intensity.
//!
//! Validation:
//!   Tests cover linear-polarization degree calculation.

const std = @import("std");

/// Purpose:
///   Store a four-component Stokes state.
///
/// Physics:
///   Captures the polarized radiance state used by the Mueller matrix helper.
pub const StokesVector = struct {
    i: f64,
    q: f64 = 0.0,
    u: f64 = 0.0,
    v: f64 = 0.0,

    /// Purpose:
    ///   Compute the fraction of total intensity carried by linear polarization.
    ///
    /// Physics:
    ///   Returns `sqrt(Q^2 + U^2) / I` when the intensity is non-zero.
    ///
    /// Vendor:
    ///   `degree of linear polarization`
    pub fn degreeOfLinearPolarization(self: StokesVector) f64 {
        const numerator = std.math.sqrt(self.q * self.q + self.u * self.u);
        if (self.i == 0.0) return 0.0;
        return numerator / self.i;
    }
};

test "stokes vector reports linear polarization degree" {
    const state = StokesVector{
        .i = 10.0,
        .q = 3.0,
        .u = 4.0,
    };
    try std.testing.expectApproxEqRel(@as(f64, 0.5), state.degreeOfLinearPolarization(), 1e-12);
}
