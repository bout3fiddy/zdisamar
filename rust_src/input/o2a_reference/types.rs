use crate::{
    common::errors,
    forward_model::radiative_transfer::common_types::{ExecutionMode, RadiativeTransferControls},
    input::{
        atmosphere::{IntervalPlacement, VerticalInterval},
        geometry,
        instrument::{AdaptiveReferenceGrid, BuiltinLineShapeKind, NoiseModelKind, SamplingMode},
        observation_model::ObservationRegime,
        spectrum::SpectralGrid,
    },
};

#[derive(Debug, Clone, PartialEq)]
pub struct ReferenceSample {
    pub wavelength_nm: f64,
    pub irradiance: f64,
    pub reflectance: f64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExternalAsset {
    pub id: String,
    pub path: String,
    pub format: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputKind {
    SummaryJson,
    GeneratedSpectrumCsv,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutputRequest {
    pub kind: OutputKind,
    pub path: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ValidationPolicy {
    pub strict_unknown_fields: bool,
    pub require_resolved_assets: bool,
    pub require_resolved_stage_references: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanSpec {
    pub model_family: String,
    pub transport_solver: String,
    pub execution_solver_mode: String,
    pub execution_derivative_mode: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanError {
    UnsupportedModelFamily,
    UnsupportedTransportSolver,
    UnsupportedExecutionMode,
    UnsupportedDerivativeMode,
}

impl PlanSpec {
    pub fn validate(&self) -> Result<(), PlanError> {
        if self.model_family != "disamar_standard" {
            return Err(PlanError::UnsupportedModelFamily);
        }
        if self.transport_solver != "dispatcher" {
            return Err(PlanError::UnsupportedTransportSolver);
        }
        self.execution_mode()?;
        self.derivative_mode()?;
        Ok(())
    }

    pub fn execution_mode(&self) -> Result<ExecutionMode, PlanError> {
        match self.execution_solver_mode.as_str() {
            "scalar" => Ok(ExecutionMode::Scalar),
            _ => Err(PlanError::UnsupportedExecutionMode),
        }
    }

    pub fn derivative_mode(&self) -> Result<crate::input::scene::DerivativeMode, PlanError> {
        match self.execution_derivative_mode.as_str() {
            "none" => Ok(crate::input::scene::DerivativeMode::None),
            "semi_analytical" => Ok(crate::input::scene::DerivativeMode::SemiAnalytical),
            _ => Err(PlanError::UnsupportedDerivativeMode),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Metadata {
    pub id: String,
    pub storage: String,
    pub description: String,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GeometrySpec {
    pub model: geometry::Model,
    pub solar_zenith_deg: f64,
    pub viewing_zenith_deg: f64,
    pub relative_azimuth_deg: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AerosolSpec {
    pub optical_depth: f64,
    pub single_scatter_albedo: f64,
    pub asymmetry_factor: f64,
    pub angstrom_exponent: f64,
    pub reference_wavelength_nm: f64,
    pub layer_center_km: f64,
    pub layer_width_km: f64,
    pub placement: IntervalPlacement,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ObservationSpec {
    pub instrument_name: String,
    pub regime: ObservationRegime,
    pub sampling: SamplingMode,
    pub noise_model: NoiseModelKind,
    pub instrument_line_fwhm_nm: f64,
    pub builtin_line_shape: BuiltinLineShapeKind,
    pub high_resolution_step_nm: f64,
    pub high_resolution_half_span_nm: f64,
    pub adaptive_reference_grid: AdaptiveReferenceGrid,
    pub solar_reference_asset_id: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LineGasSpec {
    pub line_list_asset: ExternalAsset,
    pub line_mixing_asset: ExternalAsset,
    pub strong_lines_asset: ExternalAsset,
    pub line_mixing_factor: Option<f64>,
    pub isotopes_sim: Vec<u8>,
    pub threshold_line_sim: Option<f64>,
    pub cutoff_sim_cm1: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CiaSpec {
    pub enabled: bool,
    pub cia_asset: Option<ExternalAsset>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InputsSpec {
    pub atmosphere_profile: ExternalAsset,
    pub vendor_reference_csv: ExternalAsset,
    pub raw_solar_reference: ExternalAsset,
    pub airmass_factor_lut: ExternalAsset,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SolarSpectrumSample {
    pub wavelength_nm: f64,
    pub irradiance: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ResolvedVendorO2ACase {
    pub metadata: Metadata,
    pub plan: PlanSpec,
    pub inputs: InputsSpec,
    pub scene_id: String,
    pub spectral_grid: SpectralGrid,
    pub layer_count: u32,
    pub sublayer_divisions: u8,
    pub surface_pressure_hpa: f64,
    pub fit_interval_index_1based: u32,
    pub intervals: Vec<VerticalInterval>,
    pub surface_albedo: f64,
    pub geometry: GeometrySpec,
    pub aerosol: AerosolSpec,
    pub observation: ObservationSpec,
    pub o2: LineGasSpec,
    pub o2o2: CiaSpec,
    pub rtm_controls: RadiativeTransferControls,
    pub outputs: Vec<OutputRequest>,
    pub validation: ValidationPolicy,
}

impl ResolvedVendorO2ACase {
    pub fn validate(&self) -> Result<(), errors::Error> {
        self.plan
            .validate()
            .map_err(|_| errors::Error::InvalidRequest)?;
        self.spectral_grid.validate()?;
        if self.layer_count == 0
            || self.sublayer_divisions == 0
            || self.surface_pressure_hpa <= 0.0
            || !self.surface_pressure_hpa.is_finite()
        {
            return Err(errors::Error::InvalidRequest);
        }
        if self.fit_interval_index_1based > self.intervals.len() as u32 {
            return Err(errors::Error::InvalidRequest);
        }
        for (index, interval) in self.intervals.iter().copied().enumerate() {
            if interval.index_1based != index as u32 + 1 {
                return Err(errors::Error::InvalidRequest);
            }
            interval.validate()?;
        }
        if !self.surface_albedo.is_finite() || self.surface_albedo < 0.0 {
            return Err(errors::Error::InvalidRequest);
        }
        self.aerosol.placement.validate()?;
        self.observation.adaptive_reference_grid.validate()?;
        self.rtm_controls
            .validate(ExecutionMode::Scalar)
            .map_err(|_| errors::Error::InvalidRequest)?;
        Ok(())
    }
}
