const std = @import("std");
const SceneModel = @import("../../input/Scene.zig");
const phase_functions = @import("../optical_properties/shared/phase_functions.zig");

pub const phase_coefficient_count = phase_functions.phase_coefficient_count;

// Atmospheric scattering treatment.
pub const ScatteringMode = enum(u2) {
    none = 0,
    single = 1,
    multiple = 2,
};

// Resolved radiative transfer controls compiled from canonical configuration.
pub const RadiativeTransferControls = struct {
    scattering: ScatteringMode = .multiple,
    n_streams: u16 = 16,
    use_adding: bool = false,
    num_orders_max: u16 = 0,
    fourier_floor_scalar: u16 = 2,
    threshold_conv_first: f64 = 1.0e-6,
    threshold_conv_mult: f64 = 1.0e-4,
    threshold_doubl: f64 = 0.1,
    threshold_mul: f64 = 1.0e-12,
    use_spherical_correction: bool = false,
    integrate_source_function: bool = true,
    renorm_phase_function: bool = true,
    stokes_dimension: u8 = 1,

    pub fn nGauss(self: RadiativeTransferControls) u16 {
        return self.n_streams / 2;
    }

    pub fn validate(self: RadiativeTransferControls, execution_mode: ExecutionMode) PrepareError!void {
        if (self.n_streams < 4 or (self.n_streams % 2) != 0) {
            return error.UnsupportedRadiativeTransferControls;
        }
        switch (self.nGauss()) {
            2, 3, 4, 8, 10 => {},
            else => return error.UnsupportedRadiativeTransferControls,
        }
        if (self.use_adding and self.scattering == .single) {
            return error.UnsupportedRadiativeTransferControls;
        }
        if (self.stokes_dimension != 1 and execution_mode == .scalar) {
            return error.UnsupportedRadiativeTransferControls;
        }
        if (self.threshold_conv_first <= 0.0 or
            self.threshold_conv_mult <= 0.0 or
            self.threshold_doubl <= 0.0 or
            self.threshold_mul <= 0.0)
        {
            return error.UnsupportedRadiativeTransferControls;
        }
    }

    pub fn resolvedNumOrdersMax(self: RadiativeTransferControls, scattering_optical_depth: f64) u16 {
        if (self.num_orders_max != 0) return self.num_orders_max;
        const heuristic = @max(scattering_optical_depth, 0.0) + 15.0;
        return @intFromFloat(std.math.clamp(heuristic, 1.0, @as(f64, std.math.maxInt(u16))));
    }

    pub fn nDirections(self: RadiativeTransferControls) u16 {
        return self.nGauss() + 2;
    }

    pub fn supermatrixSize(self: RadiativeTransferControls) u32 {
        return @as(u32, self.nDirections()) * @as(u32, self.stokes_dimension);
    }

    pub const default_vendor = RadiativeTransferControls{
        .scattering = .multiple,
        .n_streams = 16,
        .use_adding = false,
        .num_orders_max = 0,
        .fourier_floor_scalar = 2,
        .threshold_conv_first = 1.0e-6,
        .threshold_conv_mult = 1.0e-4,
        .threshold_doubl = 0.1,
        .threshold_mul = 1.0e-12,
        .use_spherical_correction = false,
        .integrate_source_function = true,
        .renorm_phase_function = true,
        .stokes_dimension = 1,
    };
};

pub const TransportFamily = enum {
    adding,
    labos,

    pub fn classification(self: TransportFamily) ImplementationClass {
        return switch (self) {
            .adding => .baseline,
            .labos => .baseline,
        };
    }

    pub fn provenanceLabel(self: TransportFamily) []const u8 {
        return switch (self) {
            .adding => "baseline_adding",
            .labos => "baseline_labos",
        };
    }
};

pub const ImplementationClass = enum {
    baseline,
    surrogate,
};

pub const DerivativeSemantics = enum {
    none,
    proxy,
    analytical,
};

pub const Regime = SceneModel.ObservationRegime;

pub const ExecutionMode = enum {
    scalar,
    polarized,
};

pub const DerivativeMode = SceneModel.DerivativeMode;

pub const DispatchRequest = struct {
    regime: Regime = .nadir,
    execution_mode: ExecutionMode = .scalar,
    derivative_mode: DerivativeMode = .none,
    rtm_controls: RadiativeTransferControls = .{},
};

pub const Route = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
    rtm_controls: RadiativeTransferControls = .{},

    pub fn derivativeSemantics(self: Route) DerivativeSemantics {
        if (self.derivative_mode == .none) return .none;
        return switch (self.family.classification()) {
            .surrogate => .proxy,
            .baseline => .analytical,
        };
    }
};

