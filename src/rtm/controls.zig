const std = @import("std");

const jacobian_states = @import("jacobian_states.zig");

// controls.zig ---------------------------------------------------------------------------------------------- |
// Validated RTM control rows for the O2 A LABOS transport implementation.                                     |
//                                                                                                             |
//   The Jacobian mask field uses the state order in `rtm/jacobian_states.zig`.                                |
// ------------------------------------------------------------------------------------------------------------|

pub const PrepareError = error{
    UnsupportedDerivativeMode,
    UnsupportedRadiativeTransferControls,
};

// ScatteringMode ---------------------------------------------------------------------------------------------|
// LABOS scattering order route.                                                                               |
//                                                                                                             |
// none     : direct surface-reflection route                                                                  |
// single   : first scattering order only                                                                      |
// multiple : full multiple-scattering order loop                                                              |
// ------------------------------------------------------------------------------------------------------------|
pub const ScatteringMode = enum(u2) {
    none = 0,
    single = 1,
    multiple = 2,
};
// ------------------------------------------------------------------------------------------------------------|

// DerivativeMode ---------------------------------------------------------------------------------------------|
// Prepared derivative route selector.                                                                         |
//                                                                                                             |
// none            : reflectance only                                                                          |
// semi_analytical : same-solve Jacobian propagation for the active state mask                                 |
// ------------------------------------------------------------------------------------------------------------|
pub const DerivativeMode = enum(u1) {
    none = 0,
    semi_analytical = 1,
};
// ------------------------------------------------------------------------------------------------------------|

