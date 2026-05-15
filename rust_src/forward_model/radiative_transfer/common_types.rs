use crate::{
    forward_model::{
        jacobian,
        optical_properties::shared::phase_functions::{
            self, PHASE_COEFFICIENT_COUNT, PhaseCoefficients,
        },
    },
    input::{observation_model::ObservationRegime, scene::DerivativeMode},
};

pub const PHASE_COEFFICIENT_COUNT_RT: usize = PHASE_COEFFICIENT_COUNT;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ScatteringMode {
    None = 0,
    Single = 1,
    #[default]
    Multiple = 2,
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
    pub fn validate(self) -> Result<(), Error> {
        if self.fourier_tail_reflectance_epsilon <= 0.0
            || self.threshold_conv_first <= 0.0
            || self.threshold_conv_mult <= 0.0
            || self.threshold_doubl <= 0.0
            || self.threshold_mul <= 0.0
            || self.phase_function_truncation_threshold <= 0.0
            || !self.fourier_tail_reflectance_epsilon.is_finite()
            || !self.threshold_conv_first.is_finite()
            || !self.threshold_conv_mult.is_finite()
            || !self.threshold_doubl.is_finite()
            || !self.threshold_mul.is_finite()
            || !self.phase_function_truncation_threshold.is_finite()
        {
            return Err(Error::UnsupportedRadiativeTransferControls);
        }
        Ok(())
    }

    pub fn resolved_num_orders_max(self, scattering_optical_depth: f64) -> u16 {
        if self.num_orders_max != 0 {
            return self.num_orders_max;
        }
        // DISAMAR-style controls leave this unset for the common path; the
        // optical-depth heuristic keeps weak and thick scenes on the same rule.
        let heuristic = scattering_optical_depth.max(0.0) + 15.0;
        heuristic.clamp(1.0, f64::from(u16::MAX)) as u16
    }

    pub fn capped_fourier_max(self, resolved_fourier_max: usize) -> usize {
        self.fourier_order_cap
            .map(|cap| resolved_fourier_max.min(usize::from(cap)))
            .unwrap_or(resolved_fourier_max)
    }

    pub fn o2a_default() -> Self {
        Self {
            num_orders_max: 0,
            fourier_floor_scalar: 2,
            fourier_order_cap: None,
            fourier_tail_reflectance_epsilon: 3.0e-14,
            threshold_conv_first: 1.5e-7,
            threshold_conv_mult: 1.5e-9,
            threshold_doubl: 1.0e-6,
            threshold_mul: 1.0e-8,
            phase_function_truncation_threshold: 1.0e-8,
        }
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

    pub fn validate(self, execution_mode: ExecutionMode) -> Result<(), Error> {
        if self.n_streams < 4 || !self.n_streams.is_multiple_of(2) {
            return Err(Error::UnsupportedRadiativeTransferControls);
        }
        // LABOS has fixed quadrature support for these Gauss orders.
        // Accepting another even stream count would parse but fail later.
        match self.n_gauss() {
            2 | 3 | 4 | 8 | 10 => {}
            _ => return Err(Error::UnsupportedRadiativeTransferControls),
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

    pub fn default_vendor() -> Self {
        Self::default()
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

pub type Regime = ObservationRegime;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionMode {
    #[default]
    Scalar,
    Polarized,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DispatchRequest {
    pub regime: Regime,
    pub execution_mode: ExecutionMode,
    pub derivative_mode: DerivativeMode,
    pub rtm_controls: RadiativeTransferControls,
}

impl Default for DispatchRequest {
    fn default() -> Self {
        Self {
            regime: Regime::Nadir,
            execution_mode: ExecutionMode::Scalar,
            derivative_mode: DerivativeMode::None,
            rtm_controls: RadiativeTransferControls::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Route {
    pub family: TransportFamily,
    pub regime: Regime,
    pub execution_mode: ExecutionMode,
    pub derivative_mode: DerivativeMode,
    pub derivative_state_mask: jacobian::StateMask,
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

#[derive(Debug, Clone, PartialEq)]
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
    pub optical_depth_jacobian: jacobian::Vector,
    pub scattering_optical_depth_jacobian: jacobian::Vector,
    pub single_scatter_albedo_jacobian: jacobian::Vector,
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

#[derive(Debug, Clone, PartialEq)]
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
    pub fn effective_weight(&self) -> f64 {
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

#[derive(Debug, Default, Clone, PartialEq)]
pub struct RtmQuadratureGrid {
    pub levels: Vec<RtmQuadratureLevel>,
}

impl RtmQuadratureGrid {
    pub fn is_valid_for(&self, layer_count: usize) -> bool {
        self.levels.len() == layer_count + 1
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct PseudoSphericalSample {
    pub altitude_km: f64,
    pub thickness_km: f64,
    pub optical_depth: f64,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct PseudoSphericalGrid {
    pub samples: Vec<PseudoSphericalSample>,
    pub level_sample_starts: Vec<usize>,
    pub level_altitudes_km: Vec<f64>,
}

impl PseudoSphericalGrid {
    pub fn is_valid_for(&self, layer_count: usize) -> bool {
        if self.samples.is_empty()
            || self.level_sample_starts.len() != layer_count + 1
            || (!self.level_altitudes_km.is_empty()
                && self.level_altitudes_km.len() != layer_count + 1)
            || self.level_sample_starts[0] != 0
            || self.level_sample_starts[self.level_sample_starts.len() - 1] != self.samples.len()
        {
            return false;
        }
        // The starts array is an offset table. The final entry must close at
        // samples.len() so each layer can take its sample range directly.
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

#[derive(Debug, Clone, PartialEq)]
pub struct ForwardResult {
    pub family: TransportFamily,
    pub regime: Regime,
    pub execution_mode: ExecutionMode,
    pub derivative_mode: DerivativeMode,
    pub toa_reflectance_factor: f64,
    pub jacobian: Option<jacobian::Vector>,
}

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
