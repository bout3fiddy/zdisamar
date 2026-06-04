const std = @import("std");
const SceneModel = @import("../../input/Scene.zig");
const jacobian = @import("../jacobian/root.zig");
const phase_functions = @import("../optical_properties/shared/phase_functions.zig");

// root.zig ---------------------------------------------------------------------------------------------------|
// Public RTM entry point. Callers bring prepared optical properties and controls here; LABOS                  |
// solves the transport problem and returns reflectance plus optional Jacobian values.                         |
//                                                                                                             |
// main paths                                                                                                  |
//   prepareSolveConfig                    -> reject unsupported RTM controls before the solve                 |
//   execute                               -> prepare controls, then call the prepared path                    |
//   executePreparedWithLabosWorkspace     -> call the LABOS solve with optional caller-owned scratch memory   |
//   sourceInterfaceFromLayers             -> build source interfaces from layer data when none are supplied   |
//                                                                                                             |
// ownership                                                                                                   |
//   ForwardInput borrows layer/source/quadrature slices. LABOS workspace ownership stays in labos.Workspace.  |
// ------------------------------------------------------------------------------------------------------------|

pub const labos = struct {
    const basis = @import("labos/basis.zig");
    const attenuation = @import("labos/attenuation.zig");
    const execute_mod = @import("labos/execute.zig");
    const layers_mod = @import("labos/layers.zig");
    const orders_mod = @import("labos/orders.zig");
    const reflectance_mod = @import("labos/reflectance.zig");
    const workspace_mod = @import("labos/workspace.zig");

    // labos facade -------------------------------------------------------------------------------------------|
    // This struct is a namespace of aliases. It is not a value that gets allocated, and it does not wrap      |
    // calls. Each pub const line gives another name to code in a sibling LABOS file; Zig resolves the name    |
    // at compile time.                                                                                        |
    //                                                                                                         |
    // why keep this facade                                                                                    |
    //   one public door : RTM code imports LABOS through root.zig, not every child file                       |
    //   clear exports   : helper-only names can stay private inside their own LABOS module                    |
    //   split hot code   : child files stay grouped by data: basis arrays, attenuation tables, layer R/T      |
    //                      matrices, order workspaces, and reflectance accumulation                           |
    //   simple callers   : callers see the LABOS API, not the file split used to keep hot loops readable      |
    //   cheap moves      : moving a public LABOS name between child files only changes this export list       |
    //                                                                                                         |
    // why it has no runtime cost                                                                              |
    //   no instance : callers use labos as a namespace; no labos value is allocated                           |
    //   no wrapper  : each pub const is an alias, so calls go straight to the target function                 |
    //   no hidden state : scratch memory is still explicit in Workspace and executeWithWorkspace              |
    //                                                                                                         |
    // export sections                                                                                         |
    //   limits -> shared data shapes -> basis math -> attenuation -> layers -> orders -> reflectance -> run   |
    // --------------------------------------------------------------------------------------------------------|

    // size limits --------------------------------------------------------------------------------------------|
    // Fixed LABOS array bounds shared by workspaces, matrices, phase rows, and tests.                         |
    pub const max_gauss = basis.max_gauss;
    pub const max_extra = basis.max_extra;
    pub const max_nmutot = basis.max_nmutot;
    pub const max_n2 = basis.max_n2;
    pub const max_phase_coef = basis.max_phase_coef;
    pub const max_attenuation_levels = attenuation.max_levels;

    // shared data shapes -------------------------------------------------------------------------------------|
    // Types that callers need when they build or inspect LABOS work. They are aliases to the owner module.    |
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
    pub const DynamicAttenArray = attenuation.DynamicAttenArray;
    pub const Workspace = workspace_mod.Workspace;

    // basis math ---------------------------------------------------------------------------------------------|
    // Small matrix/vector kernels used by layer and order code. Exported for tests and focused callers.       |
    pub const smul = basis.smul;
    pub const esmul = basis.esmul;
    pub const semul = basis.semul;
    pub const matAdd = basis.matAdd;
    pub const qseries = basis.qseries;
    pub const fillZplusZmin = basis.fillZplusZmin;
    pub const fillZplusZminFromBasis = basis.fillZplusZminFromBasis;

    // attenuation builders -----------------------------------------------------------------------------------|
    // Direct-beam attenuation tables, with and without a pseudo-spherical support grid.                       |
    pub const fillAttenuationDynamic = attenuation.fillAttenuationDynamic;
    pub const fillAttenuationDynamicWithGrid = attenuation.fillAttenuationDynamicWithGrid;

    // layer builders -----------------------------------------------------------------------------------------|
    // Convert prepared layer input into reflection/transmission matrices and the surface boundary.            |
    pub const calcRTlayersInto = layers_mod.calcRTlayersInto;
    pub const calcRTlayersIntoWithBasis = layers_mod.calcRTlayersIntoWithBasis;
    pub const calcRTlayers = layers_mod.calcRTlayers;
    pub const fillSurface = layers_mod.fillSurface;

    // scattering orders --------------------------------------------------------------------------------------|
    // Workspaces and loops for repeated scattering-order solves.                                              |
    pub const dotGauss = orders_mod.dotGauss;
    pub const OrdersWorkspace = orders_mod.OrdersWorkspace;
    pub const ordersScatInto = orders_mod.ordersScatInto;
    pub const ordersScatIntoWithLocalSum = orders_mod.ordersScatIntoWithLocalSum;
    pub const ordersScatIntoWithActive = orders_mod.ordersScatIntoWithActive;
    pub const ordersScatIntoWithActiveLocalSum = orders_mod.ordersScatIntoWithActiveLocalSum;

    // reflectance helpers ------------------------------------------------------------------------------------|
    // Combine Fourier/order results and choose the resolved phase/Fourier limits.                             |
    pub const calcReflectance = reflectance_mod.calcReflectance;
    pub const calcIntegratedReflectance = reflectance_mod.calcIntegratedReflectance;
    pub const calcIntegratedReflectanceWithBasis = reflectance_mod.calcIntegratedReflectanceWithBasis;
    pub const resolvedFourierMax = reflectance_mod.resolvedFourierMax;
    pub const resolvedPhaseCoefficientMax = reflectance_mod.resolvedPhaseCoefficientMax;
    pub const totalScatteringOpticalDepth = reflectance_mod.totalScatteringOpticalDepth;

    // run entry points ---------------------------------------------------------------------------------------|
    // Full LABOS solves. The workspace form lets callers reuse scratch memory across wavelengths.             |
    pub const execute = execute_mod.execute;
    pub const executeWithWorkspace = execute_mod.executeWithWorkspace;
};

