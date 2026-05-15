use crate::{
    common::errors,
    forward_model::{
        implementations::root as implementation_root,
        instrument_grid::{
            grid_calculation::{
                cache::SpectralEvaluationCache,
                forward_input::ForwardInputBuffers,
                postprocess,
                spectral_eval::{
                    self, integrate_forward_at_nominal, integrate_irradiance_at_nominal,
                },
                spectral_forward, storage,
                types::{Implementations, InstrumentGridProduct, InstrumentGridSummary},
                wavelength_plan::WavelengthSampling,
                wavelength_sampling,
            },
            spectral_math::{
                calibration,
                grid::{self, ResolvedAxis, SpectralGrid},
            },
        },
        jacobian,
        optical_properties::state_build::PreparedOpticalState,
        radiative_transfer::common_types::{
            LayerInput, PseudoSphericalSample, Route, RtmQuadratureLevel, SourceInterfaceInput,
        },
    },
    input::{instrument::SpectralChannel, scene::Scene},
};
use rayon::prelude::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    Scene(errors::Error),
    Grid(grid::Error),
    SpectralEval(spectral_eval::Error),
    InstrumentIntegration(crate::forward_model::implementations::instrument::Error),
    Postprocess(postprocess::Error),
    WavelengthSampling(wavelength_sampling::Error),
}

impl From<errors::Error> for Error {
    fn from(value: errors::Error) -> Self {
        Self::Scene(value)
    }
}

impl From<grid::Error> for Error {
    fn from(value: grid::Error) -> Self {
        Self::Grid(value)
    }
}

impl From<spectral_eval::Error> for Error {
    fn from(value: spectral_eval::Error) -> Self {
        Self::SpectralEval(value)
    }
}

impl From<crate::forward_model::implementations::instrument::Error> for Error {
    fn from(value: crate::forward_model::implementations::instrument::Error) -> Self {
        Self::InstrumentIntegration(value)
    }
}

impl From<wavelength_sampling::Error> for Error {
    fn from(value: wavelength_sampling::Error) -> Self {
        Self::WavelengthSampling(value)
    }
}

impl From<postprocess::Error> for Error {
    fn from(value: postprocess::Error) -> Self {
        Self::Postprocess(value)
    }
}

struct RunningSummary {
    radiance_sum: f64,
    irradiance_sum: f64,
    reflectance_sum: f64,
    noise_sum: f64,
    jacobian_sum: jacobian::Vector,
}

struct ForwardScratch {
    layer_inputs: Vec<LayerInput>,
    pseudo_spherical_layers: Vec<LayerInput>,
    source_interfaces: Vec<SourceInterfaceInput>,
    rtm_quadrature_levels: Vec<RtmQuadratureLevel>,
    pseudo_spherical_samples: Vec<PseudoSphericalSample>,
    pseudo_spherical_level_starts: Vec<usize>,
    pseudo_spherical_level_altitudes: Vec<f64>,
}

impl ForwardScratch {
    fn new(transport_layer_count: usize, pseudo_spherical_sample_count: usize) -> Self {
        Self {
            layer_inputs: vec![LayerInput::default(); transport_layer_count],
            pseudo_spherical_layers: vec![LayerInput::default(); pseudo_spherical_sample_count],
            source_interfaces: vec![SourceInterfaceInput::default(); transport_layer_count + 1],
            rtm_quadrature_levels: vec![RtmQuadratureLevel::default(); transport_layer_count + 1],
            pseudo_spherical_samples: vec![
                PseudoSphericalSample::default();
                pseudo_spherical_sample_count
            ],
            pseudo_spherical_level_starts: vec![0; transport_layer_count + 1],
            pseudo_spherical_level_altitudes: vec![0.0; transport_layer_count + 1],
        }
    }

    fn buffers(&mut self) -> ForwardInputBuffers<'_> {
        ForwardInputBuffers {
            layer_inputs: &mut self.layer_inputs,
            pseudo_spherical_layers: &mut self.pseudo_spherical_layers,
            source_interfaces: &mut self.source_interfaces,
            rtm_quadrature_levels: &mut self.rtm_quadrature_levels,
            pseudo_spherical_samples: &mut self.pseudo_spherical_samples,
            pseudo_spherical_level_starts: &mut self.pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes: &mut self.pseudo_spherical_level_altitudes,
        }
    }
}

impl RunningSummary {
    fn new() -> Self {
        Self {
            radiance_sum: 0.0,
            irradiance_sum: 0.0,
            reflectance_sum: 0.0,
            noise_sum: 0.0,
            jacobian_sum: jacobian::zero(),
        }
    }

    fn to_summary(
        &self,
        wavelengths: &[f64],
        has_noise_sigma: bool,
        mean_jacobian: Option<jacobian::Vector>,
    ) -> InstrumentGridSummary {
        let denominator = wavelengths.len() as f64;
        InstrumentGridSummary {
            sample_count: wavelengths.len() as u32,
            wavelength_start_nm: wavelengths[0],
            wavelength_end_nm: wavelengths[wavelengths.len() - 1],
            mean_radiance: self.radiance_sum / denominator,
            mean_irradiance: self.irradiance_sum / denominator,
            mean_reflectance: self.reflectance_sum / denominator,
            mean_noise_sigma: if has_noise_sigma {
                self.noise_sum / denominator
            } else {
                0.0
            },
            mean_jacobian,
        }
    }
}

