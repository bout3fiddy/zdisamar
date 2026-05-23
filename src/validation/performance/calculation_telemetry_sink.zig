const std = @import("std");

pub const available = true;

const nan = std.math.nan(f64);
const missing_index: i64 = -1;

const Expr = enum(u16) {
    sampling_kernel_shape = 1,
    forward_miss_reuse = 2,
    reflectance_assembly = 3,
    jacobian_column = 4,
    labos_effective_scattering_depth = 10,
    labos_doubling_trigger = 11,
    labos_qseries_skip = 12,
    orders_convergence = 20,
    fourier_weighted_reflectance = 30,
    fourier_tail_break = 31,
    labos_reflectance_clamp = 40,
    labos_jacobian_norm1 = 41,
};

// Sentinel coordinates keep the staging stream columnar: absent coordinates
// stay numeric, then become Parquet nulls in the research pipeline.
const Coordinates = struct {
    wavelength_nm: f64 = nan,
    layer_index: i64 = missing_index,
    fourier_index: i64 = missing_index,
    order_index: i64 = missing_index,
    state_index: i64 = missing_index,
    branch: i64 = missing_index,
};

const ScalarValues = struct {
    input_0: f64 = nan,
    input_1: f64 = nan,
    input_2: f64 = nan,
    input_3: f64 = nan,
    param_0: f64 = nan,
    param_1: f64 = nan,
    result: f64 = nan,
    clamped: bool = false,
    skipped: bool = false,
};

const ReductionValues = struct {
    term_count: usize = 0,
    nonzero_count: usize = 0,
    zero_count: usize = 0,
    min_term: f64 = nan,
    max_term: f64 = nan,
    sum: f64 = nan,
    mean: f64 = nan,
    l1_norm: f64 = nan,
    l2_norm: f64 = nan,
    result: f64 = nan,
};

const DecisionValues = struct {
    lhs: f64 = nan,
    rhs: f64 = nan,
    threshold: f64 = nan,
    taken: bool = false,
    work_if_taken: usize = 0,
    work_if_not_taken: usize = 0,
};

pub const RowCounts = struct {
    scalar: usize = 0,
    reduction: usize = 0,
    decision: usize = 0,
};