pub const phase_coefficient_count = phase_functions.phase_coefficient_count;
pub const LayerPhase = phase_functions.PhaseMixture;

// ScatteringMode ---------------------------------------------------------------------------------------------|
// Scattering mode used by prepared RTM controls.                                                              |
//                                                                                                             |
// none     : skip scattering orders and use direct surface reflection                                         |
// single   : run the first scattering order and skip later multiple-scattering feedback                       |
// multiple : run the full multiple-scattering LABOS order loop                                                |
// ------------------------------------------------------------------------------------------------------------|
pub const ScatteringMode = enum(u2) {
    none = 0,
    single = 1,
    multiple = 2,
};
// ------------------------------------------------------------------------------------------------------------|

// RadiativeTransferPerformanceThresholds ---------------------------------------------------------------------|
// LABOS limits and cutoffs prepared from user controls. These values decide how much Fourier/order work       |
// is kept and which tiny matrix products may be skipped.                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] fourier_tail_reflectance_epsilon    : f64                                                          |
// [ 8..15] threshold_conv_first                : f64                                                          |
// [16..23] threshold_conv_mult                 : f64                                                          |
// [24..31] threshold_doubl                     : f64                                                          |
// [32..39] threshold_mul                       : f64                                                          |
// [40..47] phase_function_truncation_threshold : f64                                                          |
// [48..49] num_orders_max                      : u16                                                          |
// [50..51] fourier_floor_scalar                : u16                                                          |
// [52..55] fourier_order_cap                   : ?u16                                                         |
// [56..59] aerosol_tangent_order_cap           : ?u16                                                         |
// [60..60] qzero_rd_product_suppression        : bool                                                         |
// [61..61] qzero_tu_product_suppression        : bool                                                         |
// [62..62] qzero_td_product_suppression        : bool                                                         |
// [63..63] padding                             : 1 B                                                          |
//                                                                                                             |
// unused bits: 8 padding + 21 bool-storage slack = 29 bits                                                    |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 64 B (0.062 KiB); total = per instance * live instance count                      |
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
        // RadiativeTransferPerformanceThresholds.validate ----------------------------------------------------|
        // Reject zero, negative, NaN, and infinite thresholds before LABOS sees them.                         |
        //                                                                                                     |
        // Later code divides by these values and uses them to stop or skip work.                              |
        // ----------------------------------------------------------------------------------------------------|

        const positive_thresholds =
            self.fourier_tail_reflectance_epsilon > 0.0 and
            self.threshold_conv_first > 0.0 and
            self.threshold_conv_mult > 0.0 and
            self.threshold_doubl > 0.0 and
            self.threshold_mul > 0.0 and
            self.phase_function_truncation_threshold > 0.0;

        const finite_thresholds =
            std.math.isFinite(self.fourier_tail_reflectance_epsilon) and
            std.math.isFinite(self.threshold_conv_first) and
            std.math.isFinite(self.threshold_conv_mult) and
            std.math.isFinite(self.threshold_doubl) and
            std.math.isFinite(self.threshold_mul) and
            std.math.isFinite(self.phase_function_truncation_threshold);

        if (!positive_thresholds or !finite_thresholds) return error.UnsupportedRadiativeTransferControls;
    }

    pub fn resolvedNumOrdersMax(
        self: RadiativeTransferPerformanceThresholds,
        scattering_optical_depth: f64,
    ) u16 {
        // RadiativeTransferPerformanceThresholds.resolvedNumOrdersMax ----------------------------------------|
        // Choose the maximum number of scattering orders. A non-zero user cap wins; otherwise use the         |
        // DISAMAR-like optical-depth rule.                                                                    |
        //                                                                                                     |
        // math                                                                                                |
        //   default cap = clamp(max(scattering_optical_depth, 0) + 15, 1, max_u16)                            |
        // ----------------------------------------------------------------------------------------------------|

        if (self.num_orders_max != 0) return self.num_orders_max;

        const heuristic = @max(scattering_optical_depth, 0.0) + 15.0;
        return @intFromFloat(std.math.clamp(heuristic, 1.0, @as(f64, std.math.maxInt(u16))));
    }

    pub fn cappedFourierMax(
        self: RadiativeTransferPerformanceThresholds,
        resolved_fourier_max: usize,
    ) usize {
        // RadiativeTransferPerformanceThresholds.cappedFourierMax --------------------------------------------|
        // Apply the optional Fourier cap after phase data reports the maximum Fourier term.                   |
        // ----------------------------------------------------------------------------------------------------|

        if (self.fourier_order_cap) |cap| return @min(resolved_fourier_max, @as(usize, cap));
        return resolved_fourier_max;
    }

    pub fn shouldEvaluateAerosolTangent(
        self: RadiativeTransferPerformanceThresholds,
        fourier_index: usize,
    ) bool {
        // RadiativeTransferPerformanceThresholds.shouldEvaluateAerosolTangent --------------------------------|
        // Keep the aerosol tangent on all Fourier terms unless the caller sets a cap.                         |
        // ----------------------------------------------------------------------------------------------------|

        if (self.aerosol_tangent_order_cap) |cap| return fourier_index <= @as(usize, cap);
        return true;
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
// ------------------------------------------------------------------------------------------------------------|

// RadiativeTransferControls ----------------------------------------------------------------------------------|
// RTM controls after input parsing. These choose the LABOS scattering mode, stream count, source              |
// integration, spherical correction, and thresholds.                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 72 B (0.070 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..63] performance_thresholds     : RadiativeTransferPerformanceThresholds                                |
// [64..65] n_streams                  : u16                                                                   |
// [66..66] scattering                 : ScatteringMode                                                        |
// [67..67] use_spherical_correction   : bool                                                                  |
// [68..68] integrate_source_function  : bool                                                                  |
// [69..69] renorm_phase_function      : bool                                                                  |
// [70..71] padding                    : 2 B                                                                   |
//                                                                                                             |
// unused bits: 16 padding + 27 enum/bool-storage slack = 43 bits                                              |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 72 B (0.070 KiB); total = per instance * live instance count                      |
pub const RadiativeTransferControls = struct {
    scattering: ScatteringMode = .multiple,
    n_streams: u16 = 16,
    performance_thresholds: RadiativeTransferPerformanceThresholds = .{},
    use_spherical_correction: bool = false,
    integrate_source_function: bool = true,
    renorm_phase_function: bool = true,

    pub fn nGauss(self: RadiativeTransferControls) u16 {
        // RadiativeTransferControls.nGauss -------------------------------------------------------------------|
        // LABOS stores streams as paired up/down Gaussian directions.                                         |
        // ----------------------------------------------------------------------------------------------------|

        return self.n_streams / 2;
    }

    pub fn validate(self: RadiativeTransferControls) PrepareError!void {
        // RadiativeTransferControls.validate -----------------------------------------------------------------|
        // Reject stream counts that do not have Gauss-Legendre tables in the LABOS basis module.              |
        // Threshold validation stays delegated to the nested threshold block.                                 |
        // ----------------------------------------------------------------------------------------------------|

        const even_minimum_streams = self.n_streams >= 4 and (self.n_streams % 2) == 0;
        if (!even_minimum_streams) return error.UnsupportedRadiativeTransferControls;

        switch (self.nGauss()) {
            2, 3, 4, 8, 10 => {},
            else => return error.UnsupportedRadiativeTransferControls,
        }

        try self.performance_thresholds.validate();
    }

    pub fn resolvedNumOrdersMax(self: RadiativeTransferControls, scattering_optical_depth: f64) u16 {
        // RadiativeTransferControls.resolvedNumOrdersMax -----------------------------------------------------|
        // Forward the order-cap decision to the threshold block.                                              |
        // ----------------------------------------------------------------------------------------------------|

        return self.performance_thresholds.resolvedNumOrdersMax(scattering_optical_depth);
    }

    pub fn supermatrixSize(self: RadiativeTransferControls) u32 {
        // RadiativeTransferControls.supermatrixSize ----------------------------------------------------------|
        // LABOS adds the viewing and solar streams to the Gaussian stream count.                              |
        // ----------------------------------------------------------------------------------------------------|

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
// ------------------------------------------------------------------------------------------------------------|

pub const DerivativeMode = SceneModel.DerivativeMode;

// SolveConfig ------------------------------------------------------------------------------------------------|
// Prepared solve controls passed into the RTM solve. Derivative selection stays beside the RTM controls       |
// so execute can choose the LABOS path and the requested Jacobian values together.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..71] rtm_controls          : RadiativeTransferControls                                                  |
// [72..72] derivative_mode       : DerivativeMode                                                             |
// [73..73] derivative_state_mask : StateMask                                                                  |
// [74..79] padding               : 6 B                                                                        |
//                                                                                                             |
// unused bits: 48 padding + 7 enum-storage slack = 55 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 80 B (0.078 KiB); total = per instance * live instance count                      |
pub const SolveConfig = struct {
    derivative_mode: DerivativeMode = .none,
    derivative_state_mask: jacobian.StateMask = jacobian.all_states_mask,
    rtm_controls: RadiativeTransferControls = .{},
};
// ------------------------------------------------------------------------------------------------------------|

// LayerInput -------------------------------------------------------------------------------------------------|
// One prepared atmospheric layer for LABOS. Optical-depth totals and Jacobian values are already built by     |
// optical-property preparation; RTM code consumes this without file I/O or text parsing.                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 176 B (0.172 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] gas_absorption_optical_depth       : f64                                                         |
// [  8.. 15] gas_scattering_optical_depth       : f64                                                         |
// [ 16.. 23] cia_optical_depth                  : f64                                                         |
// [ 24.. 31] aerosol_optical_depth              : f64                                                         |
// [ 32.. 39] aerosol_scattering_optical_depth   : f64                                                         |
// [ 40.. 47] optical_depth                      : f64                                                         |
// [ 48.. 55] scattering_optical_depth           : f64                                                         |
// [ 56.. 63] single_scatter_albedo              : f64                                                         |
// [ 64.. 87] optical_depth_jacobian             : Vector                                                      |
// [ 88..111] scattering_optical_depth_jacobian  : Vector                                                      |
// [112..135] single_scatter_albedo_jacobian     : Vector                                                      |
// [136..143] solar_mu                           : f64                                                         |
// [144..151] view_mu                            : f64                                                         |
// [152..175] phase                              : LayerPhase                                                  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// inline arrays: 3 Jacobian vectors reserve 72 B inside each instance                                         |
// out-of-line: phase points at shared prepared phase-coefficient storage                                      |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 176 B (0.172 KiB); total also includes referenced phase storage                   |
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
// ------------------------------------------------------------------------------------------------------------|

// SourceInterfaceInput ---------------------------------------------------------------------------------------|
// Source data at one interface between layers. Explicit RTM quadrature can provide source weights;            |
// otherwise root.zig builds weights from neighboring layer scattering data.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] source_weight          : f64                                                                       |
// [ 8..15] rtm_weight             : f64                                                                       |
// [16..23] ksca_above             : f64                                                                       |
// [24..47] phase_above            : LayerPhase                                                                |
// [48..55] phase_max_index_above  : usize                                                                     |
// [56..63] phase_max_index_below  : usize                                                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// out-of-line: phase_above points at shared prepared phase-coefficient storage                                |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 64 B (0.062 KiB); total also includes referenced phase storage                    |
pub const SourceInterfaceInput = struct {
    source_weight: f64 = 0.0,
    rtm_weight: f64 = 0.0,
    ksca_above: f64 = 0.0,
    phase_above: LayerPhase = .{},
    phase_max_index_above: usize = 0,
    phase_max_index_below: usize = 0,

    pub fn effectiveWeight(self: SourceInterfaceInput) f64 {
        // SourceInterfaceInput.effectiveWeight ---------------------------------------------------------------|
        // Use explicit RTM quadrature weighting when it carries a scattering coefficient; otherwise use the   |
        // source weight built from layer scattering optical depth.                                            |
        //                                                                                                     |
        // math                                                                                                |
        //   explicit source weight = RTM quadrature weight * k_sca_above                                      |
        // ----------------------------------------------------------------------------------------------------|

        if (self.rtm_weight > 0.0 and self.ksca_above > 0.0) {
            return self.rtm_weight * self.ksca_above;
        }

        return self.source_weight;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// RtmQuadratureLevel -----------------------------------------------------------------------------------------|
// One altitude quadrature level used by source integration. Phase fields store weights so each level          |
// does not need its own full phase-coefficient row.                                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] altitude_km                : f64                                                                   |
// [ 8..15] weight                     : f64                                                                   |
// [16..23] ksca                       : f64                                                                   |
// [24..31] aerosol_ksca_above_per_km  : f64                                                                   |
// [32..39] aerosol_ksca_below_per_km  : f64                                                                   |
// [40..47] aerosol_ksca_jacobian      : f64                                                                   |
// [48..55] phase_aerosol_weight       : f64                                                                   |
// [56..63] phase_rayleigh2_weight     : f64                                                                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 64 B (0.062 KiB); total = per instance * live instance count                      |
pub const RtmQuadratureLevel = struct {
    altitude_km: f64 = 0.0,
    weight: f64 = 0.0,
    ksca: f64 = 0.0,
    aerosol_ksca_above_per_km: f64 = 0.0,
    aerosol_ksca_below_per_km: f64 = 0.0,
    aerosol_ksca_jacobian: f64 = 0.0,
    phase_aerosol_weight: f64 = 0.0,
    phase_rayleigh2_weight: f64 = 0.0,

    pub fn weightedScattering(self: *const RtmQuadratureLevel) f64 {
        // RtmQuadratureLevel.weightedScattering --------------------------------------------------------------|
        // Source contribution from this quadrature level before phase rows and radiation fields are applied.  |
        //                                                                                                     |
        // math                                                                                                |
        //   weighted scattering source = quadrature_weight * k_sca                                            |
        // ----------------------------------------------------------------------------------------------------|

        return self.weight * self.ksca;
    }

    pub fn setPhaseMixture(
        self: *RtmQuadratureLevel,
        rayleigh_phase_coefficient2: f64,
        gas_ksca: f64,
        aerosol_ksca: f64,
    ) void {
        // RtmQuadratureLevel.setPhaseMixture -----------------------------------------------------------------|
        // Store the gas/aerosol phase mix for this quadrature level.                                          |
        //                                                                                                     |
        // math                                                                                                |
        //   phase mixture                                                                                     |
        //     = (aerosol_ksca / total_ksca) * aerosol_phase                                                   |
        //       + (gas_ksca / total_ksca) * Rayleigh2                                                         |
        // ----------------------------------------------------------------------------------------------------|

        const total = gas_ksca + aerosol_ksca;
        if (total <= 0.0) {
            self.phase_aerosol_weight = 0.0;
            self.phase_rayleigh2_weight = rayleigh_phase_coefficient2;
            return;
        }
        const inv_total = 1.0 / total;

        self.phase_aerosol_weight = aerosol_ksca * inv_total;
        self.phase_rayleigh2_weight = gas_ksca * inv_total * rayleigh_phase_coefficient2;
    }
};
// ------------------------------------------------------------------------------------------------------------|

const default_aerosol_phase_coefficients = phase_functions.zeroPhaseCoefficients();

// RtmQuadratureGrid ------------------------------------------------------------------------------------------|
// Borrowed quadrature grid for source integration. Levels are owned by prepared input; this view only         |
// carries the slice and aerosol phase row used to build mixed phase rows.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] levels                     : []const RtmQuadratureLevel                                            |
// [16..23] aerosol_phase_coefficients : *const [phase_coefficient_count]f64                                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// out-of-line: levels and aerosol_phase_coefficients point at prepared storage                                |
// footprint: per instance = 24 B (0.023 KiB); total also includes referenced storage                          |
pub const RtmQuadratureGrid = struct {
    levels: []const RtmQuadratureLevel = &.{},
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64 = &default_aerosol_phase_coefficients,

    pub fn isValidFor(self: RtmQuadratureGrid, layer_count: usize) bool {
        // RtmQuadratureGrid.isValidFor -----------------------------------------------------------------------|
        // A quadrature grid is usable when it has exactly one interface level per layer boundary.             |
        // ----------------------------------------------------------------------------------------------------|

        return self.levels.len == layer_count + 1;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// PseudoSphericalSample --------------------------------------------------------------------------------------|
// One support-grid sample for pseudo-spherical direct-beam attenuation.                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] altitude_km    : f64                                                                               |
// [ 8..15] thickness_km   : f64                                                                               |
// [16..23] optical_depth  : f64                                                                               |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count                      |
pub const PseudoSphericalSample = struct {
    altitude_km: f64 = 0.0,
    thickness_km: f64 = 0.0,
    optical_depth: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

// PseudoSphericalGrid ----------------------------------------------------------------------------------------|
// Borrowed support grid for curved direct-beam paths. level_sample_starts marks where each model level's      |
// samples start, so attenuation builders can find the support samples without parsing input text.             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] samples             : []const PseudoSphericalSample                                                |
// [16..31] level_sample_starts : []const usize                                                                |
// [32..47] level_altitudes_km  : []const f64                                                                  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// out-of-line: all slice fields carry referenced storage                                                      |
// footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage                          |
pub const PseudoSphericalGrid = struct {
    samples: []const PseudoSphericalSample = &.{},
    level_sample_starts: []const usize = &.{},
    level_altitudes_km: []const f64 = &.{},

    pub fn isValidFor(self: PseudoSphericalGrid, layer_count: usize) bool {
        // PseudoSphericalGrid.isValidFor ---------------------------------------------------------------------|
        // Check only the array shapes needed by RTM attenuation. Input parsing already checked what the       |
        // support grid means.                                                                                 |
        //                                                                                                     |
        // required shape                                                                                      |
        //   non-empty samples                                                                                 |
        //   one start offset per model level                                                                  |
        //   optional level altitudes with the same level count                                                |
        //   sample offsets increase and end at samples.len                                                    |
        // ----------------------------------------------------------------------------------------------------|

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
// ------------------------------------------------------------------------------------------------------------|

// ForwardInput -----------------------------------------------------------------------------------------------|
// Prepared RTM input for one high-resolution wavelength sample. Scalar fields support simple routes;          |
// layer and source slices carry the layer-resolved LABOS path.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 288 B (0.281 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] wavelength_nm                    : f64                                                           |
// [  8.. 15] spectral_weight                  : f64                                                           |
// [ 16.. 23] air_mass_factor                  : f64                                                           |
// [ 24.. 31] mu0                              : f64                                                           |
// [ 32.. 39] muv                              : f64                                                           |
// [ 40.. 47] surface_albedo                   : f64                                                           |
// [ 48.. 55] gas_absorption_optical_depth     : f64                                                           |
// [ 56.. 63] gas_scattering_optical_depth     : f64                                                           |
// [ 64.. 71] cia_optical_depth                : f64                                                           |
// [ 72.. 79] aerosol_optical_depth            : f64                                                           |
// [ 80.. 87] aerosol_scattering_optical_depth : f64                                                           |
// [ 88.. 95] optical_depth                    : f64                                                           |
// [ 96..103] single_scatter_albedo            : f64                                                           |
// [104..111] relative_azimuth_rad             : f64                                                           |
// [112..127] layers                           : []const LayerInput                                            |
// [128..143] source_interfaces                : []const SourceInterfaceInput                                  |
// [144..167] rtm_quadrature                   : RtmQuadratureGrid                                             |
// [168..215] pseudo_spherical_grid            : PseudoSphericalGrid                                           |
// [216..287] rtm_controls                     : RadiativeTransferControls                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// out-of-line: layer/source slices and grid structs carry referenced storage                                  |
// cache span: 5 cache lines at 64 B per line                                                                  |
// footprint: per instance = 288 B (0.281 KiB); total also includes referenced layer/source storage            |
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
// ------------------------------------------------------------------------------------------------------------|

// ForwardResult ----------------------------------------------------------------------------------------------|
// RTM result for one forward sample. Jacobian is null when derivative_mode is none.                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] toa_reflectance_factor : f64                                                                       |
// [ 8..39] jacobian               : ?Vector                                                                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 40 B (0.039 KiB); total = per instance * live instance count                      |
pub const ForwardResult = struct {
    toa_reflectance_factor: f64,
    jacobian: ?jacobian.Vector,
};
// ------------------------------------------------------------------------------------------------------------|

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
    // prepareSolveConfig -------------------------------------------------------------------------------------|
    // Validate public RTM controls before callers use the prepared path.                                      |
    // --------------------------------------------------------------------------------------------------------|

    try config.rtm_controls.validate();
    return config;
}

pub fn executePrepared(
    allocator: std.mem.Allocator,
    rtm_config: SolveConfig,
    input: ForwardInput,
) ExecuteError!ForwardResult {
    // executePrepared ----------------------------------------------------------------------------------------|
    // Prepared solve without caller-owned LABOS scratch memory.                                               |
    // --------------------------------------------------------------------------------------------------------|

    return executePreparedWithLabosWorkspace(allocator, rtm_config, input, null);
}

pub fn executePreparedWithLabosWorkspace(
    allocator: std.mem.Allocator,
    rtm_config: SolveConfig,
    input: ForwardInput,
    workspace: ?*labos.Workspace,
) ExecuteError!ForwardResult {
    // executePreparedWithLabosWorkspace ----------------------------------------------------------------------|
    // Prepared solve that can reuse caller-owned LABOS scratch memory across wavelength samples.              |
    // The transport solve stays under labos.executeWithWorkspace.                                             |
    // --------------------------------------------------------------------------------------------------------|

    return labos.executeWithWorkspace(allocator, rtm_config, input, workspace);
}

pub fn execute(
    allocator: std.mem.Allocator,
    config: SolveConfig,
    input: ForwardInput,
) ExecuteError!ForwardResult {
    // execute ------------------------------------------------------------------------------------------------|
    // Public one-shot path. Validate controls, then run the prepared path without a saved LABOS workspace.    |
    // --------------------------------------------------------------------------------------------------------|

    const rtm_config = try prepareSolveConfig(config);
    return executePrepared(allocator, rtm_config, input);
}

pub fn sourceInterfaceFromLayers(
    layers: []const LayerInput,
    ilevel: usize,
) SourceInterfaceInput {
    // sourceInterfaceFromLayers ------------------------------------------------------------------------------|
    // Build one source interface from neighboring layer data when explicit RTM quadrature is absent.          |
    //                                                                                                         |
    // fallback rule                                                                                           |
    //   internal interface : use scattering optical depth of the layer starting at this level                 |
    //   top boundary       : use half the scattering optical depth of the top-adjacent layer                  |
    //                                                                                                         |
    // phase data                                                                                              |
    //   phase_above and phase_max_index_above come from the layer above this interface                        |
    //   phase_max_index_below is zero at the top boundary                                                     |
    // --------------------------------------------------------------------------------------------------------|

    if (layers.len == 0) return .{};

    const above_index = @min(ilevel, layers.len - 1);
    const phase_max_index_below = if (ilevel > 0) layers[ilevel - 1].phase.maxIndex() else 0;

    const source_weight = if (ilevel < layers.len)
        @max(layers[ilevel].scattering_optical_depth, 0.0)
    else
        0.5 * @max(layers[above_index].scattering_optical_depth, 0.0);

    return .{
        .source_weight = source_weight,
        .ksca_above = @max(layers[above_index].scattering_optical_depth, 0.0),
        .phase_above = layers[above_index].phase,
        .phase_max_index_above = layers[above_index].phase.maxIndex(),
        .phase_max_index_below = phase_max_index_below,
    };
}

pub fn fillSourceInterfacesFromLayers(
    layers: []const LayerInput,
    source_interfaces: []SourceInterfaceInput,
) void {
    // fillSourceInterfacesFromLayers -------------------------------------------------------------------------|
    // Fill a caller-owned source-interface array from layer data.                                             |
    //                                                                                                         |
    // The destination must have one slot per level. A mismatched destination cannot match the layer grid,     |
    // so this helper leaves it unchanged.                                                                     |
    // --------------------------------------------------------------------------------------------------------|

    if (layers.len == 0 or source_interfaces.len != layers.len + 1) return;

    for (source_interfaces, 0..) |*source_interface, ilevel| {
        source_interface.* = sourceInterfaceFromLayers(layers, ilevel);
    }
}