pub const LayerInput = struct {
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_scattering_optical_depth: f64 = 0.0,
    optical_depth: f64 = 0.0,
    scattering_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
    solar_mu: f64 = 1.0,
    view_mu: f64 = 1.0,
    phase_coefficients: [phase_coefficient_count]f64 = phase_functions.zeroPhaseCoefficients(),
};

pub const SourceInterfaceInput = struct {
    source_weight: f64 = 0.0,
    rtm_weight: f64 = 0.0,
    gas_ksca: f64 = 0.0,
    particle_ksca_above: f64 = 0.0,
    particle_ksca_below: f64 = 0.0,
    ksca_above: f64 = 0.0,
    ksca_below: f64 = 0.0,
    gas_phase_coefficients: [phase_coefficient_count]f64 = phase_functions.gasPhaseCoefficients(),
    phase_coefficients_above: [phase_coefficient_count]f64 = phase_functions.zeroPhaseCoefficients(),
    phase_coefficients_below: [phase_coefficient_count]f64 = phase_functions.zeroPhaseCoefficients(),

    pub fn effectiveWeight(self: SourceInterfaceInput) f64 {
        if (self.rtm_weight > 0.0 and self.ksca_above > 0.0) {
            return self.rtm_weight * self.ksca_above;
        }
        return self.source_weight;
    }
};

pub const RtmQuadratureLevel = struct {
    altitude_km: f64 = 0.0,
    weight: f64 = 0.0,
    ksca: f64 = 0.0,
    phase_coefficients: [phase_coefficient_count]f64 = phase_functions.zeroPhaseCoefficients(),

    pub fn weightedScattering(self: RtmQuadratureLevel) f64 {
        return self.weight * self.ksca;
    }
};

pub const RtmQuadratureGrid = struct {
    levels: []const RtmQuadratureLevel = &.{},

    pub fn isValidFor(self: RtmQuadratureGrid, layer_count: usize) bool {
        return self.levels.len == layer_count + 1;
    }
};

pub const PseudoSphericalSample = struct {
    altitude_km: f64 = 0.0,
    thickness_km: f64 = 0.0,
    optical_depth: f64 = 0.0,
};

pub const PseudoSphericalGrid = struct {
    samples: []const PseudoSphericalSample = &.{},
    level_sample_starts: []const usize = &.{},
    level_altitudes_km: []const f64 = &.{},

    pub fn isValidFor(self: PseudoSphericalGrid, layer_count: usize) bool {
        if (self.samples.len == 0) return false;
        if (self.level_sample_starts.len != layer_count + 1) return false;
        if (self.level_altitudes_km.len != 0 and self.level_altitudes_km.len != layer_count + 1) return false;
        if (self.level_sample_starts[0] != 0) return false;
        if (self.level_sample_starts[self.level_sample_starts.len - 1] != self.samples.len) return false;
        for (1..self.level_sample_starts.len) |index| {
            if (self.level_sample_starts[index] < self.level_sample_starts[index - 1] or
                self.level_sample_starts[index] > self.samples.len)
            {
                return false;
            }
        }
        return true;
    }
};

pub const ForwardInput = struct {
    wavelength_nm: f64 = 440.0,
    spectral_weight: f64 = 1.0,
    air_mass_factor: f64 = 1.0,
    mu0: f64 = 1.0,
    muv: f64 = 1.0,
    surface_albedo: f64 = 0.05,
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_scattering_optical_depth: f64 = 0.0,
    optical_depth: f64 = 0.5,
    single_scatter_albedo: f64 = 0.95,
    relative_azimuth_rad: f64 = 0.0,
    layers: []const LayerInput = &.{},
    source_interfaces: []const SourceInterfaceInput = &.{},
    rtm_quadrature: RtmQuadratureGrid = .{},
    pseudo_spherical_grid: PseudoSphericalGrid = .{},
    rtm_controls: RadiativeTransferControls = .{},
};

pub const ForwardResult = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
    toa_reflectance_factor: f64,
    jacobian_column: ?f64,
};

pub const PrepareError = error{
    UnsupportedDerivativeMode,
    UnsupportedExecutionMode,
    UnsupportedRadiativeTransferControls,
};

pub const ExecuteError = PrepareError || error{
    SingularDoublingDenominator,
    MissingExplicitRtmQuadrature,
    OutOfMemory,
};

pub const Error = ExecuteError;