fn precompute_forward_cache(
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
    wavelength_sampling: &[WavelengthSampling],
    cache: &mut SpectralEvaluationCache,
) -> Result<(), spectral_eval::Error> {
    let forward_misses = wavelength_sampling::collect_unique_forward_misses(wavelength_sampling);
    let transport_layer_count = storage::resolved_transport_layer_count(route, prepared);
    let pseudo_spherical_sample_count =
        storage::resolved_pseudo_spherical_sample_count(scene, route, prepared);

    // Most O2 A instrument samples overlap heavily across nominal wavelengths.
    // Computing each unique forward wavelength once avoids duplicate RTM work,
    // and thread-local buffers keep the parallel path free of shared mutation.
    let samples: Result<Vec<_>, spectral_eval::Error> = forward_misses
        .par_iter()
        .map_init(
            || ForwardScratch::new(transport_layer_count, pseudo_spherical_sample_count),
            |scratch, miss| {
                spectral_forward::compute_forward_sample_at_wavelength(
                    scene,
                    route,
                    prepared,
                    miss.wavelength_nm,
                    scratch.buffers(),
                )
                .map(|sample| (miss.wavelength_nm, sample))
                .map_err(spectral_eval::Error::from)
            },
        )
        .collect();

    for (wavelength_nm, sample) in samples? {
        cache.put_forward(wavelength_nm, sample);
    }

    Ok(())
}

pub fn simulate_product(
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
) -> Result<InstrumentGridProduct, Error> {
    simulate_product_with_implementations(scene, route, prepared, implementation_root::exact())
}

