use crate::{
    forward_model::{
        instrument_grid::grid_calculation::{
            cache::SpectralEvaluationCache,
            types::Implementations,
            wavelength_plan::{ForwardCacheMiss, WavelengthSampling},
        },
        jacobian,
        radiative_transfer::{
            LayerInput, PseudoSphericalSample, Route, RtmQuadratureLevel, SourceInterfaceInput,
        },
    },
    input::{IntegrationMode, Scene, SpectralChannel},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ShapeMismatch,
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug)]
pub struct Buffers<'a> {
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

#[derive(Debug, Clone, Default, PartialEq)]
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
    pub evaluation_cache: Option<SpectralEvaluationCache>,
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
        let cache = self.evaluation_cache.get_or_insert_with(Default::default);
        cache.reset();
        cache
    }

    pub fn buffers(
        &mut self,
        scene: &Scene,
        route: Route,
        implementations: Implementations,
    ) -> Buffers<'_> {
        let sample_count = scene.spectral_grid.sample_count as usize;
        let layer_count = transport_layer_count_hint(scene, route);
        let pseudo_spherical_sample_count = pseudo_spherical_sample_count_hint(scene, route);
        let wants_jacobian = route.derivative_mode != crate::input::DerivativeMode::None;
        let wants_radiance_noise =
            (implementations.noise.materializes_sigma)(scene, SpectralChannel::Radiance);
        let wants_irradiance_noise =
            (implementations.noise.materializes_sigma)(scene, SpectralChannel::Irradiance);
        let wants_noise = wants_radiance_noise
            || wants_irradiance_noise
            || reflectance_calibration_enabled(scene);

        ensure_capacity(&mut self.wavelengths, sample_count);
        ensure_capacity(&mut self.radiance, sample_count);
        ensure_capacity(&mut self.irradiance, sample_count);
        ensure_capacity(&mut self.reflectance, sample_count);
        ensure_capacity(&mut self.scratch, sample_count);
        ensure_capacity(&mut self.scratch_aux, sample_count);
        ensure_capacity(&mut self.layer_inputs, layer_count);
        ensure_capacity(
            &mut self.pseudo_spherical_layers,
            pseudo_spherical_sample_count,
        );
        ensure_capacity(&mut self.source_interfaces, layer_count + 1);
        ensure_capacity(&mut self.rtm_quadrature_levels, layer_count + 1);
        ensure_capacity(
            &mut self.pseudo_spherical_samples,
            pseudo_spherical_sample_count,
        );
        ensure_capacity(&mut self.pseudo_spherical_level_starts, layer_count + 1);
        ensure_capacity(&mut self.pseudo_spherical_level_altitudes, layer_count + 1);
        if wants_jacobian {
            ensure_capacity(&mut self.jacobian, sample_count * jacobian::STATE_COUNT);
        }
        if wants_noise {
            ensure_capacity(&mut self.noise_sigma, sample_count);
            ensure_capacity(&mut self.radiance_noise_sigma, sample_count);
            ensure_capacity(&mut self.irradiance_noise_sigma, sample_count);
            ensure_capacity(&mut self.reflectance_noise_sigma, sample_count);
        }

        Buffers {
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
            jacobian: wants_jacobian
                .then_some(&mut self.jacobian[..sample_count * jacobian::STATE_COUNT]),
            noise_sigma: wants_noise.then_some(&mut self.noise_sigma[..sample_count]),
            radiance_noise_sigma: wants_noise
                .then_some(&mut self.radiance_noise_sigma[..sample_count]),
            irradiance_noise_sigma: wants_noise
                .then_some(&mut self.irradiance_noise_sigma[..sample_count]),
            reflectance_noise_sigma: wants_noise
                .then_some(&mut self.reflectance_noise_sigma[..sample_count]),
        }
    }
}

pub fn transport_layer_count_hint(scene: &Scene, _route: Route) -> usize {
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
        let mut total_count = 0;
        for interval in &scene.atmosphere.interval_grid.intervals {
            total_count += if uses_disamar_shared_rtm_grid {
                interval.altitude_divisions as usize + 1
            } else {
                (interval.altitude_divisions as usize).max(1)
            };
        }
        return total_count.max(1);
    }
    let layer_count = (scene.atmosphere.layer_count as usize).max(1);
    layer_count * (scene.atmosphere.sublayer_divisions as usize).max(1)
}

pub fn pseudo_spherical_sample_count_hint(scene: &Scene, route: Route) -> usize {
    let layer_count = transport_layer_count_hint(scene, route);
    layer_count * (pseudo_spherical_subgrid_divisions(scene) + 2)
}

pub fn reflectance_calibration_enabled(scene: &Scene) -> bool {
    let controls = scene.observation_model.resolved_reflectance_calibration();
    controls.multiplicative_error.enabled() || controls.additive_error.enabled()
}

fn pseudo_spherical_subgrid_divisions(scene: &Scene) -> usize {
    (scene.atmosphere.sublayer_divisions as usize).max(1)
}

pub fn validate_buffers(sample_count: usize, buffers: &Buffers<'_>) -> Result<()> {
    // All per-spectrum arrays must describe the same sweep; mismatched shapes
    // usually mean a reused workspace was sized for an older scene.
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
        .as_ref()
        .is_some_and(|values| values.len() != sample_count * jacobian::STATE_COUNT)
    {
        return Err(Error::ShapeMismatch);
    }
    if buffers
        .noise_sigma
        .as_ref()
        .is_some_and(|values| values.len() != sample_count)
        || buffers
            .radiance_noise_sigma
            .as_ref()
            .is_some_and(|values| values.len() != sample_count)
        || buffers
            .irradiance_noise_sigma
            .as_ref()
            .is_some_and(|values| values.len() != sample_count)
        || buffers
            .reflectance_noise_sigma
            .as_ref()
            .is_some_and(|values| values.len() != sample_count)
    {
        return Err(Error::ShapeMismatch);
    }
    Ok(())
}

fn ensure_capacity<T: Default + Clone>(buffer: &mut Vec<T>, capacity: usize) {
    if buffer.len() < capacity {
        buffer.resize_with(capacity, T::default);
    }
}
