const std = @import("std");

// derivatives.zig -------------------------------------------------------------------------------------------|
// Small math helpers for scalar RTM derivative columns. These routines are separate from LABOS: they are     |
// proxy math used by simple callers, not part of the layer-resolved transport solve.                         |
//                                                                                                            |
// main paths                                                                                                 |
//   transmittance                      -> Beer-Lambert survival for a unit path                              |
//   dTransmittanceDOpticalDepth        -> derivative of that survival with respect to optical depth          |
//   proxyOpticalDepthSensitivity       -> add surface and scattering proxy terms                             |
//   proxyJacobianColumn                -> apply attenuation to the proxy derivative                          |
//                                                                                                            |
// math                                                                                                       |
//   T(tau) = exp(-tau)                                                                                       |
// -----------------------------------------------------------------------------------------------------------|

pub fn transmittance(optical_depth: f64) f64 {
    // transmittance -----------------------------------------------------------------------------------------|
    // Beer-Lambert survival for a unit path optical depth.                                                   |
    //                                                                                                        |
    // math                                                                                                   |
    //   T(tau) = exp(-tau)                                                                                   |
    // -------------------------------------------------------------------------------------------------------|

    return std.math.exp(-optical_depth);
}

pub fn dTransmittanceDOpticalDepth(optical_depth: f64) f64 {
    // dTransmittanceDOpticalDepth ---------------------------------------------------------------------------|
    // Derivative of unit-path transmittance with respect to optical depth.                                   |
    //                                                                                                        |
    // math                                                                                                   |
    //   dT / dtau = -exp(-tau)                                                                               |
    // -------------------------------------------------------------------------------------------------------|

    return -transmittance(optical_depth);
}

pub fn proxyOpticalDepthSensitivity(
    surface_term: f64,
    scattering_term: f64,
    surface_path_factor: f64,
    scattering_path_factor: f64,
) f64 {
    // proxyOpticalDepthSensitivity --------------------------------------------------------------------------|
    // Add the proxy surface and scattering pieces into one optical-depth derivative.                         |
    //                                                                                                        |
    // math                                                                                                   |
    //   d signal / d tau_proxy                                                                               |
    //     = -(surface_term * surface_path_factor + scattering_term * scattering_path_factor)                 |
    // -------------------------------------------------------------------------------------------------------|

    return -(surface_term * surface_path_factor + scattering_term * scattering_path_factor);
}

pub fn proxyJacobianColumn(signal: f64, optical_depth: f64, derivative_scale: f64) f64 {
    // proxyJacobianColumn -----------------------------------------------------------------------------------|
    // Apply unit-path attenuation to one proxy Jacobian column.                                              |
    //                                                                                                        |
    // math                                                                                                   |
    //   proxy column                                                                                         |
    //     = proxyOpticalDepthSensitivity(signal, signal * scale, 1, 1) * exp(-tau)                           |
    // -------------------------------------------------------------------------------------------------------|

    return proxyOpticalDepthSensitivity(
        signal,
        signal * derivative_scale,
        1.0,
        1.0,
    ) * transmittance(optical_depth);
}