// Validation-owned sink. Product builds receive calculation_telemetry_stub
// instead, so these files and mutexes are never linked into the public model.
const Collector = struct {
    allocator: std.mem.Allocator,
    scalar_file: std.fs.File,
    reduction_file: std.fs.File,
    decision_file: std.fs.File,
    mutex: std.Thread.Mutex = .{},
    next_event_index: u64 = 0,
    scalar_rows: usize = 0,
    reduction_rows: usize = 0,
    decision_rows: usize = 0,
    first_error: ?anyerror = null,

    pub fn init(allocator: std.mem.Allocator, output_dir: []const u8) !Collector {
        try std.fs.cwd().makePath(output_dir);
        var scalar_file = try createOutputFile(allocator, output_dir, "scalar_expression_rows.csv");
        errdefer scalar_file.close();
        var reduction_file = try createOutputFile(allocator, output_dir, "reduction_expression_rows.csv");
        errdefer reduction_file.close();
        var decision_file = try createOutputFile(allocator, output_dir, "decision_rows.csv");
        errdefer decision_file.close();

        var collector = Collector{
            .allocator = allocator,
            .scalar_file = scalar_file,
            .reduction_file = reduction_file,
            .decision_file = decision_file,
        };
        try collector.writeHeaders();
        return collector;
    }

    pub fn deinit(self: *Collector) void {
        self.scalar_file.close();
        self.reduction_file.close();
        self.decision_file.close();
        self.* = undefined;
    }

    pub fn finish(self: *Collector) !void {
        if (self.first_error) |err| return err;
    }

    pub fn counts(self: *const Collector) RowCounts {
        return .{
            .scalar = self.scalar_rows,
            .reduction = self.reduction_rows,
            .decision = self.decision_rows,
        };
    }

    fn writeHeaders(self: *Collector) !void {
        try writeHeader(
            self.scalar_file,
            "event_index,expr_id,wavelength_nm,layer_index,fourier_index,order_index,state_index,branch,input_0,input_1,input_2,input_3,param_0,param_1,result,abs_result,relative_scale,clamped,skipped,finite\n",
        );
        try writeHeader(
            self.reduction_file,
            "event_index,expr_id,wavelength_nm,layer_index,fourier_index,order_index,state_index,branch,term_count,nonzero_count,zero_count,min_term,max_term,sum,mean,l1_norm,l2_norm,result\n",
        );
        try writeHeader(
            self.decision_file,
            "event_index,expr_id,wavelength_nm,layer_index,fourier_index,order_index,state_index,branch,lhs,rhs,threshold,margin,taken,work_if_taken,work_if_not_taken\n",
        );
    }

    fn writeScalar(self: *Collector, expr: Expr, coord: Coordinates, values: ScalarValues) !void {
        var buffer: [768]u8 = undefined;
        const result_abs = absOrNan(values.result);
        const line = try std.fmt.bufPrint(
            &buffer,
            "{},{},{e:.17},{},{},{},{},{},{e:.17},{e:.17},{e:.17},{e:.17},{e:.17},{e:.17},{e:.17},{e:.17},{e:.17},{},{},{}\n",
            .{
                self.nextEventIndex(),
                exprId(expr),
                coord.wavelength_nm,
                coord.layer_index,
                coord.fourier_index,
                coord.order_index,
                coord.state_index,
                coord.branch,
                values.input_0,
                values.input_1,
                values.input_2,
                values.input_3,
                values.param_0,
                values.param_1,
                values.result,
                result_abs,
                relativeScale(values),
                boolInt(values.clamped),
                boolInt(values.skipped),
                boolInt(std.math.isFinite(values.result)),
            },
        );
        try self.scalar_file.writeAll(line);
        self.scalar_rows += 1;
    }

    fn writeReduction(self: *Collector, expr: Expr, coord: Coordinates, values: ReductionValues) !void {
        var buffer: [768]u8 = undefined;
        const line = try std.fmt.bufPrint(
            &buffer,
            "{},{},{e:.17},{},{},{},{},{},{},{},{},{e:.17},{e:.17},{e:.17},{e:.17},{e:.17},{e:.17},{e:.17}\n",
            .{
                self.nextEventIndex(),
                exprId(expr),
                coord.wavelength_nm,
                coord.layer_index,
                coord.fourier_index,
                coord.order_index,
                coord.state_index,
                coord.branch,
                values.term_count,
                values.nonzero_count,
                values.zero_count,
                values.min_term,
                values.max_term,
                values.sum,
                values.mean,
                values.l1_norm,
                values.l2_norm,
                values.result,
            },
        );
        try self.reduction_file.writeAll(line);
        self.reduction_rows += 1;
    }

    fn writeDecision(self: *Collector, expr: Expr, coord: Coordinates, values: DecisionValues) !void {
        var buffer: [768]u8 = undefined;
        const line = try std.fmt.bufPrint(
            &buffer,
            "{},{},{e:.17},{},{},{},{},{},{e:.17},{e:.17},{e:.17},{e:.17},{},{},{}\n",
            .{
                self.nextEventIndex(),
                exprId(expr),
                coord.wavelength_nm,
                coord.layer_index,
                coord.fourier_index,
                coord.order_index,
                coord.state_index,
                coord.branch,
                values.lhs,
                values.rhs,
                values.threshold,
                values.lhs - values.threshold,
                boolInt(values.taken),
                values.work_if_taken,
                values.work_if_not_taken,
            },
        );
        try self.decision_file.writeAll(line);
        self.decision_rows += 1;
    }

    fn nextEventIndex(self: *Collector) u64 {
        const event_index = self.next_event_index;
        self.next_event_index += 1;
        return event_index;
    }
};

pub const CollectorHandle = Collector;

var active_mutex: std.Thread.Mutex = .{};
var active_collector: ?*Collector = null;

pub fn setCollector(collector: *Collector) void {
    active_mutex.lock();
    defer active_mutex.unlock();
    active_collector = collector;
}

pub fn clearCollector() void {
    active_mutex.lock();
    defer active_mutex.unlock();
    active_collector = null;
}

