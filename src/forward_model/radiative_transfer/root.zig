const std = @import("std");
pub const labos = struct {
    const basis = @import("labos/basis.zig");
    const attenuation = @import("labos/attenuation.zig");
    const execute_mod = @import("labos/execute.zig");
    const layers_mod = @import("labos/layers.zig");
    const orders_mod = @import("labos/orders.zig");
    const reflectance_mod = @import("labos/reflectance.zig");
    const workspace_mod = @import("labos/workspace.zig");

    // root.zig --------------------------------------------------------------------------------------------------|
    // Public LABOS facade for the wider radiative-transfer package. Implementation details stay in the sibling   |
    // files; this file chooses which names are part of the LABOS API.                                            |
    // -----------------------------------------------------------------------------------------------------------|

    pub const max_gauss = basis.max_gauss;
    pub const max_extra = basis.max_extra;
    pub const max_nmutot = basis.max_nmutot;
    pub const max_n2 = basis.max_n2;
    pub const max_phase_coef = basis.max_phase_coef;

    pub const Mat = basis.Mat;
    pub const Vec = basis.Vec;
    pub const Vec2 = basis.Vec2;
    pub const Geometry = basis.Geometry;
    pub const LayerRT = basis.LayerRT;
    pub const UDField = basis.UDField;
    pub const UDLocal = basis.UDLocal;
    pub const PhaseKernel = basis.PhaseKernel;
    pub const PhaseKernelRow = basis.PhaseKernelRow;
    pub const FourierPlmBasis = basis.FourierPlmBasis;
    pub const fillZplusZminFromBasis = basis.fillZplusZminFromBasis;
    pub const DynamicAttenArray = attenuation.DynamicAttenArray;
    pub const max_attenuation_levels = attenuation.max_levels;
    pub const Workspace = workspace_mod.Workspace;

    pub const smul = basis.smul;
    pub const esmul = basis.esmul;
    pub const semul = basis.semul;
    pub const matAdd = basis.matAdd;
    pub const qseries = basis.qseries;
    pub const fillZplusZmin = basis.fillZplusZmin;

    pub const fillAttenuationDynamic = attenuation.fillAttenuationDynamic;
    pub const fillAttenuationDynamicWithGrid = attenuation.fillAttenuationDynamicWithGrid;

    pub const calcRTlayersInto = layers_mod.calcRTlayersInto;
    pub const calcRTlayersIntoWithBasis = layers_mod.calcRTlayersIntoWithBasis;
    pub const calcRTlayers = layers_mod.calcRTlayers;
    pub const fillSurface = layers_mod.fillSurface;

    pub const dotGauss = orders_mod.dotGauss;
    pub const OrdersWorkspace = orders_mod.OrdersWorkspace;
    pub const ordersScatInto = orders_mod.ordersScatInto;
    pub const ordersScatIntoWithLocalSum = orders_mod.ordersScatIntoWithLocalSum;
    pub const ordersScatIntoWithActive = orders_mod.ordersScatIntoWithActive;
    pub const ordersScatIntoWithActiveLocalSum = orders_mod.ordersScatIntoWithActiveLocalSum;

    pub const calcReflectance = reflectance_mod.calcReflectance;
    pub const calcIntegratedReflectance = reflectance_mod.calcIntegratedReflectance;
    pub const calcIntegratedReflectanceWithBasis = reflectance_mod.calcIntegratedReflectanceWithBasis;
    pub const resolvedFourierMax = reflectance_mod.resolvedFourierMax;
    pub const resolvedPhaseCoefficientMax = reflectance_mod.resolvedPhaseCoefficientMax;
    pub const totalScatteringOpticalDepth = reflectance_mod.totalScatteringOpticalDepth;

    pub const execute = execute_mod.execute;
    pub const executeWithWorkspace = execute_mod.executeWithWorkspace;
};

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
//   size: 64 B, align: 8 B
//   field storage: 63 B across 13 fields; largest: fourier_tail_reflectance_epsilon=8 B, threshold_conv_first=8 B, threshold_conv_mult=8 B; padding: 1 B (8 bits)
//   unused bits: 8 padding + 0 bool-storage slack = 8 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 64 B (0.062 KiB); total = per instance * live instance count
pub const RadiativeTransferPerformanceThresholds = struct {
    num_orders_max: u16 = 0,
    fourier_floor_scalar: u16 = 2,
    fourier_order_cap: ?u16 = null,
    aerosol_tangent_order_cap: ?u16 = null,
    fourier_tail_reflectance_epsilon: f64 = 3.0e-14,
    threshold_conv_first: f64 = 1.0e-6,
    threshold_conv_mult: f64 = 1.0e-4,
    threshold_doubl: f64 = 0.1,
    threshold_mul: f64 = 1.0e-12,
    phase_function_truncation_threshold: f64 = phase_functions.vendor_hg_truncation_threshold,
    qzero_rd_product_suppression: bool = false,
    qzero_tu_product_suppression: bool = false,
    qzero_td_product_suppression: bool = false,

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
        // math: default multiple-scattering order cap = clamp(max(tau_sca, 0) + 15, 1, max_u16).
        const heuristic = @max(scattering_optical_depth, 0.0) + 15.0;
        return @intFromFloat(std.math.clamp(heuristic, 1.0, @as(f64, std.math.maxInt(u16))));
    }

    pub fn cappedFourierMax(
        self: RadiativeTransferPerformanceThresholds,
        resolved_fourier_max: usize,
    ) usize {
        return if (self.fourier_order_cap) |cap| @min(resolved_fourier_max, @as(usize, cap)) else resolved_fourier_max;
    }

    pub fn shouldEvaluateAerosolTangent(
        self: RadiativeTransferPerformanceThresholds,
        fourier_index: usize,
    ) bool {
        return if (self.aerosol_tangent_order_cap) |cap| fourier_index <= @as(usize, cap) else true;
    }

    pub const o2a_default = RadiativeTransferPerformanceThresholds{
        .num_orders_max = 0,
        .fourier_floor_scalar = 2,
        .fourier_order_cap = null,
        .aerosol_tangent_order_cap = null,
        .fourier_tail_reflectance_epsilon = 3.0e-14,
        .threshold_conv_first = 1.5e-7,
        .threshold_conv_mult = 1.5e-9,
        .threshold_doubl = 1.0e-6,
        .threshold_mul = 1.0e-8,
        .phase_function_truncation_threshold = 1.0e-8,
        .qzero_rd_product_suppression = false,
        .qzero_tu_product_suppression = false,
        .qzero_td_product_suppression = false,
    };
};

