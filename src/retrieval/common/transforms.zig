pub fn logState(value: f64) !f64 {
    if (value <= 0.0) return error.InvalidStateValue;
    return std.math.log(f64, std.math.e, value);
}

pub fn expState(value: f64) f64 {
    return std.math.exp(value);
}

test "state transforms round-trip positive values" {
    const logged = try logState(3.0);
    try std.testing.expectApproxEqRel(@as(f64, 3.0), expState(logged), 1e-12);
}

const std = @import("std");
