const std = @import("std");
const build_options = @import("build_options");

pub const enabled: bool = if (@hasDecl(build_options, "enable_labos_trace"))
    build_options.enable_labos_trace
else
    false;

pub const max_workers: usize = 64;
pub const RunRef = if (enabled) ?*Run else void;
pub const WorkerRef = if (enabled) ?*Worker else void;

comptime {
    if (!enabled) {
        if (@sizeOf(RunRef) != 0) @compileError("disabled trace run references must remain zero-sized");
        if (@sizeOf(WorkerRef) != 0) @compileError("disabled trace worker references must remain zero-sized");
    }
}

pub const Section = enum(u8) {
    simulate_wavelength_sampling,
    simulate_forward_miss_collection,
    simulate_forward_prefetch_wall,
    simulate_radiance_cache_integration,
    simulate_radiance_convolution,
    simulate_radiance_postprocess,
    simulate_irradiance_sampling,
    simulate_irradiance_convolution,
    simulate_irradiance_postprocess,
    simulate_ring_correction,
    simulate_reflectance_assembly,
    simulate_noise_sigma,
    simulate_jacobian_processing,
    forward_input,
    forward_input_carrier_init,
    forward_input_layers,
    forward_input_rtm_quadrature,
    forward_input_source_interfaces,
    forward_input_pseudo_spherical,
    labos_execute,
    labos_fourier_total,
    plm_basis,
    rt_layer_build,
    rt_layer_phase_matrix,
    rt_layer_effective_scattering,
    rt_layer_initial_exponential,
    rt_layer_single_scatter,
    rt_layer_phase_renormalization,
    rt_layer_doubling,
    orders_total,
    orders_initial_sources,
    orders_initial_transport,
    orders_multiple_loop,
    orders_local_down,
    orders_local_up,
    orders_transport,
    orders_accumulate,
    reflectance_integral,

    pub fn name(self: Section) []const u8 {
        return switch (self) {
            .simulate_wavelength_sampling => "simulate.wavelength_sampling",
            .simulate_forward_miss_collection => "simulate.forward_miss_collection",
            .simulate_forward_prefetch_wall => "simulate.forward_prefetch_wall",
            .simulate_radiance_cache_integration => "simulate.radiance_cache_integration",
            .simulate_radiance_convolution => "simulate.radiance_convolution",
            .simulate_radiance_postprocess => "simulate.radiance_postprocess",
            .simulate_irradiance_sampling => "simulate.irradiance_sampling",
            .simulate_irradiance_convolution => "simulate.irradiance_convolution",
            .simulate_irradiance_postprocess => "simulate.irradiance_postprocess",
            .simulate_ring_correction => "simulate.ring_correction",
            .simulate_reflectance_assembly => "simulate.reflectance_assembly",
            .simulate_noise_sigma => "simulate.noise_sigma",
            .simulate_jacobian_processing => "simulate.jacobian_processing",
            .forward_input => "forward_sample.configured_forward_input",
            .forward_input_carrier_init => "forward_input.carrier_init",
            .forward_input_layers => "forward_input.layers",
            .forward_input_rtm_quadrature => "forward_input.rtm_quadrature",
            .forward_input_source_interfaces => "forward_input.source_interfaces",
            .forward_input_pseudo_spherical => "forward_input.pseudo_spherical",
            .labos_execute => "forward_sample.labos_execute",
            .labos_fourier_total => "labos.fourier_loop",
            .plm_basis => "labos.plm_basis",
            .rt_layer_build => "labos.rt_layer_build",
            .rt_layer_phase_matrix => "labos.rt_layer.phase_matrix",
            .rt_layer_effective_scattering => "labos.rt_layer.effective_scattering",
            .rt_layer_initial_exponential => "labos.rt_layer.initial_exponential",
            .rt_layer_single_scatter => "labos.rt_layer.single_scatter",
            .rt_layer_phase_renormalization => "labos.rt_layer.phase_renormalization",
            .rt_layer_doubling => "labos.rt_layer.doubling",
            .orders_total => "labos.orders.total",
            .orders_initial_sources => "labos.orders.initial_sources",
            .orders_initial_transport => "labos.orders.initial_transport",
            .orders_multiple_loop => "labos.orders.multiple_loop",
            .orders_local_down => "labos.orders.local_down",
            .orders_local_up => "labos.orders.local_up",
            .orders_transport => "labos.orders.transport",
            .orders_accumulate => "labos.orders.accumulate",
            .reflectance_integral => "labos.reflectance_integral",
        };
    }
};