pub fn wavelengthSamplingPlan(
    row_count: usize,
    radiance_integrated_rows: usize,
    irradiance_integrated_rows: usize,
    radiance_sample_count: usize,
    irradiance_sample_count: usize,
    side_sample_count: usize,
    max_kernel_sample_count: usize,
) void {
    const integrated_rows = radiance_integrated_rows + irradiance_integrated_rows;
    const total_sample_count = radiance_sample_count + irradiance_sample_count;
    const candidate_rows = row_count * 2;
    recordReduction(
        .sampling_kernel_shape,
        .{},
        .{
            .term_count = candidate_rows,
            .nonzero_count = integrated_rows,
            .zero_count = candidate_rows -| integrated_rows,
            .max_term = float(max_kernel_sample_count),
            .sum = float(total_sample_count),
            .mean = ratio(total_sample_count, candidate_rows),
            .l1_norm = float(side_sample_count),
            .result = float(side_sample_count),
        },
    );
}

pub fn forwardMissPlan(row_count: usize, sample_index_count: usize, miss_count: usize) void {
    recordReduction(
        .forward_miss_reuse,
        .{},
        .{
            .term_count = sample_index_count,
            .nonzero_count = miss_count,
            .zero_count = sample_index_count -| miss_count,
            .sum = float(miss_count),
            .mean = ratio(miss_count, sample_index_count),
            .result = ratio(miss_count, sample_index_count),
            .l1_norm = float(row_count),
        },
    );
}

pub fn reflectanceAssembly(
    sample_count: usize,
    denominator_clamp_count: usize,
    min_denominator: f64,
    max_reflectance: f64,
) void {
    recordReduction(
        .reflectance_assembly,
        .{},
        .{
            .term_count = sample_count,
            .nonzero_count = sample_count -| denominator_clamp_count,
            .zero_count = denominator_clamp_count,
            .min_term = min_denominator,
            .max_term = max_reflectance,
            .result = max_reflectance,
        },
    );
}

pub fn jacobianColumn(state_index: usize, sum: f64, mean: f64, max_abs: f64) void {
    recordReduction(
        .jacobian_column,
        .{ .state_index = index(state_index) },
        .{
            .sum = sum,
            .mean = mean,
            .l1_norm = max_abs,
            .result = mean,
        },
    );
}

pub fn labosLayerDecision(
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
    const coord: Coordinates = .{
        .layer_index = index(layer_index),
        .fourier_index = index(i_fourier),
        .branch = index(phase_max_index),
    };
    recordScalar(
        .labos_effective_scattering_depth,
        coord,
        .{
            .input_0 = optical_depth,
            .input_1 = single_scatter_albedo,
            .input_2 = max_beta_eff,
            .param_0 = threshold_doubl,
            .param_1 = start_optical_depth,
            .result = effective_scattering_depth,
            .skipped = !uses_doubling,
        },
    );
    recordDecision(
        .labos_doubling_trigger,
        coord,
        .{
            .lhs = effective_scattering_depth,
            .rhs = start_optical_depth,
            .threshold = threshold_doubl,
            .taken = uses_doubling,
            .work_if_taken = doubling_count,
            .work_if_not_taken = 0,
        },
    );
}

pub fn labosDoublingStep(
    trace_r: f64,
    trace_t: f64,
    threshold_mul: f64,
    qseries_is_zero: bool,
) void {
    recordDecision(
        .labos_qseries_skip,
        .{},
        .{
            .lhs = @abs(trace_r * trace_r),
            .rhs = trace_t,
            .threshold = threshold_mul,
            .taken = qseries_is_zero,
            .work_if_taken = 0,
            .work_if_not_taken = 1,
        },
    );
}

pub fn ordersConvergence(
    iteration_count: usize,
    max_iteration_count: usize,
    max_outgoing_upward: f64,
    threshold: f64,
    returned_initial: bool,
    hit_iteration_cap: bool,
) void {
    recordDecision(
        .orders_convergence,
        .{
            .order_index = index(iteration_count),
            .branch = if (returned_initial) 1 else 2,
        },
        .{
            .lhs = max_outgoing_upward,
            .rhs = float(max_iteration_count),
            .threshold = threshold,
            .taken = !hit_iteration_cap,
            .work_if_taken = iteration_count,
            .work_if_not_taken = max_iteration_count,
        },
    );
}

