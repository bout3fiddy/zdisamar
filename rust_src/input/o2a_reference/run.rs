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
        reference::airmass_phase::{AirmassFactorLut, AirmassFactorPoint},
        reference::spectroscopy::line_list_ops,
        reference_data::{
            ClimatologyPoint, ClimatologyProfile, CollisionInducedAbsorptionPoint,
            CollisionInducedAbsorptionTable, RelaxationMatrix, SpectroscopyLine,
            SpectroscopyLineList, SpectroscopyStrongLine,
        },
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

pub fn load_cia_table(asset: &ExternalAsset) -> Result<CollisionInducedAbsorptionTable, Error> {
    if asset.format != "bira_cia" {
        return Err(Error::InvalidData);
    }

    let bytes = fs::read_to_string(&asset.path)?;
    let mut numeric_header_index = 0;
    let mut scale_factor = 0.0;
    let mut expected_data_rows = None;
    let mut points = Vec::new();

    for line in bytes.lines() {
        let stripped = line.trim_matches(['\r', ' ', '\t']);
        if stripped.is_empty() || stripped.starts_with('#') {
            continue;
        }

        let mut tokens = stripped.split_whitespace();
        let Some(first_token) = tokens.next() else {
            continue;
        };
        if first_token.starts_with('!') {
            continue;
        }

        if numeric_header_index < 3 {
            let numeric_value = first_token.parse::<f64>()?;
            match numeric_header_index {
                0 => scale_factor = numeric_value,
                1 => {}
                2 => expected_data_rows = Some(numeric_value as usize),
                _ => unreachable!(),
            }
            numeric_header_index += 1;
            continue;
        }

        points.push(CollisionInducedAbsorptionPoint {
            wavelength_nm: first_token.parse()?,
            a0: parse_token_f64(tokens.next())?,
            a1: parse_token_f64(tokens.next())?,
            a2: parse_token_f64(tokens.next())?,
        });
    }

    if numeric_header_index < 3 || points.is_empty() {
        return Err(Error::InvalidData);
    }
    if expected_data_rows.is_some_and(|expected| points.len() < expected) {
        return Err(Error::InvalidData);
    }

    Ok(CollisionInducedAbsorptionTable {
        points,
        scale_factor_cm5_per_molecule2: scale_factor,
    })
}

pub fn load_airmass_factor_lut(asset: &ExternalAsset) -> Result<AirmassFactorLut, Error> {
    if asset.format != "csv" {
        return Err(Error::InvalidData);
    }

    let bytes = fs::read_to_string(&asset.path)?;
    let mut points = Vec::new();

    for line in bytes.lines().skip(1) {
        let trimmed = line.trim_matches(['\r', ' ', '\t']);
        if trimmed.is_empty() {
            continue;
        }

        let mut columns = trimmed.split(',');
        points.push(AirmassFactorPoint {
            solar_zenith_deg: parse_csv_f64(columns.next())?,
            view_zenith_deg: parse_csv_f64(columns.next())?,
            relative_azimuth_deg: parse_csv_f64(columns.next())?,
            airmass_factor: parse_csv_f64(columns.next())?,
        });
    }

    if points.is_empty() {
        return Err(Error::InvalidData);
    }

    Ok(AirmassFactorLut { points })
}

pub fn load_resolved_vendor_o2a_line_list(
    spec: &LineGasSpec,
) -> Result<SpectroscopyLineList, Error> {
    let mut line_list = load_spectroscopy_line_list(&spec.line_list_asset)?;
    let strong_lines = load_spectroscopy_strong_lines(&spec.strong_lines_asset)?;
    let relaxation_matrix = load_spectroscopy_relaxation_matrix(&spec.line_mixing_asset)?;
    attach_strong_line_sidecars(&mut line_list, strong_lines, relaxation_matrix)?;
    Ok(line_list)
}

