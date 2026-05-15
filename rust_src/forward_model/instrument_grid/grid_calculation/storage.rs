use crate::{
    forward_model::{
        instrument_grid::grid_calculation::{
            cache::SpectralEvaluationCache,
            types::Implementations,
            wavelength_plan::{ForwardCacheMiss, WavelengthSampling},
        },
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

#[derive(Debug)]
pub struct BuffersMut<'a> {
    pub wavelengths: &'a mut [f64],
    pub radiance: &'a mut [f64],
    pub irradiance: &'a mut [f64],
    pub reflectance: &'a mut [f64],
    pub scratch: &'a mut [f64],
    pub scratch_aux: &'a mut [f64],
    pub layer_inputs: &'a mut [LayerInput],
    pub pseudo_spherical_layers: &'a mut [LayerInput],
    pub source_interfaces: &'a mut [SourceInterfaceInput],
    pub rtm_quadrature_levels: &'a mut [RtmQuadratureLevel],
    pub pseudo_spherical_samples: &'a mut [PseudoSphericalSample],
    pub pseudo_spherical_level_starts: &'a mut [usize],
    pub pseudo_spherical_level_altitudes: &'a mut [f64],
    pub jacobian: Option<&'a mut [f64]>,
    pub noise_sigma: Option<&'a mut [f64]>,
    pub radiance_noise_sigma: Option<&'a mut [f64]>,
    pub irradiance_noise_sigma: Option<&'a mut [f64]>,
    pub reflectance_noise_sigma: Option<&'a mut [f64]>,
}

#[derive(Debug, Default)]
pub struct SummaryStorage {
    pub wavelengths: Vec<f64>,
    pub radiance: Vec<f64>,
    pub irradiance: Vec<f64>,
    pub reflectance: Vec<f64>,
    pub scratch: Vec<f64>,
    pub scratch_aux: Vec<f64>,
    pub layer_inputs: Vec<LayerInput>,
    pub pseudo_spherical_layers: Vec<LayerInput>,
    pub source_interfaces: Vec<SourceInterfaceInput>,
    pub rtm_quadrature_levels: Vec<RtmQuadratureLevel>,
    pub pseudo_spherical_samples: Vec<PseudoSphericalSample>,
    pub pseudo_spherical_level_starts: Vec<usize>,
    pub pseudo_spherical_level_altitudes: Vec<f64>,
    pub jacobian: Vec<f64>,
    pub noise_sigma: Vec<f64>,
    pub radiance_noise_sigma: Vec<f64>,
    pub irradiance_noise_sigma: Vec<f64>,
    pub reflectance_noise_sigma: Vec<f64>,
    pub evaluation_cache: SpectralEvaluationCache,
    pub wavelength_sampling: Vec<WavelengthSampling>,
    pub forward_misses: Vec<ForwardCacheMiss>,
    pub wavelength_plan_key: u64,
    pub wavelength_plan_valid: bool,
    pub forward_misses_valid: bool,
    pub profile_spectroscopy_cache_key: u64,
    pub profile_spectroscopy_cache_valid: bool,
}

pub type ProductStorage = SummaryStorage;

impl SummaryStorage {
    pub fn invalidate_wavelength_plan(&mut self) {
        self.wavelength_sampling.clear();
        self.forward_misses.clear();
        self.wavelength_plan_key = 0;
        self.wavelength_plan_valid = false;
        self.forward_misses_valid = false;
        self.profile_spectroscopy_cache_key = 0;
        self.profile_spectroscopy_cache_valid = false;
    }

    pub fn spectral_cache(&mut self) -> &mut SpectralEvaluationCache {
        self.evaluation_cache.reset();
        &mut self.evaluation_cache
    }

    pub fn buffers(
        &mut self,
        scene: &Scene,
        route: Route,
        implementations: Implementations,
    ) -> BuffersMut<'_> {
        let sample_count = scene.spectral_grid.sample_count as usize;
        let layer_count = transport_layer_count_hint(scene, route);
        let pseudo_spherical_sample_count = pseudo_spherical_sample_count_hint(scene, route);
        let wants_jacobian = route.derivative_mode != crate::input::scene::DerivativeMode::None;
        let wants_radiance_noise =
            (implementations.noise.materializes_sigma)(scene, SpectralChannel::Radiance);
        let wants_irradiance_noise =
            (implementations.noise.materializes_sigma)(scene, SpectralChannel::Irradiance);
        let wants_noise = wants_radiance_noise
            || wants_irradiance_noise
            || reflectance_calibration_enabled(scene);

        resize_with_default(&mut self.wavelengths, sample_count);
        resize_with_default(&mut self.radiance, sample_count);
        resize_with_default(&mut self.irradiance, sample_count);
        resize_with_default(&mut self.reflectance, sample_count);
        resize_with_default(&mut self.scratch, sample_count);
        resize_with_default(&mut self.scratch_aux, sample_count);
        resize_with_default(&mut self.layer_inputs, layer_count);
        resize_with_default(
            &mut self.pseudo_spherical_layers,
            pseudo_spherical_sample_count,
        );
        resize_with_default(&mut self.source_interfaces, layer_count + 1);
        resize_with_default(&mut self.rtm_quadrature_levels, layer_count + 1);
        resize_with_default(
            &mut self.pseudo_spherical_samples,
            pseudo_spherical_sample_count,
        );
        resize_with_default(&mut self.pseudo_spherical_level_starts, layer_count + 1);
        resize_with_default(&mut self.pseudo_spherical_level_altitudes, layer_count + 1);
        if wants_jacobian {
            resize_with_default(&mut self.jacobian, sample_count * jacobian::STATE_COUNT);
        }
        if wants_noise {
            resize_with_default(&mut self.noise_sigma, sample_count);
            resize_with_default(&mut self.radiance_noise_sigma, sample_count);
            resize_with_default(&mut self.irradiance_noise_sigma, sample_count);
            resize_with_default(&mut self.reflectance_noise_sigma, sample_count);
        }

        BuffersMut {
            wavelengths: &mut self.wavelengths[..sample_count],
            radiance: &mut self.radiance[..sample_count],
            irradiance: &mut self.irradiance[..sample_count],
            reflectance: &mut self.reflectance[..sample_count],
            scratch: &mut self.scratch[..sample_count],
            scratch_aux: &mut self.scratch_aux[..sample_count],
            layer_inputs: &mut self.layer_inputs[..layer_count],
            pseudo_spherical_layers: &mut self.pseudo_spherical_layers
                [..pseudo_spherical_sample_count],
            source_interfaces: &mut self.source_interfaces[..layer_count + 1],
            rtm_quadrature_levels: &mut self.rtm_quadrature_levels[..layer_count + 1],
            pseudo_spherical_samples: &mut self.pseudo_spherical_samples
                [..pseudo_spherical_sample_count],
            pseudo_spherical_level_starts: &mut self.pseudo_spherical_level_starts
                [..layer_count + 1],
            pseudo_spherical_level_altitudes: &mut self.pseudo_spherical_level_altitudes
                [..layer_count + 1],
            jacobian: if wants_jacobian {
                Some(&mut self.jacobian[..sample_count * jacobian::STATE_COUNT])
            } else {
                None
            },
            noise_sigma: if wants_noise {
                Some(&mut self.noise_sigma[..sample_count])
            } else {
                None
            },
            radiance_noise_sigma: if wants_noise {
                Some(&mut self.radiance_noise_sigma[..sample_count])
            } else {
                None
            },
            irradiance_noise_sigma: if wants_noise {
                Some(&mut self.irradiance_noise_sigma[..sample_count])
            } else {
                None
            },
            reflectance_noise_sigma: if wants_noise {
                Some(&mut self.reflectance_noise_sigma[..sample_count])
            } else {
                None
            },
        }
    }
}

fn resize_with_default<T: Default>(buffer: &mut Vec<T>, len: usize) {
    if buffer.len() < len {
        buffer.resize_with(len, T::default);
    }
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
