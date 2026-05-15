use std::{fs, io, num::ParseFloatError};

use crate::{
    common::errors,
    forward_model::radiative_transfer::{
        common_route,
        common_types::{self, DispatchRequest},
    },
    input::{
        absorber::{
            Absorber, AbsorberSet, LineGasControls, Spectroscopy, SpectroscopyMode,
            SpectroscopyStage,
        },
        atmosphere::{IntervalGrid, IntervalSemantics},
        atmospheric_types::AbsorberSpecies,
        binding::Binding,
        geometry::Geometry,
        instrument::{
            Id as InstrumentId, IntegrationMode, OperationalSolarSpectrum, SlitIndex,
            SpectralChannelControls, SpectralResponse,
        },
        observation_model::ObservationModel,
        reference_data::{ClimatologyPoint, ClimatologyProfile},
        scene::Scene,
        surface::Surface,
    },
};

use super::types::{
    ExternalAsset, LineGasSpec, ReferenceSample, ResolvedVendorO2ACase, SolarSpectrumSample,
};

#[derive(Debug)]
pub enum Error {
    Io(io::Error),
    ParseFloat(ParseFloatError),
    InvalidData,
    InvalidRequest(errors::Error),
    Route(common_types::Error),
    UnsupportedSolarReferenceAssetFormat,
}

impl From<io::Error> for Error {
    fn from(value: io::Error) -> Self {
        Self::Io(value)
    }
}

impl From<ParseFloatError> for Error {
    fn from(value: ParseFloatError) -> Self {
        Self::ParseFloat(value)
    }
}

impl From<errors::Error> for Error {
    fn from(value: errors::Error) -> Self {
        Self::InvalidRequest(value)
    }
}

impl From<common_types::Error> for Error {
    fn from(value: common_types::Error) -> Self {
        Self::Route(value)
    }
}

pub type Route = common_types::Route;

pub fn load_reference_samples(path: &str) -> Result<Vec<ReferenceSample>, Error> {
    let bytes = fs::read_to_string(path)?;
    let mut samples = Vec::new();

    for line in bytes.lines().skip(1) {
        let trimmed = line.trim_matches(['\r', ' ', '\t']);
        if trimmed.is_empty() {
            continue;
        }

        let mut columns = trimmed.split(',');
        let wavelength_nm = parse_csv_f64(columns.next())?;
        let irradiance = parse_csv_f64(columns.next())?;
        let _radiance = parse_csv_f64(columns.next())?;
        let reflectance = parse_csv_f64(columns.next())?;

        samples.push(ReferenceSample {
            wavelength_nm,
            irradiance,
            reflectance,
        });
    }

    Ok(samples)
}

pub fn load_solar_spectrum_samples(
    asset: &ExternalAsset,
) -> Result<Vec<SolarSpectrumSample>, Error> {
    if asset.format != "solar_reference_csv" {
        return Err(Error::UnsupportedSolarReferenceAssetFormat);
    }

    let bytes = fs::read_to_string(&asset.path)?;
    let mut samples = Vec::new();

    for line in bytes.lines().skip(1) {
        let trimmed = line.trim_matches(['\r', ' ', '\t']);
        if trimmed.is_empty() {
            continue;
        }

        let mut columns = trimmed.split(',');
        samples.push(SolarSpectrumSample {
            wavelength_nm: parse_csv_f64(columns.next())?,
            irradiance: parse_csv_f64(columns.next())?,
        });
    }

    Ok(samples)
}

pub fn load_climatology_profile(asset: &ExternalAsset) -> Result<ClimatologyProfile, Error> {
    if asset.format != "profile_csv" {
        return Err(Error::InvalidData);
    }

    let bytes = fs::read_to_string(&asset.path)?;
    let mut rows = Vec::new();

    for line in bytes.lines().skip(1) {
        let trimmed = line.trim_matches(['\r', ' ', '\t']);
        if trimmed.is_empty() {
            continue;
        }

        let mut columns = trimmed.split(',');
        rows.push(ClimatologyPoint {
            altitude_km: parse_csv_f64(columns.next())?,
            pressure_hpa: parse_csv_f64(columns.next())?,
            temperature_k: parse_csv_f64(columns.next())?,
            air_number_density_cm3: parse_csv_f64(columns.next())?,
        });
    }

    Ok(ClimatologyProfile { rows })
}