pub fn load_spectroscopy_line_list(asset: &ExternalAsset) -> Result<SpectroscopyLineList, Error> {
    if asset.format != "hitran_par_o2a" && asset.format != "hitran_par" {
        return Err(Error::InvalidData);
    }
    let has_vendor_o2a_fields = asset.format == "hitran_par_o2a";
    let bytes = fs::read_to_string(&asset.path)?;
    let mut lines = Vec::new();

    for raw_line in bytes.lines() {
        let line = raw_line.trim_end_matches('\r');
        let stripped = line.trim_matches([' ', '\t']);
        if stripped.is_empty() || stripped.starts_with('#') || stripped.starts_with('!') {
            continue;
        }
        if line.len() < 67 {
            return Err(Error::InvalidData);
        }

        lines.push(parse_hitran_160_line(line, has_vendor_o2a_fields)?);
    }
    if lines.is_empty() {
        return Err(Error::InvalidData);
    }

    Ok(SpectroscopyLineList {
        lines,
        ..SpectroscopyLineList::default()
    })
}

pub fn load_spectroscopy_strong_lines(
    asset: &ExternalAsset,
) -> Result<Vec<SpectroscopyStrongLine>, Error> {
    if asset.format != "lisa_sdf" {
        return Err(Error::InvalidData);
    }

    let bytes = fs::read_to_string(&asset.path)?;
    let mut lines = Vec::new();
    for raw_line in bytes.lines() {
        let line = raw_line.trim_end_matches('\r');
        let stripped = line.trim_matches([' ', '\t']);
        if stripped.is_empty() || stripped.starts_with('#') || stripped.starts_with('!') {
            continue;
        }
        if line.len() < 87 {
            return Err(Error::InvalidData);
        }
        lines.push(parse_lisa_sdf_line(line)?);
    }
    if lines.is_empty() {
        return Err(Error::InvalidData);
    }
    Ok(lines)
}