pub const section_count = @typeInfo(Section).@"enum".fields.len;

pub const Counter = enum(u8) {
    output_wavelengths,
    high_resolution_misses,
    worker_count,
    forward_samples,
    fourier_terms,
    fourier_tail_breaks,
    layer_visits,
    layer_skipped_fourier_out_of_range,
    layer_skipped_empty_optics,
    phase_matrix_builds,
    phase_coeff_terms_scanned,
    phase_coeff_terms_nonzero,
    single_scatter_r,
    single_scatter_t,
    doubled_layers,
    doubling_steps,
    doubling_qseries_skipped,
    doubling_qseries_nonzero,
    matrix_qseries,
    matrix_smul_q_product,
    matrix_smul_rd,
    matrix_smul_rd_nonzero,
    matrix_smul_tu,
    matrix_smul_tu_nonzero,
    matrix_smul_td,
    matrix_smul_td_nonzero,
    matrix_smul_add_semul3,
    matrix_semul,
    matrix_semul_add,
    matrix_mat_add_esmul,
    matrix_mat_add_esmul3,
    matrix_esmul_semul,
    matrix_esmul_semul_add,
    initial_exp_evals,
    doubling_square_evals,
    phase_renormalizations,
    orders_calls,
    orders_initial_returns,
    orders_multiple_iterations,
    dot_gauss_pair_calls,
    dot_gauss_pair_terms,
    orders_inactive_down_layers,
    orders_inactive_up_layers,

    pub fn name(self: Counter) []const u8 {
        return switch (self) {
            .output_wavelengths => "output_wavelengths",
            .high_resolution_misses => "high_resolution_misses",
            .worker_count => "worker_count",
            .forward_samples => "forward_samples",
            .fourier_terms => "fourier_terms",
            .fourier_tail_breaks => "fourier_tail_breaks",
            .layer_visits => "layer_visits",
            .layer_skipped_fourier_out_of_range => "layer_skipped_fourier_out_of_range",
            .layer_skipped_empty_optics => "layer_skipped_empty_optics",
            .phase_matrix_builds => "phase_matrix_builds",
            .phase_coeff_terms_scanned => "phase_coeff_terms_scanned",
            .phase_coeff_terms_nonzero => "phase_coeff_terms_nonzero",
            .single_scatter_r => "single_scatter_r",
            .single_scatter_t => "single_scatter_t",
            .doubled_layers => "doubled_layers",
            .doubling_steps => "doubling_steps",
            .doubling_qseries_skipped => "doubling_qseries_skipped",
            .doubling_qseries_nonzero => "doubling_qseries_nonzero",
            .matrix_qseries => "matrix_qseries",
            .matrix_smul_q_product => "matrix_smul_q_product",
            .matrix_smul_rd => "matrix_smul_rd",
            .matrix_smul_rd_nonzero => "matrix_smul_rd_nonzero",
            .matrix_smul_tu => "matrix_smul_tu",
            .matrix_smul_tu_nonzero => "matrix_smul_tu_nonzero",
            .matrix_smul_td => "matrix_smul_td",
            .matrix_smul_td_nonzero => "matrix_smul_td_nonzero",
            .matrix_smul_add_semul3 => "matrix_smul_add_semul3",
            .matrix_semul => "matrix_semul",
            .matrix_semul_add => "matrix_semul_add",
            .matrix_mat_add_esmul => "matrix_mat_add_esmul",
            .matrix_mat_add_esmul3 => "matrix_mat_add_esmul3",
            .matrix_esmul_semul => "matrix_esmul_semul",
            .matrix_esmul_semul_add => "matrix_esmul_semul_add",
            .initial_exp_evals => "initial_exp_evals",
            .doubling_square_evals => "doubling_square_evals",
            .phase_renormalizations => "phase_renormalizations",
            .orders_calls => "orders_calls",
            .orders_initial_returns => "orders_initial_returns",
            .orders_multiple_iterations => "orders_multiple_iterations",
            .dot_gauss_pair_calls => "dot_gauss_pair_calls",
            .dot_gauss_pair_terms => "dot_gauss_pair_terms",
            .orders_inactive_down_layers => "orders_inactive_down_layers",
            .orders_inactive_up_layers => "orders_inactive_up_layers",
        };
    }
};

