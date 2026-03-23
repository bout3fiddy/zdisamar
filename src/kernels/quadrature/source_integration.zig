//! Purpose:
//!   Integrate source terms against quadrature weights.
//!
//! Physics:
//!   Computes a weighted sum over the supplied source function samples.
//!
//! Vendor:
//!   `source integration`
//!
//! Design:
//!   The helper stays deliberately tiny so transport code can inject its own weighting logic.
//!
//! Invariants:
//!   Source and weight slices must be the same length.
//!
//! Validation:
//!   Tests cover weighted accumulation of a short source vector.

pub const Error = error{
    ShapeMismatch,
};

/// Purpose:
///   Integrate a sampled source term with matching quadrature weights.
///
/// Physics:
///   Produces the discrete weighted integral used by transport source terms.
///
/// Vendor:
///   `weighted source integration`
pub fn integrate(weights: []const f64, source_terms: []const f64) Error!f64 {
    if (weights.len != source_terms.len) return Error.ShapeMismatch;

    var sum: f64 = 0.0;
    for (weights, source_terms) |weight, source| {
        sum += weight * source;
    }
    return sum;
}

test "source integration accumulates weighted source terms" {
    const weights = [_]f64{ 0.5, 1.0, 0.5 };
    const source_terms = [_]f64{ 2.0, 4.0, 6.0 };
    const integrated = try integrate(&weights, &source_terms);
    try std.testing.expectApproxEqRel(@as(f64, 8.0), integrated, 1e-12);
}

const std = @import("std");