// PerformanceThresholds --------------------------------------------------------------------------------------|
// LABOS limits and cutoffs prepared from input controls.                                                      |
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
// [60..63] padding                             : 4 B                                                          |
//                                                                                                             |
// unused bits: 32 padding                                                                                     |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 64 B (0.062 KiB); total = per instance * live instance count                      |
pub const PerformanceThresholds = struct {
    num_orders_max: u16 = 0,
    fourier_floor_scalar: u16 = 2,
    fourier_order_cap: ?u16 = null,
    aerosol_tangent_order_cap: ?u16 = null,
    fourier_tail_reflectance_epsilon: f64 = 3.0e-14,
    threshold_conv_first: f64 = 1.0e-6,
    threshold_conv_mult: f64 = 1.0e-4,
    threshold_doubl: f64 = 0.1,
    threshold_mul: f64 = 1.0e-12,
    phase_function_truncation_threshold: f64 = 1.0e-8,

    pub fn validate(self: PerformanceThresholds) PrepareError!void {
        // validate ------------------------------------------------------------------------------------------ |
        // Reject zero, negative, NaN, and infinite thresholds before LABOS uses them as divisors or gates.    |
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

    pub fn resolvedNumOrdersMax(self: PerformanceThresholds, scattering_optical_depth: f64) u16 {
        // resolvedNumOrdersMax ------------------------------------------------------------------------------ |
        // Use a non-zero caller cap directly; otherwise keep the optical-depth rule.                          |
        //                                                                                                     |
        // math                                                                                                |
        //   default cap = clamp(max(scattering_optical_depth, 0) + 15, 1, max_u16)                            |
        // ----------------------------------------------------------------------------------------------------|
        if (self.num_orders_max != 0) return self.num_orders_max;

        const heuristic = @max(scattering_optical_depth, 0.0) + 15.0;
        return @intFromFloat(std.math.clamp(heuristic, 1.0, @as(f64, std.math.maxInt(u16))));
    }

    pub fn cappedFourierMax(self: PerformanceThresholds, resolved_fourier_max: usize) usize {
        // cappedFourierMax ---------------------------------------------------------------------------------- |
        // Apply the optional Fourier cap after phase data reports the maximum available Fourier term.         |
        // ----------------------------------------------------------------------------------------------------|
        if (self.fourier_order_cap) |cap| return @min(resolved_fourier_max, @as(usize, cap));
        return resolved_fourier_max;
    }

    pub fn shouldEvaluateAerosolTangent(self: PerformanceThresholds, fourier_index: usize) bool {
        // shouldEvaluateAerosolTangent ---------------------------------------------------------------------- |
        // Keep aerosol tangent terms through the optional inclusive Fourier cap.                              |
        // ----------------------------------------------------------------------------------------------------|
        if (self.aerosol_tangent_order_cap) |cap| return fourier_index <= @as(usize, cap);
        return true;
    }

    pub const o2a_default = PerformanceThresholds{
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
    };
};
// ------------------------------------------------------------------------------------------------------------|

// TransportControls ------------------------------------------------------------------------------------------|
// RTM controls after parsing and before wavelength-worker execution.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 72 B (0.070 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..63] performance_thresholds     : PerformanceThresholds                                                 |
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
pub const TransportControls = struct {
    scattering: ScatteringMode = .multiple,
    n_streams: u16 = 16,
    performance_thresholds: PerformanceThresholds = .{},
    use_spherical_correction: bool = false,
    integrate_source_function: bool = true,
    renorm_phase_function: bool = true,

    pub fn nGauss(self: TransportControls) u16 {
        // nGauss -------------------------------------------------------------------------------------------- |
        // LABOS stores streams as paired up/down Gaussian directions.                                         |
        // ----------------------------------------------------------------------------------------------------|
        return self.n_streams / 2;
    }

    pub fn validate(self: TransportControls) PrepareError!void {
        // validate ------------------------------------------------------------------------------------------ |
        // Validate the Gauss-Legendre stream count before worker solves rely on precomputed LABOS basis rows. |
        // ----------------------------------------------------------------------------------------------------|
        const even_minimum_streams = self.n_streams >= 4 and (self.n_streams % 2) == 0;
        if (!even_minimum_streams) return error.UnsupportedRadiativeTransferControls;

        switch (self.nGauss()) {
            2, 3, 4, 8, 10 => {},
            else => return error.UnsupportedRadiativeTransferControls,
        }

        try self.performance_thresholds.validate();
    }

    pub fn resolvedNumOrdersMax(self: TransportControls, scattering_optical_depth: f64) u16 {
        // resolvedNumOrdersMax ------------------------------------------------------------------------------ |
        // Forward the scattering-order cap decision to the threshold block.                                   |
        // ----------------------------------------------------------------------------------------------------|
        return self.performance_thresholds.resolvedNumOrdersMax(scattering_optical_depth);
    }

    pub const default_vendor = TransportControls{
        .scattering = .multiple,
        .n_streams = 16,
        .performance_thresholds = .{},
        .use_spherical_correction = false,
        .integrate_source_function = true,
        .renorm_phase_function = true,
    };
};
// ------------------------------------------------------------------------------------------------------------|

// SolveConfig ------------------------------------------------------------------------------------------------|
// Prepared controls passed into the transport solve.                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..71] controls              : TransportControls                                                          |
// [72..72] derivative_mode       : DerivativeMode                                                             |
// [73..73] derivative_state_mask : StateMask                                                                  |
// [74..79] padding               : 6 B                                                                        |
//                                                                                                             |
// unused bits: 48 padding + 7 enum-storage slack = 55 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 80 B (0.078 KiB); total = per instance * live instance count                      |
pub const SolveConfig = struct {
    derivative_mode: DerivativeMode = .none,
    derivative_state_mask: jacobian_states.StateMask = jacobian_states.all_states_mask,
    controls: TransportControls = .{},
};
// ------------------------------------------------------------------------------------------------------------|

pub fn prepareSolveConfig(config: SolveConfig) PrepareError!SolveConfig {
    // prepareSolveConfig ------------------------------------------------------------------------------------ |
    // Last setup-side validation before wavelength workers call the transport solve with prepared controls.   |
    // --------------------------------------------------------------------------------------------------------|
    try config.controls.validate();

    return .{
        .derivative_mode = config.derivative_mode,
        .derivative_state_mask = jacobian_states.sanitizedMask(config.derivative_state_mask),
        .controls = config.controls,
    };
}
