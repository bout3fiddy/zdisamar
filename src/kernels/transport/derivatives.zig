pub fn transmittance(optical_depth: f64) f64 {
    return std.math.exp(-optical_depth);
}

pub fn dTransmittanceDOpticalDepth(optical_depth: f64) f64 {
    return -transmittance(optical_depth);
}

pub fn jacobianColumn(signal: f64, optical_depth: f64, derivative_scale: f64) f64 {
    return signal * derivative_scale * -dTransmittanceDOpticalDepth(optical_depth);
}

test "transport derivative helpers expose analytical transmittance gradients" {
    try std.testing.expectApproxEqRel(@as(f64, -std.math.exp(-0.5)), dTransmittanceDOpticalDepth(0.5), 1e-12);
    try std.testing.expect(jacobianColumn(1.0, 0.5, 0.1) > 0.0);
}

const std = @import("std");