pub fn build_vendor_trace_gas_spectroscopy_profile(
    source_profile: &ClimatologyProfile,
    dense_profile: &ClimatologyProfile,
) -> ClimatologyProfile {
    ClimatologyProfile {
        rows: source_profile
            .rows
            .iter()
            .map(|source_row| {
                let pressure_hpa = source_row.pressure_hpa;
                let temperature_k = source_row.temperature_k;
                ClimatologyPoint {
                    altitude_km: dense_profile
                        .interpolate_altitude_for_pressure_spline(pressure_hpa),
                    pressure_hpa,
                    temperature_k,
                    air_number_density_cm3: pressure_hpa / temperature_k.max(1.0e-9) / 1.380658e-19,
                }
            })
            .collect(),
    }
}

pub fn build_resolved_vendor_o2a_scene(
    resolved: &ResolvedVendorO2ACase,
    raw_solar_spectrum: &[SolarSpectrumSample],
) -> Result<Scene, Error> {
    let mut solar_spectrum = retain_solar_support(resolved, raw_solar_spectrum)?;
    solar_spectrum.prepare_interpolation()?;

    let absorber_set = build_o2_absorber_set(&resolved.o2);
    let reference_response = reference_spectral_response(resolved);
    let mut scene =
        scene_from_resolved_o2a(resolved, absorber_set, solar_spectrum, reference_response);
    attach_resolved_intervals(&mut scene, resolved);
    scene.validate()?;
    Ok(scene)
}

pub fn prepare_resolved_vendor_o2a_route(
    scene: &Scene,
    resolved: &ResolvedVendorO2ACase,
) -> Result<Route, Error> {
    Ok(common_route::prepare_route(DispatchRequest {
        regime: scene.observation_model.regime,
        execution_mode: resolved
            .plan
            .execution_mode()
            .map_err(|_| errors::Error::InvalidRequest)?,
        derivative_mode: resolved
            .plan
            .derivative_mode()
            .map_err(|_| errors::Error::InvalidRequest)?,
        rtm_controls: resolved.rtm_controls,
    })?)
}

pub fn retain_solar_support(
    resolved: &ResolvedVendorO2ACase,
    raw_solar_spectrum: &[SolarSpectrumSample],
) -> Result<OperationalSolarSpectrum, Error> {
    let solar_support_start_nm =
        resolved.spectral_grid.start_nm - (2.0 * resolved.observation.instrument_line_fwhm_nm);
    let solar_support_end_nm =
        resolved.spectral_grid.end_nm + (2.0 * resolved.observation.instrument_line_fwhm_nm);

    let retained = raw_solar_spectrum
        .iter()
        .copied()
        .filter(|sample| {
            sample.wavelength_nm > solar_support_start_nm
                && sample.wavelength_nm < solar_support_end_nm
        })
        .collect::<Vec<_>>();
    if retained.len() < 3 {
        return Err(Error::InvalidData);
    }

    Ok(OperationalSolarSpectrum {
        wavelengths_nm: retained.iter().map(|sample| sample.wavelength_nm).collect(),
        irradiance: retained.iter().map(|sample| sample.irradiance).collect(),
        spline_second_derivatives: Vec::new(),
    })
}

pub fn build_o2_absorber_set(spec: &LineGasSpec) -> AbsorberSet {
    AbsorberSet {
        items: vec![Absorber {
            id: "o2".to_string(),
            species: "o2".to_string(),
            resolved_species: Some(AbsorberSpecies::O2),
            profile_source: Binding::Atmosphere,
            spectroscopy: Spectroscopy {
                mode: SpectroscopyMode::LineByLine,
                line_gas_controls: LineGasControls {
                    factor_lm_sim: spec.line_mixing_factor,
                    isotopes_sim: spec.isotopes_sim.clone(),
                    threshold_line_sim: spec.threshold_line_sim,
                    cutoff_sim_cm1: spec.cutoff_sim_cm1,
                    active_stage: SpectroscopyStage::Simulation,
                    ..LineGasControls::default()
                },
                ..Spectroscopy::default()
            },
            ..Absorber::default()
        }],
    }
}

