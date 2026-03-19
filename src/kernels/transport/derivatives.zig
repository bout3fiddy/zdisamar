const std = @import("std");

pub fn transmittance(optical_depth: f64) f64 {
    return std.math.exp(-optical_depth);
}

pub fn dTransmittanceDOpticalDepth(optical_depth: f64) f64 {
    return -transmittance(optical_depth);
}

pub fn proxyOpticalDepthSensitivity(
    surface_term: f64,
    scattering_term: f64,
    surface_path_factor: f64,
    scattering_path_factor: f64,
) f64 {
    return -(surface_term * surface_path_factor + scattering_term * scattering_path_factor);
}

pub fn proxyJacobianColumn(signal: f64, optical_depth: f64, derivative_scale: f64) f64 {
    return proxyOpticalDepthSensitivity(
        signal,
        signal * derivative_scale,
        1.0,
        1.0,
    ) * transmittance(optical_depth);
}

test "transport derivative helpers expose analytical transmittance gradients" {
    try std.testing.expectApproxEqRel(@as(f64, -std.math.exp(-0.5)), dTransmittanceDOpticalDepth(0.5), 1e-12);
    try std.testing.expectApproxEqRel(
        @as(f64, -1.1),
        proxyOpticalDepthSensitivity(1.0, 0.1, 1.0, 1.0),
        1e-12,
    );
    try std.testing.expect(proxyJacobianColumn(1.0, 0.5, 0.1) < 0.0);
}
