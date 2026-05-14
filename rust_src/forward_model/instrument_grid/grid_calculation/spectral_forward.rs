use crate::{
    forward_model::{
        implementations::surface,
        jacobian::{self, Vector},
        radiative_transfer::ForwardResult,
    },
    input::{Scene, solar_irradiance_at_wavelength},
};

pub const MIN_PARALLEL_FORWARD_MISS_COUNT: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ForwardIntegratedSample {
    pub radiance: f64,
    pub jacobian: Vector,
}

impl Default for ForwardIntegratedSample {
    fn default() -> Self {
        Self {
            radiance: 0.0,
            jacobian: jacobian::zero(),
        }
    }
}

pub fn radiance_from_forward(
    scene: &Scene,
    surface_implementation: surface::Implementation,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: ForwardResult,
) -> f64 {
    let solar_irradiance = solar_irradiance_at_wavelength(scene, wavelength_nm);
    let solar_cosine = scene.geometry.solar_cosine_at_altitude(0.0);
    let surface_gain = (surface_implementation.brdf_factor)(surface::EvaluationContext {
        scene,
        wavelength_nm,
        safe_span,
        phase,
        forward,
    });
    solar_cosine * (forward.toa_reflectance_factor * surface_gain) * solar_irradiance
        / std::f64::consts::PI
}

pub fn radiance_jacobian_from_forward(
    scene: &Scene,
    surface_implementation: surface::Implementation,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: ForwardResult,
) -> Vector {
    let Some(reflectance_jacobian) = forward.jacobian else {
        return jacobian::zero();
    };
    let solar_irradiance = solar_irradiance_at_wavelength(scene, wavelength_nm);
    let solar_cosine = scene.geometry.solar_cosine_at_altitude(0.0);
    let surface_gain = (surface_implementation.brdf_factor)(surface::EvaluationContext {
        scene,
        wavelength_nm,
        safe_span,
        phase,
        forward,
    });
    jacobian::scale(
        reflectance_jacobian,
        solar_cosine * surface_gain * solar_irradiance / std::f64::consts::PI,
    )
}