pub const counter_count = @typeInfo(Counter).@"enum".fields.len;

pub const Worker = struct {
    sections_ns: [section_count]u64 = [_]u64{0} ** section_count,
    counters: [counter_count]u64 = [_]u64{0} ** counter_count,

    pub inline fn addSection(self: *Worker, section: Section, elapsed_ns: u64) void {
        if (!enabled) return;
        self.sections_ns[@intFromEnum(section)] += elapsed_ns;
    }

    pub inline fn addCounter(self: *Worker, counter: Counter, value: u64) void {
        if (!enabled) return;
        self.counters[@intFromEnum(counter)] += value;
    }
};

pub const Run = struct {
    wall_sections_ns: [section_count]u64 = [_]u64{0} ** section_count,
    counters: [counter_count]u64 = [_]u64{0} ** counter_count,
    workers: [max_workers]Worker = [_]Worker{.{}} ** max_workers,
    worker_count: usize = 0,
    forward_wall_ns: u64 = 0,

    pub fn init() Run {
        return .{};
    }

    pub inline fn setForwardWallNs(self: *Run, elapsed_ns: u64) void {
        if (!enabled) return;
        self.forward_wall_ns = elapsed_ns;
    }

    pub inline fn setWorkerCount(self: *Run, count: usize) void {
        if (!enabled) return;
        self.worker_count = @min(count, max_workers);
    }

    pub inline fn worker(self: *Run, index: usize) ?*Worker {
        if (!enabled or index >= max_workers) return null;
        if (index + 1 > self.worker_count) self.worker_count = index + 1;
        return &self.workers[index];
    }

    pub inline fn addWallSection(self: *Run, section: Section, elapsed_ns: u64) void {
        if (!enabled) return;
        self.wall_sections_ns[@intFromEnum(section)] += elapsed_ns;
    }

    pub inline fn addCounter(self: *Run, counter: Counter, value: u64) void {
        if (!enabled) return;
        self.counters[@intFromEnum(counter)] += value;
    }

    pub fn totalWorkerSectionNs(self: *const Run, section: Section) u64 {
        if (!enabled) return 0;
        var sum: u64 = 0;
        for (self.workers[0..self.worker_count]) |worker_state| {
            sum += worker_state.sections_ns[@intFromEnum(section)];
        }
        return sum;
    }

    pub fn totalCounter(self: *const Run, counter: Counter) u64 {
        if (!enabled) return 0;
        var sum = self.counters[@intFromEnum(counter)];
        for (self.workers[0..self.worker_count]) |worker_state| {
            sum += worker_state.counters[@intFromEnum(counter)];
        }
        return sum;
    }
};

pub inline fn noRun() RunRef {
    if (enabled) return null;
    return {};
}

pub inline fn noWorker() WorkerRef {
    if (enabled) return null;
    return {};
}

pub inline fn asRun(ref: RunRef) ?*Run {
    if (enabled) return ref;
    return null;
}

pub inline fn asWorker(ref: WorkerRef) ?*Worker {
    if (enabled) return ref;
    return null;
}

pub inline fn begin() i128 {
    if (!enabled) return 0;
    return std.time.nanoTimestamp();
}

pub inline fn elapsed(start_ns: i128) u64 {
    if (!enabled) return 0;
    const end_ns = std.time.nanoTimestamp();
    return @intCast(@max(end_ns - start_ns, 0));
}
