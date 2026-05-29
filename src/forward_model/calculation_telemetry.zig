const build_options = @import("build_options");
const sink = @import("calculation_telemetry_sink");

// instrumentation: calculation telemetry facade
// captures: selected math states
// why: compile data capture out unless the Parquet harness opts in.
pub const requested: bool = if (@hasDecl(build_options, "enable_calculation_telemetry"))
    build_options.enable_calculation_telemetry
else
    false;

pub const enabled: bool = requested and sink.available;
pub const Stage = sink.Stage;
pub const Context = sink.Context;

pub inline fn setContext(context: Context) void {
    if (comptime !enabled) return;
    sink.setContext(context);
}

pub inline fn currentContext() Context {
    if (comptime !enabled) return .{};
    return sink.currentContext();
}

pub inline fn clearContext() void {
    if (comptime !enabled) return;
    sink.clearContext();
}

// instrumentation: calculation telemetry
// captures: integration kernel counts
// why: quantify spectral sampling fan-out.
pub inline fn wavelengthSamplingPlan(
    row_count: usize,
    radiance_integrated_rows: usize,
    irradiance_integrated_rows: usize,
    radiance_sample_count: usize,
    irradiance_sample_count: usize,
    side_sample_count: usize,
    max_kernel_sample_count: usize,
) void {
    if (comptime !enabled) return;
    sink.wavelengthSamplingPlan(
        row_count,
        radiance_integrated_rows,
        irradiance_integrated_rows,
        radiance_sample_count,
        irradiance_sample_count,
        side_sample_count,
        max_kernel_sample_count,
    );
}

// instrumentation: calculation telemetry
// captures: unique forward-cache misses
// why: measure wavelength reuse from integration plans.
pub inline fn forwardMissPlan(row_count: usize, sample_index_count: usize, miss_count: usize) void {
    if (comptime !enabled) return;
    sink.forwardMissPlan(row_count, sample_index_count, miss_count);
}

// instrumentation: calculation telemetry
// captures: reflectance denominator clamps and maxima
// why: detect unstable output assembly.
pub inline fn reflectanceAssembly(
    sample_count: usize,
    denominator_clamp_count: usize,
    min_denominator: f64,
    max_reflectance: f64,
) void {
    if (comptime !enabled) return;
    sink.reflectanceAssembly(sample_count, denominator_clamp_count, min_denominator, max_reflectance);
}

// instrumentation: calculation telemetry
// captures: Jacobian column sums and maxima
// why: find weak derivative signals for OE pruning.
pub inline fn jacobianColumn(state_index: usize, sum: f64, mean: f64, max_abs: f64) void {
    if (comptime !enabled) return;
    sink.jacobianColumn(state_index, sum, mean, max_abs);
}

// instrumentation: calculation telemetry
// captures: LABOS layer-doubling threshold inputs
// why: study which layer/Fourier coordinates need doubling.
pub inline fn labosLayerDecision(
    i_fourier: usize,
    layer_index: usize,
    phase_max_index: usize,
    optical_depth: f64,
    single_scatter_albedo: f64,
    max_beta_eff: f64,
    effective_scattering_depth: f64,
    threshold_doubl: f64,
    start_optical_depth: f64,
    doubling_count: usize,
    uses_doubling: bool,
) void {
    if (comptime !enabled) return;
    sink.labosLayerDecision(
        i_fourier,
        layer_index,
        phase_max_index,
        optical_depth,
        single_scatter_albedo,
        max_beta_eff,
        effective_scattering_depth,
        threshold_doubl,
        start_optical_depth,
        doubling_count,
        uses_doubling,
    );
}

// instrumentation: calculation telemetry
// captures: q-series skip margin per doubling step
// why: identify coordinates where Q=(I-RR)^-1-I is negligible.
pub inline fn labosDoublingStep(
    i_fourier: usize,
    layer_index: usize,
    phase_max_index: usize,
    doubling_step_index: usize,
    trace_r: f64,
    trace_t: f64,
    threshold_mul: f64,
    qseries_is_zero: bool,
) void {
    if (comptime !enabled) return;
    sink.labosDoublingStep(
        i_fourier,
        layer_index,
        phase_max_index,
        doubling_step_index,
        trace_r,
        trace_t,
        threshold_mul,
        qseries_is_zero,
    );
}

// instrumentation: calculation telemetry
// captures: downstream R-D/T-U/T-D product gates
// why: test if q-zero branches imply more matrix work can be skipped.
pub inline fn labosDoublingDownstreamGates(
    i_fourier: usize,
    layer_index: usize,
    phase_max_index: usize,
    doubling_step_index: usize,
    qseries_is_zero: bool,
    trace_r: f64,
    trace_t: f64,
    trace_d: f64,
    trace_u: f64,
    threshold_mul: f64,
    rd_nonzero: bool,
    tu_nonzero: bool,
    td_nonzero: bool,
) void {
    if (comptime !enabled) return;
    sink.labosDoublingDownstreamGates(
        i_fourier,
        layer_index,
        phase_max_index,
        doubling_step_index,
        qseries_is_zero,
        trace_r,
        trace_t,
        trace_d,
        trace_u,
        threshold_mul,
        rd_nonzero,
        tu_nonzero,
        td_nonzero,
    );
}

// instrumentation: calculation telemetry
// captures: scattering-order stop margins
// why: tune order convergence without losing reflectance.
pub inline fn ordersConvergence(
    iteration_count: usize,
    max_iteration_count: usize,
    max_outgoing_upward: f64,
    threshold: f64,
    returned_initial: bool,
    hit_iteration_cap: bool,
) void {
    if (comptime !enabled) return;
    sink.ordersConvergence(
        iteration_count,
        max_iteration_count,
        max_outgoing_upward,
        threshold,
        returned_initial,
        hit_iteration_cap,
    );
}

// instrumentation: calculation telemetry
// captures: Fourier term contribution and tail stop
// why: locate late terms with negligible reflectance.
pub inline fn fourierContribution(
    i_fourier: usize,
    fourier_weight: f64,
    term_reflectance: f64,
    weighted_reflectance: f64,
    tail_threshold: f64,
    tail_break: bool,
) void {
    if (comptime !enabled) return;
    sink.fourierContribution(
        i_fourier,
        fourier_weight,
        term_reflectance,
        weighted_reflectance,
        tail_threshold,
        tail_break,
    );
}

// instrumentation: calculation telemetry
// captures: raw/clamped LABOS reflectance and Jacobian norm
// why: detect suspicious outputs and weak derivatives.
pub inline fn labosResult(raw_reflectance: f64, clamped_reflectance: f64, jacobian_norm1: f64) void {
    if (comptime !enabled) return;
    sink.labosResult(raw_reflectance, clamped_reflectance, jacobian_norm1);
}
