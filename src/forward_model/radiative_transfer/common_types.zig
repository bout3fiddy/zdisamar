const std = @import("std");
const SceneModel = @import("../../input/Scene.zig");
const jacobian = @import("../jacobian/root.zig");
const phase_functions = @import("../optical_properties/shared/phase_functions.zig");

pub const phase_coefficient_count = phase_functions.phase_coefficient_count;
pub const LayerPhase = phase_functions.PhaseMixture;

// Atmospheric scattering treatment.
pub const ScatteringMode = enum(u2) {
    none = 0,
    single = 1,
    multiple = 2,
};

// layout(64-bit):
//   size: 56 B, align: 8 B
//   field storage: 56 B across 9 fields; largest: fourier_tail_reflectance_epsilon=8 B, threshold_conv_first=8 B, threshold_conv_mult=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 56 B (0.055 KiB); total = per instance * live instance count
pub const RadiativeTransferPerformanceThresholds = struct {
    num_orders_max: u16 = 0,
    fourier_floor_scalar: u16 = 2,
    fourier_order_cap: ?u16 = null,
    fourier_tail_reflectance_epsilon: f64 = 3.0e-14,
    threshold_conv_first: f64 = 1.0e-6,
    threshold_conv_mult: f64 = 1.0e-4,
    threshold_doubl: f64 = 0.1,
    threshold_mul: f64 = 1.0e-12,
    phase_function_truncation_threshold: f64 = phase_functions.vendor_hg_truncation_threshold,

    pub fn validate(self: RadiativeTransferPerformanceThresholds) PrepareError!void {
        if (self.fourier_tail_reflectance_epsilon <= 0.0 or
            self.threshold_conv_first <= 0.0 or
            self.threshold_conv_mult <= 0.0 or
            self.threshold_doubl <= 0.0 or
            self.threshold_mul <= 0.0 or
            self.phase_function_truncation_threshold <= 0.0 or
            !std.math.isFinite(self.fourier_tail_reflectance_epsilon) or
            !std.math.isFinite(self.threshold_conv_first) or
            !std.math.isFinite(self.threshold_conv_mult) or
            !std.math.isFinite(self.threshold_doubl) or
            !std.math.isFinite(self.threshold_mul) or
            !std.math.isFinite(self.phase_function_truncation_threshold))
        {
            return error.UnsupportedRadiativeTransferControls;
        }
    }

    pub fn resolvedNumOrdersMax(
        self: RadiativeTransferPerformanceThresholds,
        scattering_optical_depth: f64,
    ) u16 {
        if (self.num_orders_max != 0) return self.num_orders_max;
        const heuristic = @max(scattering_optical_depth, 0.0) + 15.0;
        return @intFromFloat(std.math.clamp(heuristic, 1.0, @as(f64, std.math.maxInt(u16))));
    }

    pub fn cappedFourierMax(
        self: RadiativeTransferPerformanceThresholds,
        resolved_fourier_max: usize,
    ) usize {
        return if (self.fourier_order_cap) |cap| @min(resolved_fourier_max, @as(usize, cap)) else resolved_fourier_max;
    }

    pub const o2a_default = RadiativeTransferPerformanceThresholds{
        .num_orders_max = 0,
        .fourier_floor_scalar = 2,
        .fourier_order_cap = null,
        .fourier_tail_reflectance_epsilon = 3.0e-14,
        .threshold_conv_first = 1.5e-7,
        .threshold_conv_mult = 1.5e-9,
        .threshold_doubl = 1.0e-6,
        .threshold_mul = 1.0e-8,
        .phase_function_truncation_threshold = 1.0e-8,
    };
};