// Resolved radiative transfer controls compiled from canonical configuration.
// layout(64-bit):
//   size: 72 B, align: 8 B
//   field storage: 70 B across 6 fields; largest: performance_thresholds=64 B, n_streams=2 B, scattering=1 B; padding: 2 B (16 bits)
//   unused bits: 16 padding + 27 enum/bool-storage slack = 43 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 72 B (0.070 KiB); total = per instance * live instance count
pub const RadiativeTransferControls = struct {
    scattering: ScatteringMode = .multiple,
    n_streams: u16 = 16,
    performance_thresholds: RadiativeTransferPerformanceThresholds = .{},
    use_spherical_correction: bool = false,
    integrate_source_function: bool = true,
    renorm_phase_function: bool = true,

    pub fn nGauss(self: RadiativeTransferControls) u16 {
        return self.n_streams / 2;
    }

    pub fn validate(self: RadiativeTransferControls) PrepareError!void {
        if (self.n_streams < 4 or (self.n_streams % 2) != 0) {
            return error.UnsupportedRadiativeTransferControls;
        }
        switch (self.nGauss()) {
            2, 3, 4, 8, 10 => {},
            else => return error.UnsupportedRadiativeTransferControls,
        }
        try self.performance_thresholds.validate();
    }

    pub fn resolvedNumOrdersMax(self: RadiativeTransferControls, scattering_optical_depth: f64) u16 {
        return self.performance_thresholds.resolvedNumOrdersMax(scattering_optical_depth);
    }

    pub fn supermatrixSize(self: RadiativeTransferControls) u32 {
        return @as(u32, self.nGauss() + 2);
    }

    pub const default_vendor = RadiativeTransferControls{
        .scattering = .multiple,
        .n_streams = 16,
        .performance_thresholds = .{},
        .use_spherical_correction = false,
        .integrate_source_function = true,
        .renorm_phase_function = true,
    };
};

pub const DerivativeMode = SceneModel.DerivativeMode;

// layout(64-bit):
//   size: 80 B, align: 8 B
//   field storage:
//     75 B across 4 fields; largest: rtm_controls=72 B, regime=1 B, derivative_mode=1 B
//     padding: 5 B (40 bits)
//   unused bits: 40 padding + 0 bool-storage slack = 40 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 80 B (0.078 KiB); total = per instance * live instance count
pub const SolveConfig = struct {
    derivative_mode: DerivativeMode = .none,
    derivative_state_mask: jacobian.StateMask = jacobian.all_states_mask,
    rtm_controls: RadiativeTransferControls = .{},
};

// layout(64-bit):
//   size: 208 B, align: 8 B
//   field storage: 208 B across 16 fields; largest: phase=40 B, optical_depth_jacobian=24 B, scattering_optical_depth_jacobian=24 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   inline arrays: 3 Jacobian vectors reserve 72 B inside each instance
//   encoded fields: phase stores gas/aerosol phase weights plus shared phase-row references instead of a full 1208 B coefficient row
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 208 B (0.203 KiB); total also includes referenced phase storage above
pub const LayerInput = struct {
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
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
//   encoded fields: phase_above stores gas/aerosol phase weights plus shared phase-row references; phase_max_index_above and phase_max_index_below store Fourier bounds
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
            // math: RTM quadrature source weight = quadrature_weight * scattering_coefficient_above.
            return self.rtm_weight * self.ksca_above;
        }
        return self.source_weight;
    }
};

