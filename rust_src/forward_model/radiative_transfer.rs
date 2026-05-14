use crate::{
    forward_model::{
        jacobian::{self, StateMask, Vector},
        optical_properties::shared::phase_functions::{
            self, PHASE_COEFFICIENT_COUNT, PhaseCoefficients,
        },
    },
    input::{DerivativeMode, ObservationRegime},
};

pub mod dispatcher;
pub mod labos;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    UnsupportedExecutionMode,
    UnsupportedDerivativeMode,
    UnsupportedTransportSolver,
    UnsupportedObservationRegime,
    UnsupportedRadiativeTransferControls,
    SingularDoublingDenominator,
    MissingExplicitRtmQuadrature,
    OutOfMemory,
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ScatteringMode {
    None,
    Single,
    #[default]
    Multiple,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RadiativeTransferPerformanceThresholds {
    pub num_orders_max: u16,
    pub fourier_floor_scalar: u16,
    pub fourier_order_cap: Option<u16>,
    pub fourier_tail_reflectance_epsilon: f64,
    pub threshold_conv_first: f64,
    pub threshold_conv_mult: f64,
    pub threshold_doubl: f64,
    pub threshold_mul: f64,
    pub phase_function_truncation_threshold: f64,
}

impl Default for RadiativeTransferPerformanceThresholds {
    fn default() -> Self {
        Self {
            num_orders_max: 0,
            fourier_floor_scalar: 2,
            fourier_order_cap: None,
            fourier_tail_reflectance_epsilon: 3.0e-14,
            threshold_conv_first: 1.0e-6,
            threshold_conv_mult: 1.0e-4,
            threshold_doubl: 0.1,
            threshold_mul: 1.0e-12,
            phase_function_truncation_threshold: phase_functions::VENDOR_HG_TRUNCATION_THRESHOLD,
        }
    }
}

impl RadiativeTransferPerformanceThresholds {
    pub const O2A_DEFAULT: Self = Self {
        num_orders_max: 0,
        fourier_floor_scalar: 2,
        fourier_order_cap: None,
        fourier_tail_reflectance_epsilon: 3.0e-14,
        threshold_conv_first: 1.5e-7,
        threshold_conv_mult: 1.5e-9,
        threshold_doubl: 1.0e-6,
        threshold_mul: 1.0e-8,
        phase_function_truncation_threshold: 1.0e-8,
    };

    pub fn validate(self) -> Result<()> {
        let values = [
            self.fourier_tail_reflectance_epsilon,
            self.threshold_conv_first,
            self.threshold_conv_mult,
            self.threshold_doubl,
            self.threshold_mul,
            self.phase_function_truncation_threshold,
        ];
        if values
            .iter()
            .any(|value| *value <= 0.0 || !value.is_finite())
        {
            return Err(Error::UnsupportedRadiativeTransferControls);
        }
        Ok(())
    }

    pub fn resolved_num_orders_max(self, scattering_optical_depth: f64) -> u16 {
        if self.num_orders_max != 0 {
            return self.num_orders_max;
        }
        let heuristic = scattering_optical_depth.max(0.0) + 15.0;
        heuristic.clamp(1.0, f64::from(u16::MAX)) as u16
    }

    pub fn capped_fourier_max(self, resolved_fourier_max: usize) -> usize {
        self.fourier_order_cap
            .map(|cap| resolved_fourier_max.min(usize::from(cap)))
            .unwrap_or(resolved_fourier_max)
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RadiativeTransferControls {
    pub scattering: ScatteringMode,
    pub n_streams: u16,
    pub use_adding: bool,
    pub performance_thresholds: RadiativeTransferPerformanceThresholds,
    pub use_spherical_correction: bool,
    pub integrate_source_function: bool,
    pub renorm_phase_function: bool,
    pub stokes_dimension: u8,
}

impl Default for RadiativeTransferControls {
    fn default() -> Self {
        Self {
            scattering: ScatteringMode::Multiple,
            n_streams: 16,
            use_adding: false,
            performance_thresholds: RadiativeTransferPerformanceThresholds::default(),
            use_spherical_correction: false,
            integrate_source_function: true,
            renorm_phase_function: true,
            stokes_dimension: 1,
        }
    }
}

impl RadiativeTransferControls {
    pub fn n_gauss(self) -> u16 {
        self.n_streams / 2
    }

    pub fn validate(self, execution_mode: ExecutionMode) -> Result<()> {
        if self.n_streams < 4 || !self.n_streams.is_multiple_of(2) {
            return Err(Error::UnsupportedRadiativeTransferControls);
        }
        if !matches!(self.n_gauss(), 2 | 3 | 4 | 8 | 10) {
            return Err(Error::UnsupportedRadiativeTransferControls);
        }
        if self.use_adding && self.scattering == ScatteringMode::Single {
            return Err(Error::UnsupportedRadiativeTransferControls);
        }
        if self.stokes_dimension != 1 && execution_mode == ExecutionMode::Scalar {
            return Err(Error::UnsupportedRadiativeTransferControls);
        }
        self.performance_thresholds.validate()
    }

    pub fn resolved_num_orders_max(self, scattering_optical_depth: f64) -> u16 {
        self.performance_thresholds
            .resolved_num_orders_max(scattering_optical_depth)
    }

    pub fn n_directions(self) -> u16 {
        self.n_gauss() + 2
    }

    pub fn supermatrix_size(self) -> u32 {
        u32::from(self.n_directions()) * u32::from(self.stokes_dimension)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportFamily {
    Labos,
}

impl TransportFamily {
    pub fn classification(self) -> ImplementationClass {
        match self {
            Self::Labos => ImplementationClass::Baseline,
        }
    }

    pub fn provenance_label(self) -> &'static str {
        match self {
            Self::Labos => "baseline_labos",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImplementationClass {
    Baseline,
    Surrogate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DerivativeSemantics {
    None,
    Proxy,
    Analytical,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ExecutionMode {
    #[default]
    Scalar,
    Polarized,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DispatchRequest {
    pub regime: ObservationRegime,
    pub execution_mode: ExecutionMode,
    pub derivative_mode: DerivativeMode,
    pub rtm_controls: RadiativeTransferControls,
}

impl Default for DispatchRequest {
    fn default() -> Self {
        Self {
            regime: ObservationRegime::Nadir,
            execution_mode: ExecutionMode::Scalar,
            derivative_mode: DerivativeMode::None,
            rtm_controls: RadiativeTransferControls::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Route {
    pub family: TransportFamily,
    pub regime: ObservationRegime,
    pub execution_mode: ExecutionMode,
    pub derivative_mode: DerivativeMode,
    pub derivative_state_mask: StateMask,
    pub rtm_controls: RadiativeTransferControls,
}

impl Route {
    pub fn derivative_semantics(self) -> DerivativeSemantics {
        if self.derivative_mode == DerivativeMode::None {
            return DerivativeSemantics::None;
        }
        match self.family.classification() {
            ImplementationClass::Surrogate => DerivativeSemantics::Proxy,
            ImplementationClass::Baseline => DerivativeSemantics::Analytical,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LayerInput {
    pub gas_absorption_optical_depth: f64,
    pub gas_scattering_optical_depth: f64,
    pub cia_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub aerosol_scattering_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub cloud_scattering_optical_depth: f64,
    pub optical_depth: f64,
    pub scattering_optical_depth: f64,
    pub single_scatter_albedo: f64,
    pub optical_depth_jacobian: Vector,
    pub scattering_optical_depth_jacobian: Vector,
    pub single_scatter_albedo_jacobian: Vector,
    pub solar_mu: f64,
    pub view_mu: f64,
    pub phase_coefficients: PhaseCoefficients,
}

impl Default for LayerInput {
    fn default() -> Self {
        Self {
            gas_absorption_optical_depth: 0.0,
            gas_scattering_optical_depth: 0.0,
            cia_optical_depth: 0.0,
            aerosol_optical_depth: 0.0,
            aerosol_scattering_optical_depth: 0.0,
            cloud_optical_depth: 0.0,
            cloud_scattering_optical_depth: 0.0,
            optical_depth: 0.0,
            scattering_optical_depth: 0.0,
            single_scatter_albedo: 0.0,
            optical_depth_jacobian: jacobian::zero(),
            scattering_optical_depth_jacobian: jacobian::zero(),
            single_scatter_albedo_jacobian: jacobian::zero(),
            solar_mu: 1.0,
            view_mu: 1.0,
            phase_coefficients: phase_functions::zero_phase_coefficients(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SourceInterfaceInput {
    pub source_weight: f64,
    pub rtm_weight: f64,
    pub gas_ksca: f64,
    pub particle_ksca_above: f64,
    pub particle_ksca_below: f64,
    pub ksca_above: f64,
    pub ksca_below: f64,
    pub gas_phase_coefficients: PhaseCoefficients,
    pub phase_coefficients_above: PhaseCoefficients,
    pub phase_coefficients_below: PhaseCoefficients,
}

impl Default for SourceInterfaceInput {
    fn default() -> Self {
        Self {
            source_weight: 0.0,
            rtm_weight: 0.0,
            gas_ksca: 0.0,
            particle_ksca_above: 0.0,
            particle_ksca_below: 0.0,
            ksca_above: 0.0,
            ksca_below: 0.0,
            gas_phase_coefficients: phase_functions::gas_phase_coefficients(),
            phase_coefficients_above: phase_functions::zero_phase_coefficients(),
            phase_coefficients_below: phase_functions::zero_phase_coefficients(),
        }
    }
}

impl SourceInterfaceInput {
    pub fn effective_weight(self) -> f64 {
        if self.rtm_weight > 0.0 && self.ksca_above > 0.0 {
            return self.rtm_weight * self.ksca_above;
        }
        self.source_weight
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RtmQuadratureLevel {
    pub altitude_km: f64,
    pub weight: f64,
    pub ksca: f64,
    pub phase_coefficients: PhaseCoefficients,
    pub aerosol_ksca_phase_above_per_km: PhaseCoefficients,
    pub aerosol_ksca_phase_below_per_km: PhaseCoefficients,
    pub ksca_phase_coefficient_jacobian: [[f64; PHASE_COEFFICIENT_COUNT]; jacobian::STATE_COUNT],
}

impl Default for RtmQuadratureLevel {
    fn default() -> Self {
        Self {
            altitude_km: 0.0,
            weight: 0.0,
            ksca: 0.0,
            phase_coefficients: phase_functions::zero_phase_coefficients(),
            aerosol_ksca_phase_above_per_km: phase_functions::zero_phase_coefficients(),
            aerosol_ksca_phase_below_per_km: phase_functions::zero_phase_coefficients(),
            ksca_phase_coefficient_jacobian: [[0.0; PHASE_COEFFICIENT_COUNT];
                jacobian::STATE_COUNT],
        }
    }
}

impl RtmQuadratureLevel {
    pub fn weighted_scattering(&self) -> f64 {
        self.weight * self.ksca
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct RtmQuadratureGrid {
    pub levels: Vec<RtmQuadratureLevel>,
}

impl RtmQuadratureGrid {
    pub fn is_valid_for(&self, layer_count: usize) -> bool {
        self.levels.len() == layer_count + 1
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct PseudoSphericalSample {
    pub altitude_km: f64,
    pub thickness_km: f64,
    pub optical_depth: f64,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct PseudoSphericalGrid {
    pub samples: Vec<PseudoSphericalSample>,
    pub level_sample_starts: Vec<usize>,
    pub level_altitudes_km: Vec<f64>,
}

impl PseudoSphericalGrid {
    pub fn is_valid_for(&self, layer_count: usize) -> bool {
        if self.samples.is_empty() {
            return false;
        }
        if self.level_sample_starts.len() != layer_count + 1 {
            return false;
        }
        if !self.level_altitudes_km.is_empty() && self.level_altitudes_km.len() != layer_count + 1 {
            return false;
        }
        if self.level_sample_starts[0] != 0 {
            return false;
        }
        if self.level_sample_starts[self.level_sample_starts.len() - 1] != self.samples.len() {
            return false;
        }
        for index in 1..self.level_sample_starts.len() {
            if self.level_sample_starts[index] < self.level_sample_starts[index - 1]
                || self.level_sample_starts[index] > self.samples.len()
            {
                return false;
            }
        }
        true
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ForwardInput {
    pub wavelength_nm: f64,
    pub spectral_weight: f64,
    pub air_mass_factor: f64,
    pub mu0: f64,
    pub muv: f64,
    pub surface_albedo: f64,
    pub gas_absorption_optical_depth: f64,
    pub gas_scattering_optical_depth: f64,
    pub cia_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub aerosol_scattering_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub cloud_scattering_optical_depth: f64,
    pub optical_depth: f64,
    pub single_scatter_albedo: f64,
    pub relative_azimuth_rad: f64,
    pub layers: Vec<LayerInput>,
    pub source_interfaces: Vec<SourceInterfaceInput>,
    pub rtm_quadrature: RtmQuadratureGrid,
    pub pseudo_spherical_grid: PseudoSphericalGrid,
    pub rtm_controls: RadiativeTransferControls,
}

impl Default for ForwardInput {
    fn default() -> Self {
        Self {
            wavelength_nm: 440.0,
            spectral_weight: 1.0,
            air_mass_factor: 1.0,
            mu0: 1.0,
            muv: 1.0,
            surface_albedo: 0.05,
            gas_absorption_optical_depth: 0.0,
            gas_scattering_optical_depth: 0.0,
            cia_optical_depth: 0.0,
            aerosol_optical_depth: 0.0,
            aerosol_scattering_optical_depth: 0.0,
            cloud_optical_depth: 0.0,
            cloud_scattering_optical_depth: 0.0,
            optical_depth: 0.5,
            single_scatter_albedo: 0.95,
            relative_azimuth_rad: 0.0,
            layers: Vec::new(),
            source_interfaces: Vec::new(),
            rtm_quadrature: RtmQuadratureGrid::default(),
            pseudo_spherical_grid: PseudoSphericalGrid::default(),
            rtm_controls: RadiativeTransferControls::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ForwardResult {
    pub family: TransportFamily,
    pub regime: ObservationRegime,
    pub execution_mode: ExecutionMode,
    pub derivative_mode: DerivativeMode,
    pub toa_reflectance_factor: f64,
    pub jacobian: Option<Vector>,
}

pub fn prepare_route(request: DispatchRequest) -> Result<Route> {
    if request.rtm_controls.use_adding {
        return Err(Error::UnsupportedTransportSolver);
    }
    if request.regime != ObservationRegime::Nadir {
        return Err(Error::UnsupportedObservationRegime);
    }
    if request.execution_mode != ExecutionMode::Scalar {
        return Err(Error::UnsupportedExecutionMode);
    }
    if request.derivative_mode == DerivativeMode::Numerical {
        return Err(Error::UnsupportedDerivativeMode);
    }
    request.rtm_controls.validate(request.execution_mode)?;
    Ok(Route {
        family: TransportFamily::Labos,
        regime: request.regime,
        execution_mode: request.execution_mode,
        derivative_mode: request.derivative_mode,
        derivative_state_mask: jacobian::ALL_STATES_MASK,
        rtm_controls: request.rtm_controls,
    })
}

pub fn source_interface_from_layers(layers: &[LayerInput], ilevel: usize) -> SourceInterfaceInput {
    if layers.is_empty() {
        return SourceInterfaceInput::default();
    }
    let above_index = ilevel.min(layers.len() - 1);
    let below_index = if ilevel > 0 { ilevel - 1 } else { above_index };
    let source_weight = if ilevel < layers.len() {
        layers[ilevel].scattering_optical_depth.max(0.0)
    } else {
        0.5 * layers[above_index].scattering_optical_depth.max(0.0)
    };

    SourceInterfaceInput {
        source_weight,
        particle_ksca_above: layers[above_index].scattering_optical_depth.max(0.0),
        particle_ksca_below: if ilevel > 0 {
            layers[below_index].scattering_optical_depth.max(0.0)
        } else {
            0.0
        },
        ksca_above: layers[above_index].scattering_optical_depth.max(0.0),
        ksca_below: if ilevel > 0 {
            layers[below_index].scattering_optical_depth.max(0.0)
        } else {
            0.0
        },
        phase_coefficients_above: layers[above_index].phase_coefficients,
        phase_coefficients_below: if ilevel > 0 {
            layers[below_index].phase_coefficients
        } else {
            phase_functions::zero_phase_coefficients()
        },
        ..SourceInterfaceInput::default()
    }
}

pub fn fill_source_interfaces_from_layers(
    layers: &[LayerInput],
    source_interfaces: &mut [SourceInterfaceInput],
) {
    if layers.is_empty() || source_interfaces.len() != layers.len() + 1 {
        return;
    }
    for (ilevel, source_interface) in source_interfaces.iter_mut().enumerate() {
        *source_interface = source_interface_from_layers(layers, ilevel);
    }
}