pub fn simulate_product_with_implementations(
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
    implementations: Implementations,
) -> Result<InstrumentGridProduct, Error> {
    scene.validate()?;
    let axis = ResolvedAxis {
        base: SpectralGrid {
            start_nm: scene.spectral_grid.start_nm,
            end_nm: scene.spectral_grid.end_nm,
            sample_count: scene.spectral_grid.sample_count,
        },
        explicit_wavelengths_nm: scene.observation_model.measured_wavelengths_nm.clone(),
    };
    axis.validate()?;
    let instrument_provider = implementations.instrument;
    let noise_provider = implementations.noise;
    let wavelength_sampling = wavelength_sampling::build_wavelength_sampling(
        scene,
        &axis,
        prepared,
        instrument_provider,
    )?;
    let mut cache = SpectralEvaluationCache::default();
    precompute_forward_cache(scene, route, prepared, &wavelength_sampling, &mut cache)?;

    let sample_count = scene.spectral_grid.sample_count as usize;
    let transport_layer_count = storage::resolved_transport_layer_count(route, prepared);
    let pseudo_spherical_sample_count =
        storage::resolved_pseudo_spherical_sample_count(scene, route, prepared);
    let mut layer_inputs = vec![LayerInput::default(); transport_layer_count];
    let mut pseudo_spherical_layers = vec![LayerInput::default(); pseudo_spherical_sample_count];
    let mut source_interfaces = vec![SourceInterfaceInput::default(); transport_layer_count + 1];
    let mut rtm_quadrature_levels = vec![RtmQuadratureLevel::default(); transport_layer_count + 1];
    let mut pseudo_spherical_samples =
        vec![PseudoSphericalSample::default(); pseudo_spherical_sample_count];
    let mut pseudo_spherical_level_starts = vec![0; transport_layer_count + 1];
    let mut pseudo_spherical_level_altitudes = vec![0.0; transport_layer_count + 1];

    let mut wavelengths = vec![0.0; sample_count];
    let mut radiance = vec![0.0; sample_count];
    let mut irradiance = vec![0.0; sample_count];
    let mut reflectance = vec![0.0; sample_count];
    let mut noise_sigma = vec![0.0; sample_count];
    let mut scratch = vec![0.0; sample_count];
    let mut scratch_aux = vec![0.0; sample_count];
    let wants_jacobian = route.derivative_mode != crate::input::scene::DerivativeMode::None;
    let mut jacobian_values =
        wants_jacobian.then(|| vec![0.0; sample_count * jacobian::STATE_COUNT]);
    let mut summary = RunningSummary::new();
    let solar_cosine = scene.geometry.solar_cosine_at_altitude(0.0);
    let mut forward_buffers = ForwardInputBuffers {
        layer_inputs: &mut layer_inputs,
        pseudo_spherical_layers: &mut pseudo_spherical_layers,
        source_interfaces: &mut source_interfaces,
        rtm_quadrature_levels: &mut rtm_quadrature_levels,
        pseudo_spherical_samples: &mut pseudo_spherical_samples,
        pseudo_spherical_level_starts: &mut pseudo_spherical_level_starts,
        pseudo_spherical_level_altitudes: &mut pseudo_spherical_level_altitudes,
    };

    for (index, plan) in wavelength_sampling.iter().enumerate() {
        let sample = integrate_forward_at_nominal(
            scene,
            route,
            prepared,
            plan.radiance_wavelength_nm,
            &mut forward_buffers,
            &mut cache,
            &plan.radiance_integration,
        )?;
        let sample_irradiance = integrate_irradiance_at_nominal(
            scene,
            plan.irradiance_wavelength_nm,
            &mut cache,
            &plan.irradiance_integration,
        )?;
        wavelengths[index] = plan.nominal_wavelength_nm;
        radiance[index] = sample.radiance;
        irradiance[index] = sample_irradiance;
        if let Some(values) = &mut jacobian_values {
            let start = index * jacobian::STATE_COUNT;
            values[start..start + jacobian::STATE_COUNT].copy_from_slice(&sample.jacobian);
        }
    }

    postprocess::apply_channel_corrections(
        scene,
        SpectralChannel::Radiance,
        (instrument_provider.calibration_for_scene)(scene, SpectralChannel::Radiance),
        prepared.depolarization_factor,
        &wavelengths,
        &mut radiance,
        &mut scratch,
    )?;
    postprocess::apply_channel_corrections(
        scene,
        SpectralChannel::Irradiance,
        (instrument_provider.calibration_for_scene)(scene, SpectralChannel::Irradiance),
        prepared.depolarization_factor,
        &wavelengths,
        &mut irradiance,
        &mut scratch,
    )?;
    calibration::apply_ring_spectrum(
        &scene.observation_model.resolved_ring_controls(),
        &wavelengths,
        &irradiance,
        &mut radiance,
        &mut scratch,
    )
    .map_err(postprocess::Error::from)?;

    if let Some(values) = &mut jacobian_values {
        for state_index in 0..jacobian::STATE_COUNT {
            for sample_index in 0..sample_count {
                scratch[sample_index] = values[sample_index * jacobian::STATE_COUNT + state_index];
            }
            postprocess::apply_channel_jacobian_corrections(
                scene,
                SpectralChannel::Radiance,
                (instrument_provider.calibration_for_scene)(scene, SpectralChannel::Radiance),
                prepared.depolarization_factor,
                &wavelengths,
                &mut scratch,
                &mut scratch_aux,
            )?;
            for sample_index in 0..sample_count {
                values[sample_index * jacobian::STATE_COUNT + state_index] = scratch[sample_index];
            }
        }
    }

    let has_noise_sigma = (noise_provider.materializes_sigma)(scene, SpectralChannel::Radiance);
    postprocess::materialize_channel_sigma(
        noise_provider,
        scene,
        SpectralChannel::Radiance,
        &wavelengths,
        &radiance,
        &mut noise_sigma,
    )?;
    summary.noise_sum = noise_sigma.iter().sum();

    for index in 0..sample_count {
        let sample_reflectance = if irradiance[index] > 0.0 && solar_cosine > 0.0 {
            radiance[index] * std::f64::consts::PI / (irradiance[index] * solar_cosine)
        } else {
            0.0
        };
        reflectance[index] = sample_reflectance;
        summary.radiance_sum += radiance[index];
        summary.irradiance_sum += irradiance[index];
        summary.reflectance_sum += sample_reflectance;
        if let Some(values) = &jacobian_values {
            let start = index * jacobian::STATE_COUNT;
            let mut row = jacobian::zero();
            row.copy_from_slice(&values[start..start + jacobian::STATE_COUNT]);
            jacobian::add_scaled(&mut summary.jacobian_sum, row, 1.0);
        }
    }

    let mean_jacobian = jacobian_values.as_ref().map(|_| {
        let mut mean = summary.jacobian_sum;
        for value in &mut mean {
            *value /= sample_count as f64;
        }
        mean
    });
    let product_summary = summary.to_summary(&wavelengths, has_noise_sigma, mean_jacobian);
    Ok(InstrumentGridProduct {
        summary: product_summary,
        wavelengths,
        radiance,
        irradiance,
        reflectance,
        noise_sigma,
        radiance_noise_sigma: Vec::new(),
        irradiance_noise_sigma: Vec::new(),
        reflectance_noise_sigma: Vec::new(),
        jacobian: jacobian_values,
        effective_air_mass_factor: prepared.effective_air_mass_factor,
        effective_single_scatter_albedo: prepared.effective_single_scatter_albedo,
        effective_temperature_k: prepared.effective_temperature_k,
        effective_pressure_hpa: prepared.effective_pressure_hpa,
        gas_optical_depth: prepared.gas_optical_depth,
        cia_optical_depth: prepared.cia_optical_depth,
        aerosol_optical_depth: prepared.aerosol_optical_depth,
        cloud_optical_depth: prepared.cloud_optical_depth,
        total_optical_depth: prepared.total_optical_depth,
        depolarization_factor: prepared.depolarization_factor,
        d_optical_depth_d_temperature: prepared.d_optical_depth_d_temperature,
    })
}