// Resolved radiative transfer controls compiled from canonical configuration.
// layout(64-bit):
//   size: 64 B, align: 8 B
//   field storage: 64 B across 8 fields; largest: performance_thresholds=56 B, n_streams=2 B, scattering=1 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 28 bool-storage slack = 28 bits
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 64 B (0.062 KiB); total = per instance * live instance count
pub const RadiativeTransferControls = struct {
    scattering: ScatteringMode = .multiple,
    n_streams: u16 = 16,
    use_adding: bool = false,
    performance_thresholds: RadiativeTransferPerformanceThresholds = .{},
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
        try self.performance_thresholds.validate();
    }

    pub fn resolvedNumOrdersMax(self: RadiativeTransferControls, scattering_optical_depth: f64) u16 {
        return self.performance_thresholds.resolvedNumOrdersMax(scattering_optical_depth);
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
        .performance_thresholds = .{},
        .use_spherical_correction = false,
        .integrate_source_function = true,
        .renorm_phase_function = true,
        .stokes_dimension = 1,
    };
};

pub const TransportFamily = enum {
    labos,

    pub fn classification(self: TransportFamily) ImplementationClass {
        return switch (self) {
            .labos => .baseline,
        };
    }

    pub fn provenanceLabel(self: TransportFamily) []const u8 {
        return switch (self) {
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

// layout(64-bit):
//   size: 72 B, align: 8 B
//   field storage: rtm_controls=64 B, regime=1 B, execution_mode=1 B, derivative_mode=1 B; padding: 5 B (40 bits)
//   unused bits: 40 padding + 0 bool-storage slack = 40 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 72 B (0.070 KiB); total = per instance * live instance count
pub const DispatchRequest = struct {
    regime: Regime = .nadir,
    execution_mode: ExecutionMode = .scalar,
    derivative_mode: DerivativeMode = .none,
    rtm_controls: RadiativeTransferControls = .{},
};

// layout(64-bit):
//   size: 72 B, align: 8 B
//   field storage: 68 B across 6 fields; largest: rtm_controls=64 B, regime=1 B, execution_mode=1 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 72 B (0.070 KiB); total = per instance * live instance count
pub const Route = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
    derivative_state_mask: jacobian.StateMask = jacobian.all_states_mask,
    rtm_controls: RadiativeTransferControls = .{},

    pub fn derivativeSemantics(self: Route) DerivativeSemantics {
        if (self.derivative_mode == .none) return .none;
        return switch (self.family.classification()) {
            .surrogate => .proxy,
            .baseline => .analytical,
        };
    }
};

// layout(64-bit):
//   size: 208 B, align: 8 B
//   field storage: 208 B across 16 fields; largest: phase=40 B, optical_depth_jacobian=24 B, scattering_optical_depth_jacobian=24 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   inline arrays: 3 Jacobian vectors reserve 72 B inside each instance
//   encoded fields: phase stores gas/aerosol/cloud phase weights plus shared phase-row references instead of a full 1208 B coefficient row
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 208 B (0.203 KiB); total also includes referenced phase storage above
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
    optical_depth_jacobian: jacobian.Vector = jacobian.zero(),
    scattering_optical_depth_jacobian: jacobian.Vector = jacobian.zero(),
    single_scatter_albedo_jacobian: jacobian.Vector = jacobian.zero(),
    solar_mu: f64 = 1.0,
    view_mu: f64 = 1.0,
    phase: LayerPhase = .{},
};

// layout(64-bit):
//   size: 80 B, align: 8 B
//   field storage: 80 B across 6 fields; largest: phase_above=40 B, source_weight=8 B, rtm_weight=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   encoded fields: phase_above stores gas/aerosol/cloud phase weights plus shared phase-row references; phase_max_index_above and phase_max_index_below store Fourier bounds
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 80 B (0.078 KiB); total also includes referenced phase storage above
pub const SourceInterfaceInput = struct {
    source_weight: f64 = 0.0,
    rtm_weight: f64 = 0.0,
    ksca_above: f64 = 0.0,
    phase_above: LayerPhase = .{},
    phase_max_index_above: usize = 0,
    phase_max_index_below: usize = 0,

    pub fn effectiveWeight(self: SourceInterfaceInput) f64 {
        if (self.rtm_weight > 0.0 and self.ksca_above > 0.0) {
            return self.rtm_weight * self.ksca_above;
        }
        return self.source_weight;
    }
};

// layout(64-bit):
//   size: 72 B, align: 8 B
//   field storage: 72 B across 9 fields; largest: altitude_km=8 B, weight=8 B, ksca=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   encoded fields: phase_aerosol_weight, phase_cloud_weight, and phase_rayleigh2_weight encode the full 1208 B combined phase row
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 72 B (0.070 KiB); total = per instance * live instance count
pub const RtmQuadratureLevel = struct {
    altitude_km: f64 = 0.0,
    weight: f64 = 0.0,
    ksca: f64 = 0.0,
    aerosol_ksca_above_per_km: f64 = 0.0,
    aerosol_ksca_below_per_km: f64 = 0.0,
    aerosol_ksca_jacobian: f64 = 0.0,
    phase_aerosol_weight: f64 = 0.0,
    phase_cloud_weight: f64 = 0.0,
    phase_rayleigh2_weight: f64 = 0.0,

    pub fn weightedScattering(self: RtmQuadratureLevel) f64 {
        return self.weight * self.ksca;
    }

    pub fn setPhaseMixture(
        self: *RtmQuadratureLevel,
        rayleigh_phase_coefficient2: f64,
        gas_ksca: f64,
        aerosol_ksca: f64,
        cloud_ksca: f64,
    ) void {
        const total = gas_ksca + aerosol_ksca + cloud_ksca;
        if (total <= 0.0) {
            self.phase_aerosol_weight = 0.0;
            self.phase_cloud_weight = 0.0;
            self.phase_rayleigh2_weight = rayleigh_phase_coefficient2;
            return;
        }
        const inv_total = 1.0 / total;
        self.phase_aerosol_weight = aerosol_ksca * inv_total;
        self.phase_cloud_weight = cloud_ksca * inv_total;
        self.phase_rayleigh2_weight = gas_ksca * inv_total * rayleigh_phase_coefficient2;
    }
};

const default_aerosol_phase_coefficients = phase_functions.zeroPhaseCoefficients();
const default_cloud_phase_coefficients = phase_functions.zeroPhaseCoefficients();

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: levels=16 B, aerosol_phase_coefficients=8 B, cloud_phase_coefficients=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: levels carries a slice descriptor, aerosol_phase_coefficients and cloud_phase_coefficients point at prepared phase storage; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above
pub const RtmQuadratureGrid = struct {
    levels: []const RtmQuadratureLevel = &.{},
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64 = &default_aerosol_phase_coefficients,
    cloud_phase_coefficients: *const [phase_coefficient_count]f64 = &default_cloud_phase_coefficients,

    pub fn isValidFor(self: RtmQuadratureGrid, layer_count: usize) bool {
        return self.levels.len == layer_count + 1;
    }
};

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: altitude_km=8 B, thickness_km=8 B, optical_depth=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count
pub const PseudoSphericalSample = struct {
    altitude_km: f64 = 0.0,
    thickness_km: f64 = 0.0,
    optical_depth: f64 = 0.0,
};

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: samples=16 B, level_sample_starts=16 B, level_altitudes_km=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: samples, level_sample_starts, level_altitudes_km carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
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

// layout(64-bit):
//   size: 304 B, align: 8 B
//   field storage: 304 B across 21 fields; largest: rtm_controls=64 B, pseudo_spherical_grid=48 B, rtm_quadrature=32 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: layers, source_interfaces carry references/descriptors; referenced storage is not included in size
//   cache span: 5 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 304 B (0.297 KiB); total also includes referenced storage above
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

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: 43 B across 6 fields; largest: jacobian=32 B, toa_reflectance_factor=8 B, regime=1 B; padding: 5 B (40 bits)
//   unused bits: 40 padding + 0 bool-storage slack = 40 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total = per instance * live instance count
pub const ForwardResult = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
    toa_reflectance_factor: f64,
    jacobian: ?jacobian.Vector,
};

pub const PrepareError = error{
    UnsupportedExecutionMode,
    UnsupportedDerivativeMode,
    UnsupportedTransportSolver,
    UnsupportedObservationRegime,
    UnsupportedRadiativeTransferControls,
};

pub const ExecuteError = PrepareError || error{
    SingularDoublingDenominator,
    MissingExplicitRtmQuadrature,
    OutOfMemory,
};

pub const Error = ExecuteError;