// layout(64-bit):
//   size: 72 B, align: 8 B
//   field storage: 72 B across 9 fields; largest: altitude_km=8 B, weight=8 B, ksca=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   encoded fields: phase_aerosol_weight and phase_rayleigh2_weight encode the full 1208 B combined phase row
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
    phase_rayleigh2_weight: f64 = 0.0,

    pub fn weightedScattering(self: RtmQuadratureLevel) f64 {
        // math: weighted scattering source = quadrature_weight * k_sca.
        return self.weight * self.ksca;
    }

    pub fn setPhaseMixture(
        self: *RtmQuadratureLevel,
        rayleigh_phase_coefficient2: f64,
        gas_ksca: f64,
        aerosol_ksca: f64,
    ) void {
        const total = gas_ksca + aerosol_ksca;
        if (total <= 0.0) {
            self.phase_aerosol_weight = 0.0;
            self.phase_rayleigh2_weight = rayleigh_phase_coefficient2;
            return;
        }
        const inv_total = 1.0 / total;
        // math: phase mixture = (aerosol_ksca / total_ksca) * aerosol_phase + (gas_ksca / total_ksca) * Rayleigh2.
        self.phase_aerosol_weight = aerosol_ksca * inv_total;
        self.phase_rayleigh2_weight = gas_ksca * inv_total * rayleigh_phase_coefficient2;
    }
};

const default_aerosol_phase_coefficients = phase_functions.zeroPhaseCoefficients();

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: levels=16 B, aerosol_phase_coefficients=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: levels carries a slice descriptor, aerosol_phase_coefficients points at prepared phase storage; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total also includes referenced storage above
pub const RtmQuadratureGrid = struct {
    levels: []const RtmQuadratureLevel = &.{},
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64 = &default_aerosol_phase_coefficients,

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
    toa_reflectance_factor: f64,
    jacobian: ?jacobian.Vector,
};

pub const PrepareError = error{
    UnsupportedDerivativeMode,
    UnsupportedRadiativeTransferControls,
};

pub const ExecuteError = PrepareError || error{
    SingularDoublingDenominator,
    MissingExplicitRtmQuadrature,
    OutOfMemory,
};

pub const Error = ExecuteError;

pub const Jacobian = jacobian;

pub fn prepareSolveConfig(config: SolveConfig) PrepareError!SolveConfig {
    try config.rtm_controls.validate();
    return config;
}

pub fn executePrepared(
    allocator: std.mem.Allocator,
    rtm_config: SolveConfig,
    input: ForwardInput,
) ExecuteError!ForwardResult {
    return executePreparedWithLabosWorkspace(allocator, rtm_config, input, null);
}

pub fn executePreparedWithLabosWorkspace(
    allocator: std.mem.Allocator,
    rtm_config: SolveConfig,
    input: ForwardInput,
    workspace: ?*labos.Workspace,
) ExecuteError!ForwardResult {
    return labos.executeWithWorkspace(allocator, rtm_config, input, workspace);
}

pub fn execute(
    allocator: std.mem.Allocator,
    config: SolveConfig,
    input: ForwardInput,
) ExecuteError!ForwardResult {
    const rtm_config = try prepareSolveConfig(config);
    return executePrepared(allocator, rtm_config, input);
}

pub fn sourceInterfaceFromLayers(
    layers: []const LayerInput,
    ilevel: usize,
) SourceInterfaceInput {
    if (layers.len == 0) return .{};
    const above_index = @min(ilevel, layers.len - 1);
    const below_index = if (ilevel > 0) ilevel - 1 else above_index;
    // math: fallback source weight uses layer scattering optical depth, with half weight at the top boundary.
    const source_weight = if (ilevel < layers.len)
        @max(layers[ilevel].scattering_optical_depth, 0.0)
    else
        0.5 * @max(layers[above_index].scattering_optical_depth, 0.0);

    return .{
        .source_weight = source_weight,
        .ksca_above = @max(layers[above_index].scattering_optical_depth, 0.0),
        .phase_above = layers[above_index].phase,
        .phase_max_index_above = layers[above_index].phase.maxIndex(),
        .phase_max_index_below = if (ilevel > 0)
            layers[below_index].phase.maxIndex()
        else
            0,
    };
}

pub fn fillSourceInterfacesFromLayers(
    layers: []const LayerInput,
    source_interfaces: []SourceInterfaceInput,
) void {
    if (layers.len == 0 or source_interfaces.len != layers.len + 1) return;
    for (source_interfaces, 0..) |*source_interface, ilevel| {
        source_interface.* = sourceInterfaceFromLayers(layers, ilevel);
    }
}
