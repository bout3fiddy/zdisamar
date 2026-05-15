pub fn transmittance(optical_depth: f64) -> f64 {
    (-optical_depth).exp()
}

pub fn d_transmittance_d_optical_depth(optical_depth: f64) -> f64 {
    -transmittance(optical_depth)
}

pub fn proxy_optical_depth_sensitivity(
    surface_term: f64,
    scattering_term: f64,
    surface_path_factor: f64,
    scattering_path_factor: f64,
) -> f64 {
    -(surface_term * surface_path_factor + scattering_term * scattering_path_factor)
}

pub fn proxy_jacobian_column(signal: f64, optical_depth: f64, derivative_scale: f64) -> f64 {
    proxy_optical_depth_sensitivity(signal, signal * derivative_scale, 1.0, 1.0)
        * transmittance(optical_depth)
}