pub fn reference_spectral_response(resolved: &ResolvedVendorO2ACase) -> SpectralResponse {
    let slit_index = match resolved.observation.builtin_line_shape {
        crate::input::instrument::BuiltinLineShapeKind::Gaussian => SlitIndex::GaussianModulated,
        crate::input::instrument::BuiltinLineShapeKind::FlatTopN4 => SlitIndex::FlatTopN4,
        crate::input::instrument::BuiltinLineShapeKind::TripleFlatTopN4 => {
            SlitIndex::TripleFlatTopN4
        }
    };

    SpectralResponse {
        explicit: true,
        slit_index,
        fwhm_nm: resolved.observation.instrument_line_fwhm_nm,
        builtin_line_shape: resolved.observation.builtin_line_shape,
        integration_mode: IntegrationMode::DisamarHrGrid,
        high_resolution_step_nm: resolved.observation.high_resolution_step_nm,
        high_resolution_half_span_nm: resolved.observation.high_resolution_half_span_nm,
        ..SpectralResponse::default()
    }
}

fn scene_from_resolved_o2a(
    resolved: &ResolvedVendorO2ACase,
    absorber_set: AbsorberSet,
    solar_spectrum: OperationalSolarSpectrum,
    reference_response: SpectralResponse,
) -> Scene {
    Scene {
        id: resolved.scene_id.clone(),
        surface: Surface {
            albedo: resolved.surface_albedo,
            pressure_hpa: resolved.surface_pressure_hpa,
            ..Surface::default()
        },
        aerosol: crate::input::aerosol::Aerosol {
            enabled: true,
            optical_depth: resolved.aerosol.optical_depth,
            single_scatter_albedo: resolved.aerosol.single_scatter_albedo,
            asymmetry_factor: resolved.aerosol.asymmetry_factor,
            angstrom_exponent: resolved.aerosol.angstrom_exponent,
            reference_wavelength_nm: resolved.aerosol.reference_wavelength_nm,
            layer_center_km: resolved.aerosol.layer_center_km,
            layer_width_km: resolved.aerosol.layer_width_km,
            placement: resolved.aerosol.placement,
            ..crate::input::aerosol::Aerosol::default()
        },
        geometry: Geometry {
            model: resolved.geometry.model,
            solar_zenith_deg: resolved.geometry.solar_zenith_deg,
            viewing_zenith_deg: resolved.geometry.viewing_zenith_deg,
            relative_azimuth_deg: resolved.geometry.relative_azimuth_deg,
            ..Geometry::default()
        },
        atmosphere: crate::input::atmosphere::Atmosphere {
            layer_count: resolved.layer_count,
            sublayer_divisions: resolved.sublayer_divisions,
            surface_pressure_hpa: resolved.surface_pressure_hpa,
            has_aerosols: true,
            ..crate::input::atmosphere::Atmosphere::default()
        },
        spectral_grid: resolved.spectral_grid,
        absorbers: absorber_set,
        observation_model: ObservationModel {
            instrument: InstrumentId::Custom(resolved.observation.instrument_name.clone()),
            regime: resolved.observation.regime,
            sampling: resolved.observation.sampling,
            noise_model: resolved.observation.noise_model,
            instrument_line_fwhm_nm: resolved.observation.instrument_line_fwhm_nm,
            builtin_line_shape: resolved.observation.builtin_line_shape,
            high_resolution_step_nm: resolved.observation.high_resolution_step_nm,
            high_resolution_half_span_nm: resolved.observation.high_resolution_half_span_nm,
            adaptive_reference_grid: resolved.observation.adaptive_reference_grid,
            operational_solar_spectrum: solar_spectrum,
            measurement_pipeline: crate::input::instrument::MeasurementPipeline {
                radiance: SpectralChannelControls {
                    explicit: true,
                    response: reference_response.clone(),
                    ..SpectralChannelControls::default()
                },
                irradiance: SpectralChannelControls {
                    explicit: true,
                    response: reference_response,
                    ..SpectralChannelControls::default()
                },
                ..crate::input::instrument::MeasurementPipeline::default()
            },
            ..ObservationModel::default()
        },
        phase_function_truncation_threshold: resolved
            .rtm_controls
            .performance_thresholds
            .phase_function_truncation_threshold,
        ..Scene::default()
    }
}

fn attach_resolved_intervals(scene: &mut Scene, resolved: &ResolvedVendorO2ACase) {
    if resolved.intervals.is_empty() {
        return;
    }
    scene.atmosphere.interval_grid = IntervalGrid {
        semantics: IntervalSemantics::ExplicitPressureBounds,
        fit_interval_index_1based: resolved.fit_interval_index_1based,
        intervals: resolved.intervals.clone(),
    };
}

fn parse_csv_f64(value: Option<&str>) -> Result<f64, Error> {
    let Some(value) = value else {
        return Err(Error::InvalidData);
    };
    Ok(value.trim_matches([' ', '\t']).parse()?)
}