pub fn load_spectroscopy_relaxation_matrix(
    asset: &ExternalAsset,
) -> Result<RelaxationMatrix, Error> {
    if asset.format != "lisa_rmf" {
        return Err(Error::InvalidData);
    }

    let bytes = fs::read_to_string(&asset.path)?;
    let mut wt0 = Vec::new();
    let mut bw = Vec::new();
    for raw_line in bytes.lines() {
        let line = raw_line.trim_end_matches('\r');
        let stripped = line.trim_matches([' ', '\t']);
        if stripped.is_empty() || stripped.starts_with('#') || stripped.starts_with('!') {
            continue;
        }
        if line.len() < 31 {
            return Err(Error::InvalidData);
        }
        wt0.push(parse_fixed_f64(line, 0, 15)?);
        bw.push(parse_fixed_f64(line, 15, 31)?);
    }
    if wt0.is_empty() || wt0.len() != bw.len() {
        return Err(Error::InvalidData);
    }

    let line_count = (wt0.len() as f64).sqrt().round() as usize;
    if line_count * line_count != wt0.len() {
        return Err(Error::InvalidData);
    }

    Ok(RelaxationMatrix {
        line_count,
        wt0,
        bw,
    })
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

fn parse_token_f64(value: Option<&str>) -> Result<f64, Error> {
    let Some(value) = value else {
        return Err(Error::InvalidData);
    };
    Ok(value.parse()?)
}

fn attach_strong_line_sidecars(
    line_list: &mut SpectroscopyLineList,
    strong_lines: Vec<SpectroscopyStrongLine>,
    relaxation_matrix: RelaxationMatrix,
) -> Result<(), Error> {
    line_list.strong_lines = Some(strong_lines);
    line_list.relaxation_matrix = Some(relaxation_matrix);
    line_list.strong_line_match_by_line = None;
    line_list.vendor_strong_line_partition =
        line_list_ops::detect_vendor_strong_line_partition(line_list);
    line_list_ops::validate_strong_line_partition(line_list)?;
    Ok(())
}

fn parse_hitran_160_line(
    line: &str,
    has_vendor_o2a_fields: bool,
) -> Result<SpectroscopyLine, Error> {
    let gas_index = parse_fixed_u16(line, 0, 2)?;
    let isotope_number = parse_fixed_u16(line, 2, 3)? as u8;
    let center_wavenumber_cm1 = parse_fixed_f64(line, 3, 15)?;
    let line_strength = parse_fixed_f64(line, 15, 25)?;
    let air_half_width_cm1 = parse_fixed_f64(line, 35, 40)?;
    let lower_state_energy_cm1 = parse_fixed_f64(line, 45, 55)?;
    let temperature_exponent = parse_fixed_f64(line, 55, 59)?;
    let pressure_shift_cm1 = parse_fixed_f64(line, 59, 67)?;
    let has_inline_vendor_fields = has_vendor_o2a_fields && line.len() >= 85;

    let center_wavelength_nm = wavenumber_to_wavelength_nm(center_wavenumber_cm1);
    let air_half_width_nm = spectral_width_cm1_to_nm(air_half_width_cm1, center_wavenumber_cm1);
    let pressure_shift_nm = -spectral_width_cm1_to_nm(pressure_shift_cm1, center_wavenumber_cm1);
    let line_mixing_coefficient =
        derive_line_mixing_coefficient(air_half_width_cm1, pressure_shift_cm1);

    let inline_branch_ic1 = if has_inline_vendor_fields {
        parse_optional_fixed_u16(line, 67, 70)?
    } else {
        None
    };
    let inline_branch_ic2 = if has_inline_vendor_fields {
        parse_optional_fixed_u16(line, 70, 73)?
    } else {
        None
    };
    let inline_rotational_nf = if has_inline_vendor_fields {
        parse_optional_fixed_u16(line, 83, 85)?
    } else {
        None
    };
    let fallback_vendor_metadata = if has_vendor_o2a_fields
        && inline_branch_ic1.is_none()
        && inline_branch_ic2.is_none()
        && inline_rotational_nf.is_none()
    {
        fallback_vendor_o2a_branch_metadata(line, center_wavenumber_cm1)?
    } else {
        None
    };

    let branch_ic1 =
        inline_branch_ic1.or_else(|| fallback_vendor_metadata.map(|metadata| metadata.branch_ic1));
    let branch_ic2 =
        inline_branch_ic2.or_else(|| fallback_vendor_metadata.map(|metadata| metadata.branch_ic2));
    let rotational_nf = inline_rotational_nf
        .or_else(|| fallback_vendor_metadata.map(|metadata| metadata.rotational_nf));

    Ok(SpectroscopyLine {
        gas_index,
        isotope_number,
        abundance_fraction: derive_isotopic_abundance_fraction(gas_index, isotope_number as u16),
        vendor_filter_metadata_from_source: inline_branch_ic1.is_some()
            && inline_branch_ic2.is_some()
            && inline_rotational_nf.is_some(),
        center_wavelength_nm,
        center_wavenumber_cm1: Some(center_wavenumber_cm1),
        line_strength_cm2_per_molecule: line_strength,
        air_half_width_nm,
        air_half_width_cm1: Some(air_half_width_cm1),
        temperature_exponent,
        lower_state_energy_cm1,
        pressure_shift_nm,
        pressure_shift_cm1: Some(pressure_shift_cm1),
        line_mixing_coefficient,
        branch_ic1: optional_u16_to_u8(branch_ic1)?,
        branch_ic2: optional_u16_to_u8(branch_ic2)?,
        rotational_nf: optional_u16_to_u8(rotational_nf)?,
    })
}

fn parse_lisa_sdf_line(line: &str) -> Result<SpectroscopyStrongLine, Error> {
    let center_wavenumber_cm1 = parse_fixed_f64(line, 0, 12)?;
    let population_t0 = parse_fixed_f64(line, 14, 23)?;
    let dipole_ratio = parse_fixed_f64(line, 25, 34)?;
    let dipole_t0 = parse_fixed_f64(line, 35, 44)?;
    let lower_state_energy_cm1 = parse_fixed_f64(line, 46, 56)?;
    let temperature_exponent = parse_fixed_f64(line, 65, 69)?;
    let pressure_shift_cm1 = parse_fixed_f64(line, 71, 79)?;
    let branch_token = fixed_slice(line, 83, 84)?.trim_matches([' ', '\t']);
    let nf_token = fixed_slice(line, 84, 87)?.trim_matches([' ', '\t']);
    let rotational_index_m1 = rotational_index_from_lisa_branch(branch_token, nf_token)?;

    // DISAMAR ignores the tabulated HWT0 field and rebuilds the reference
    // half-width from the LISA branch metadata before temperature scaling.
    let _tabulated_air_half_width_cm1 = parse_fixed_f64(line, 58, 63)?;
    let air_half_width_cm1 = vendor_lisa_reference_half_width_cm1(branch_token, nf_token)?;

    let center_wavelength_nm = wavenumber_to_wavelength_nm(center_wavenumber_cm1);
    let air_half_width_nm = spectral_width_cm1_to_nm(air_half_width_cm1, center_wavenumber_cm1);
    let pressure_shift_nm = -spectral_width_cm1_to_nm(pressure_shift_cm1, center_wavenumber_cm1);

    Ok(SpectroscopyStrongLine {
        center_wavenumber_cm1,
        center_wavelength_nm,
        population_t0,
        dipole_ratio,
        dipole_t0,
        lower_state_energy_cm1,
        air_half_width_cm1,
        air_half_width_nm,
        temperature_exponent,
        pressure_shift_cm1,
        pressure_shift_nm,
        rotational_index_m1,
    })
}

fn fixed_slice(line: &str, start: usize, end: usize) -> Result<&str, Error> {
    line.get(start..end).ok_or(Error::InvalidData)
}

fn parse_fixed_f64(line: &str, start: usize, end: usize) -> Result<f64, Error> {
    Ok(fixed_slice(line, start, end)?
        .trim_matches([' ', '\t'])
        .parse()?)
}

fn parse_fixed_u16(line: &str, start: usize, end: usize) -> Result<u16, Error> {
    fixed_slice(line, start, end)?
        .trim_matches([' ', '\t'])
        .parse()
        .map_err(|_| Error::InvalidData)
}

fn parse_optional_fixed_u16(line: &str, start: usize, end: usize) -> Result<Option<u16>, Error> {
    let trimmed = fixed_slice(line, start, end)?.trim_matches([' ', '\t']);
    if trimmed.is_empty() {
        return Ok(None);
    }
    trimmed.parse().map(Some).map_err(|_| Error::InvalidData)
}

fn optional_u16_to_u8(value: Option<u16>) -> Result<Option<u8>, Error> {
    value
        .map(|value| u8::try_from(value).map_err(|_| Error::InvalidData))
        .transpose()
}

fn wavenumber_to_wavelength_nm(wavenumber_cm1: f64) -> f64 {
    1.0e7 / wavenumber_cm1.max(1.0)
}

fn spectral_width_cm1_to_nm(width_cm1: f64, center_wavenumber_cm1: f64) -> f64 {
    let safe_center = center_wavenumber_cm1.max(1.0);
    width_cm1 * 1.0e7 / (safe_center * safe_center)
}

fn derive_line_mixing_coefficient(air_half_width_cm1: f64, pressure_shift_cm1: f64) -> f64 {
    (pressure_shift_cm1.abs() / air_half_width_cm1.abs().max(1.0e-6)).clamp(0.0, 0.15)
}

fn derive_isotopic_abundance_fraction(gas_index: u16, isotope_number: u16) -> f64 {
    match gas_index {
        1 => match isotope_number {
            1 => 0.997317,
            2 => 1.99983e-3,
            3 => 3.71884e-4,
            4 => 3.10693e-4,
            5 => 6.23003e-7,
            6 => 1.15853e-7,
            _ => 1.0e-8,
        },
        2 => match isotope_number {
            1 => 0.984204,
            2 => 1.10574e-2,
            3 => 3.94707e-3,
            4 => 7.33989e-4,
            5 => 4.43446e-5,
            6 => 8.24623e-6,
            _ => 1.0e-8,
        },
        5 => match isotope_number {
            1 => 0.986544,
            2 => 1.10836e-2,
            3 => 1.97822e-3,
            4 => 3.67867e-4,
            5 => 2.22250e-5,
            6 => 4.13292e-6,
            _ => 1.0e-8,
        },
        6 => match isotope_number {
            1 => 0.988274,
            2 => 1.11031e-2,
            3 => 6.15751e-4,
            _ => 1.0e-8,
        },
        7 => match isotope_number {
            1 => 0.995262,
            2 => 3.99141e-3,
            3 => 7.42235e-4,
            _ => 1.0e-8,
        },
        10 => match isotope_number {
            1 => 0.991,
            2 => 0.006,
            3 => 0.003,
            _ => 1.0e-8,
        },
        11 => match isotope_number {
            1 => 0.995872,
            2 => 3.66129e-3,
            _ => 1.0e-8,
        },
        _ => 1.0,
    }
}

fn rotational_index_from_lisa_branch(branch_token: &str, nf_token: &str) -> Result<i32, Error> {
    if branch_token.len() != 1 {
        return Err(Error::InvalidData);
    }
    let nf = nf_token.parse::<i32>().map_err(|_| Error::InvalidData)?;
    match branch_token.as_bytes()[0] {
        b'P' => Ok(-nf),
        b'R' => Ok(nf + 1),
        _ => Err(Error::InvalidData),
    }
}

fn vendor_lisa_reference_half_width_cm1(branch_token: &str, nf_token: &str) -> Result<f64, Error> {
    if branch_token.len() != 1 {
        return Err(Error::InvalidData);
    }
    let raw_nf = nf_token.parse::<i32>().map_err(|_| Error::InvalidData)?;
    let vendor_nf = match branch_token.as_bytes()[0] {
        b'P' => raw_nf - 1,
        b'R' => raw_nf + 1,
        _ => return Err(Error::InvalidData),
    };
    let vendor_nf = f64::from(vendor_nf);
    let sbhw = 0.02204
        + 0.03749
            / (1.0 + 0.05428 * vendor_nf - 1.19e-3 * vendor_nf * vendor_nf
                + 2.073e-6 * vendor_nf.powi(4));
    Ok(1.023 * 1.012 * sbhw / (1.0 + ((vendor_nf - 5.0) / 55.0).powi(2)).sqrt())
}

#[derive(Debug, Clone, Copy)]
struct VendorO2ABranchMetadata {
    branch_ic1: u16,
    branch_ic2: u16,
    rotational_nf: u16,
}

fn fallback_vendor_o2a_branch_metadata(
    line: &str,
    center_wavenumber_cm1: f64,
) -> Result<Option<VendorO2ABranchMetadata>, Error> {
    if !(12800.0..=13250.0).contains(&center_wavenumber_cm1) {
        return Ok(None);
    }

    let mut tokens = line.split_whitespace();
    while let Some(branch_token) = tokens.next() {
        if branch_token.len() != 1 || branch_token.as_bytes()[0] != b'P' {
            continue;
        }
        let Some(upper_token) = tokens.next() else {
            return Ok(None);
        };
        let Some(lower_token) = tokens.next() else {
            return Ok(None);
        };
        if upper_token.len() < 2 {
            return Ok(None);
        }

        let branch_kind = upper_token.as_bytes()[upper_token.len() - 1];
        if branch_kind != b'P' && branch_kind != b'Q' {
            return Ok(None);
        }
        let rotational_prefix = &upper_token[..upper_token.len() - 1];
        if rotational_prefix.is_empty() {
            return Ok(None);
        }

        let upper_nf = rotational_prefix
            .parse::<u16>()
            .map_err(|_| Error::InvalidData)?;
        let lower_nf = lower_token.parse::<u16>().map_err(|_| Error::InvalidData)?;
        if upper_nf == 0 || upper_nf > 35 || upper_nf % 2 == 0 {
            return Ok(None);
        }
        if !(lower_nf == upper_nf || lower_nf + 1 == upper_nf) {
            return Ok(None);
        }
        return Ok(Some(VendorO2ABranchMetadata {
            branch_ic1: 5,
            branch_ic2: 1,
            rotational_nf: upper_nf,
        }));
    }
    Ok(None)
}
