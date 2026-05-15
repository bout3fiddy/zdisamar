use crate::{
    forward_model::{
        jacobian,
        optical_properties::state_build::PreparedOpticalState,
        radiative_transfer::common_types::{
            LayerInput, PseudoSphericalSample, Route, RtmQuadratureLevel, SourceInterfaceInput,
        },
    },
    input::{
        instrument::{IntegrationMode, SpectralChannel},
        scene::Scene,
    },
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ShapeMismatch,
}

#[derive(Debug, Clone, Copy)]
pub struct Buffers<'a> {
    pub wavelengths: &'a [f64],
    pub radiance: &'a [f64],
    pub irradiance: &'a [f64],
    pub reflectance: &'a [f64],
    pub scratch: &'a [f64],
    pub scratch_aux: &'a [f64],
    pub layer_inputs: &'a [LayerInput],
    pub pseudo_spherical_layers: &'a [LayerInput],
    pub source_interfaces: &'a [SourceInterfaceInput],
    pub rtm_quadrature_levels: &'a [RtmQuadratureLevel],
    pub pseudo_spherical_samples: &'a [PseudoSphericalSample],
    pub pseudo_spherical_level_starts: &'a [usize],
    pub pseudo_spherical_level_altitudes: &'a [f64],
    pub jacobian: Option<&'a [f64]>,
    pub noise_sigma: Option<&'a [f64]>,
    pub radiance_noise_sigma: Option<&'a [f64]>,
    pub irradiance_noise_sigma: Option<&'a [f64]>,
    pub reflectance_noise_sigma: Option<&'a [f64]>,
}

pub fn transport_layer_count_hint(scene: &Scene, route: Route) -> usize {
    let _ = route;
    if scene.atmosphere.interval_grid.enabled() {
        let uses_disamar_shared_rtm_grid = scene
            .observation_model
            .resolved_channel_controls(SpectralChannel::Radiance)
            .response
            .integration_mode
            == IntegrationMode::DisamarHrGrid
            || scene
                .observation_model
                .resolved_channel_controls(SpectralChannel::Irradiance)
                .response
                .integration_mode
                == IntegrationMode::DisamarHrGrid;
        let total_count = scene
            .atmosphere
            .interval_grid
            .intervals
            .iter()
            .map(|interval| {
                if uses_disamar_shared_rtm_grid {
                    interval.altitude_divisions as usize + 1
                } else {
                    (interval.altitude_divisions as usize).max(1)
                }
            })
            .sum::<usize>();
        return total_count.max(1);
    }

    let layer_count = (scene.atmosphere.layer_count as usize).max(1);
    layer_count * usize::from(scene.atmosphere.sublayer_divisions).max(1)
}

pub fn pseudo_spherical_sample_count_hint(scene: &Scene, route: Route) -> usize {
    let layer_count = transport_layer_count_hint(scene, route);
    layer_count * (pseudo_spherical_subgrid_divisions(scene) + 2)
}

pub fn reflectance_calibration_enabled(scene: &Scene) -> bool {
    let controls = scene.observation_model.resolved_reflectance_calibration();
    controls.multiplicative_error.enabled() || controls.additive_error.enabled()
}

pub fn resolved_transport_layer_count(route: Route, prepared: &PreparedOpticalState) -> usize {
    let _ = route;
    prepared.transport_layer_count()
}

pub fn resolved_pseudo_spherical_sample_count(
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
) -> usize {
    let transport_layer_count = resolved_transport_layer_count(route, prepared);
    if prepared.interval_semantics_use_reduced_shared_rtm_layers()
        && prepared
            .shared_rtm_geometry
            .is_valid_for(transport_layer_count)
    {
        return prepared
            .shared_rtm_geometry
            .layers
            .iter()
            .map(|layer| {
                let support_count = layer.support_count as usize;
                support_count.saturating_sub(2)
            })
            .sum();
    }
    transport_layer_count * pseudo_spherical_subgrid_divisions(scene)
}

pub fn pseudo_spherical_subgrid_divisions(scene: &Scene) -> usize {
    usize::from(scene.atmosphere.sublayer_divisions).max(1)
}

pub fn validate_buffers(sample_count: usize, buffers: &Buffers<'_>) -> Result<(), Error> {
    if sample_count == 0
        || buffers.wavelengths.len() != sample_count
        || buffers.radiance.len() != sample_count
        || buffers.irradiance.len() != sample_count
        || buffers.reflectance.len() != sample_count
        || buffers.scratch.len() != sample_count
        || buffers.scratch_aux.len() != sample_count
        || buffers.layer_inputs.is_empty()
        || buffers.pseudo_spherical_layers.is_empty()
        || buffers.source_interfaces.len() != buffers.layer_inputs.len() + 1
        || buffers.rtm_quadrature_levels.len() != buffers.layer_inputs.len() + 1
    {
        return Err(Error::ShapeMismatch);
    }
    if buffers.pseudo_spherical_samples.len() != buffers.pseudo_spherical_layers.len()
        || buffers.pseudo_spherical_level_starts.len() != buffers.layer_inputs.len() + 1
        || buffers.pseudo_spherical_level_altitudes.len() != buffers.layer_inputs.len() + 1
    {
        return Err(Error::ShapeMismatch);
    }
    if buffers
        .jacobian
        .is_some_and(|values| values.len() != sample_count * jacobian::STATE_COUNT)
        || buffers
            .noise_sigma
            .is_some_and(|values| values.len() != sample_count)
        || buffers
            .radiance_noise_sigma
            .is_some_and(|values| values.len() != sample_count)
        || buffers
            .irradiance_noise_sigma
            .is_some_and(|values| values.len() != sample_count)
        || buffers
            .reflectance_noise_sigma
            .is_some_and(|values| values.len() != sample_count)
    {
        return Err(Error::ShapeMismatch);
    }
    Ok(())
}
