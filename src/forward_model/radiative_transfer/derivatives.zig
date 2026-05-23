const std = @import("std");

pub fn transmittance(optical_depth: f64) f64 {
    // math: T(tau) = exp(-tau).
    return std.math.exp(-optical_depth);
}

pub fn dTransmittanceDOpticalDepth(optical_depth: f64) f64 {
    // math: dT/dtau = -exp(-tau).
    return -transmittance(optical_depth);
}

pub fn proxyOpticalDepthSensitivity(
    surface_term: f64,
    scattering_term: f64,
    surface_path_factor: f64,
    scattering_path_factor: f64,
) f64 {
    // math: d signal/d tau_proxy = -(surface_term * surface_path_factor + scattering_term * scattering_path_factor).
    return -(surface_term * surface_path_factor + scattering_term * scattering_path_factor);
}

pub fn proxyJacobianColumn(signal: f64, optical_depth: f64, derivative_scale: f64) f64 {
    // math: proxy column = proxyOpticalDepthSensitivity(signal, signal*scale, 1, 1) * exp(-tau).
    return proxyOpticalDepthSensitivity(
        signal,
        signal * derivative_scale,
        1.0,
        1.0,
    ) * transmittance(optical_depth);
}
