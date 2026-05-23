pub const available = false;

pub inline fn wavelengthSamplingPlan(
    row_count: usize,
    radiance_integrated_rows: usize,
    irradiance_integrated_rows: usize,
    radiance_sample_count: usize,
    irradiance_sample_count: usize,
    side_sample_count: usize,
    max_kernel_sample_count: usize,
) void {
    _ = row_count;
    _ = radiance_integrated_rows;
    _ = irradiance_integrated_rows;
    _ = radiance_sample_count;
    _ = irradiance_sample_count;
    _ = side_sample_count;
    _ = max_kernel_sample_count;
}

pub inline fn forwardMissPlan(row_count: usize, sample_index_count: usize, miss_count: usize) void {
    _ = row_count;
    _ = sample_index_count;
    _ = miss_count;
}

pub inline fn reflectanceAssembly(
    sample_count: usize,
    denominator_clamp_count: usize,
    min_denominator: f64,
    max_reflectance: f64,
) void {
    _ = sample_count;
    _ = denominator_clamp_count;
    _ = min_denominator;
    _ = max_reflectance;
}

pub inline fn jacobianColumn(state_index: usize, sum: f64, mean: f64, max_abs: f64) void {
    _ = state_index;
    _ = sum;
    _ = mean;
    _ = max_abs;
}

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
    _ = i_fourier;
    _ = layer_index;
    _ = phase_max_index;
    _ = optical_depth;
    _ = single_scatter_albedo;
    _ = max_beta_eff;
    _ = effective_scattering_depth;
    _ = threshold_doubl;
    _ = start_optical_depth;
    _ = doubling_count;
    _ = uses_doubling;
}

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
    _ = i_fourier;
    _ = layer_index;
    _ = phase_max_index;
    _ = doubling_step_index;
    _ = trace_r;
    _ = trace_t;
    _ = threshold_mul;
    _ = qseries_is_zero;
}

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
    _ = i_fourier;
    _ = layer_index;
    _ = phase_max_index;
    _ = doubling_step_index;
    _ = qseries_is_zero;
    _ = trace_r;
    _ = trace_t;
    _ = trace_d;
    _ = trace_u;
    _ = threshold_mul;
    _ = rd_nonzero;
    _ = tu_nonzero;
    _ = td_nonzero;
}

pub inline fn ordersConvergence(
    iteration_count: usize,
    max_iteration_count: usize,
    max_outgoing_upward: f64,
    threshold: f64,
    returned_initial: bool,
    hit_iteration_cap: bool,
) void {
    _ = iteration_count;
    _ = max_iteration_count;
    _ = max_outgoing_upward;
    _ = threshold;
    _ = returned_initial;
    _ = hit_iteration_cap;
}

pub inline fn fourierContribution(
    i_fourier: usize,
    fourier_weight: f64,
    term_reflectance: f64,
    weighted_reflectance: f64,
    tail_threshold: f64,
    tail_break: bool,
) void {
    _ = i_fourier;
    _ = fourier_weight;
    _ = term_reflectance;
    _ = weighted_reflectance;
    _ = tail_threshold;
    _ = tail_break;
}

pub inline fn labosResult(raw_reflectance: f64, clamped_reflectance: f64, jacobian_norm1: f64) void {
    _ = raw_reflectance;
    _ = clamped_reflectance;
    _ = jacobian_norm1;
}
