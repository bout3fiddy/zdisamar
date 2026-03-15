pub const Error = error{
    ShapeMismatch,
};

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
