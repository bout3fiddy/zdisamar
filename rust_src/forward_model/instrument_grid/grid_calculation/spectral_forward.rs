use crate::{
    forward_model::{
        instrument_grid::grid_calculation::forward_input::{
            self, ForwardInputBuffers, configured_forward_input,
        },
        jacobian,
        optical_properties::state_build::PreparedOpticalState,
        radiative_transfer::{
            common_types::{ForwardResult, Route},
            labos,
        },
    },
    input::{reference::solar_irradiance, scene::Scene},
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ForwardIntegratedSample {
    pub radiance: f64,
    pub jacobian: jacobian::Vector,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ForwardInput(forward_input::Error),
    RadiativeTransfer(crate::forward_model::radiative_transfer::common_types::Error),
}

impl From<forward_input::Error> for Error {
    fn from(value: forward_input::Error) -> Self {
        Self::ForwardInput(value)
    }
}

impl From<crate::forward_model::radiative_transfer::common_types::Error> for Error {
    fn from(value: crate::forward_model::radiative_transfer::common_types::Error) -> Self {
        Self::RadiativeTransfer(value)
    }
}

pub fn compute_forward_sample_at_wavelength(
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    buffers: ForwardInputBuffers<'_>,
) -> Result<ForwardIntegratedSample, Error> {
    let input = configured_forward_input(scene, route, prepared, wavelength_nm, buffers)?;
    let mut effective_route = route;
    effective_route.rtm_controls = input.rtm_controls;
    let forward = labos::execute(effective_route, &input)?;
    Ok(ForwardIntegratedSample {
        radiance: radiance_from_forward(scene, wavelength_nm, &forward),
        jacobian: radiance_jacobian_from_forward(scene, wavelength_nm, &forward),
    })
}

pub fn radiance_from_forward(scene: &Scene, wavelength_nm: f64, forward: &ForwardResult) -> f64 {
    let solar_irradiance = solar_irradiance::irradiance_at_wavelength(scene, wavelength_nm);
    let solar_cosine = scene.geometry.solar_cosine_at_altitude(0.0);
    solar_cosine * forward.toa_reflectance_factor * solar_irradiance / std::f64::consts::PI
}

pub fn radiance_jacobian_from_forward(
    scene: &Scene,
    wavelength_nm: f64,
    forward: &ForwardResult,
) -> jacobian::Vector {
    let Some(reflectance_jacobian) = forward.jacobian else {
        return jacobian::zero();
    };
    let solar_irradiance = solar_irradiance::irradiance_at_wavelength(scene, wavelength_nm);
    let solar_cosine = scene.geometry.solar_cosine_at_altitude(0.0);
    jacobian::scale(
        reflectance_jacobian,
        solar_cosine * solar_irradiance / std::f64::consts::PI,
    )
}