pub fn fourierContribution(
    i_fourier: usize,
    fourier_weight: f64,
    term_reflectance: f64,
    weighted_reflectance: f64,
    tail_threshold: f64,
    tail_break: bool,
) void {
    const coord: Coordinates = .{ .fourier_index = index(i_fourier) };
    recordScalar(
        .fourier_weighted_reflectance,
        coord,
        .{
            .input_0 = term_reflectance,
            .param_0 = fourier_weight,
            .param_1 = tail_threshold,
            .result = weighted_reflectance,
            .skipped = tail_break,
        },
    );
    recordDecision(
        .fourier_tail_break,
        coord,
        .{
            .lhs = @abs(term_reflectance),
            .rhs = weighted_reflectance,
            .threshold = tail_threshold,
            .taken = tail_break,
            .work_if_taken = 0,
            .work_if_not_taken = 1,
        },
    );
}

pub fn labosResult(raw_reflectance: f64, clamped_reflectance: f64, jacobian_norm1: f64) void {
    recordScalar(
        .labos_reflectance_clamp,
        .{},
        .{
            .input_0 = raw_reflectance,
            .result = clamped_reflectance,
            .clamped = raw_reflectance != clamped_reflectance,
        },
    );
    recordScalar(
        .labos_jacobian_norm1,
        .{},
        .{
            .input_0 = clamped_reflectance,
            .result = jacobian_norm1,
        },
    );
}

fn recordScalar(expr: Expr, coord: Coordinates, values: ScalarValues) void {
    const collector = activeCollector() orelse return;
    collector.mutex.lock();
    defer collector.mutex.unlock();
    if (collector.first_error != null) return;
    collector.writeScalar(expr, coord, values) catch |err| {
        collector.first_error = err;
    };
}

fn recordReduction(expr: Expr, coord: Coordinates, values: ReductionValues) void {
    const collector = activeCollector() orelse return;
    collector.mutex.lock();
    defer collector.mutex.unlock();
    if (collector.first_error != null) return;
    collector.writeReduction(expr, coord, values) catch |err| {
        collector.first_error = err;
    };
}

fn recordDecision(expr: Expr, coord: Coordinates, values: DecisionValues) void {
    const collector = activeCollector() orelse return;
    collector.mutex.lock();
    defer collector.mutex.unlock();
    if (collector.first_error != null) return;
    collector.writeDecision(expr, coord, values) catch |err| {
        collector.first_error = err;
    };
}

fn activeCollector() ?*Collector {
    active_mutex.lock();
    defer active_mutex.unlock();
    return active_collector;
}

fn createOutputFile(allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.fs.cwd().createFile(path, .{ .truncate = true });
}

fn writeHeader(file: std.fs.File, header: []const u8) !void {
    try file.writeAll(header);
}

fn exprId(expr: Expr) u16 {
    return @intFromEnum(expr);
}

fn index(value: usize) i64 {
    return std.math.cast(i64, value) orelse std.math.maxInt(i64);
}

fn float(value: usize) f64 {
    return @floatFromInt(value);
}

fn ratio(numerator: usize, denominator: usize) f64 {
    if (denominator == 0) return nan;
    return float(numerator) / float(denominator);
}

fn boolInt(value: bool) u8 {
    return @intFromBool(value);
}

fn absOrNan(value: f64) f64 {
    if (!std.math.isFinite(value)) return nan;
    return @abs(value);
}

fn relativeScale(values: ScalarValues) f64 {
    var denominator: f64 = 0.0;
    const inputs = [_]f64{
        values.input_0,
        values.input_1,
        values.input_2,
        values.input_3,
        values.param_0,
        values.param_1,
    };
    for (inputs) |value| {
        if (std.math.isFinite(value)) denominator += @abs(value);
    }
    if (denominator <= 0.0 or !std.math.isFinite(values.result)) return nan;
    return @abs(values.result) / denominator;
}
