const std = @import("std");
const Parquet = @import("parquet_lite.zig");

// instrumentation: calculation telemetry sink
// captures: expression rows to Parquet
// why: make forward-model math inspectable outside the product path.
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
    labos_qseries_rd_product = 13,
    labos_qseries_tu_product = 14,
    labos_qseries_td_product = 15,
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

const scalar_columns = [_]Parquet.ColumnDef{
    .{ .name = "event_index", .kind = .int64 },
    .{ .name = "expr_id", .kind = .int32 },
    .{ .name = "wavelength_nm", .kind = .double },
    .{ .name = "layer_index", .kind = .int64 },
    .{ .name = "fourier_index", .kind = .int64 },
    .{ .name = "order_index", .kind = .int64 },
    .{ .name = "state_index", .kind = .int64 },
    .{ .name = "branch", .kind = .int64 },
    .{ .name = "input_0", .kind = .double },
    .{ .name = "input_1", .kind = .double },
    .{ .name = "input_2", .kind = .double },
    .{ .name = "input_3", .kind = .double },
    .{ .name = "param_0", .kind = .double },
    .{ .name = "param_1", .kind = .double },
    .{ .name = "result", .kind = .double },
    .{ .name = "abs_result", .kind = .double },
    .{ .name = "relative_scale", .kind = .double },
    .{ .name = "clamped", .kind = .int32 },
    .{ .name = "skipped", .kind = .int32 },
    .{ .name = "finite", .kind = .int32 },
};

const reduction_columns = [_]Parquet.ColumnDef{
    .{ .name = "event_index", .kind = .int64 },
    .{ .name = "expr_id", .kind = .int32 },
    .{ .name = "wavelength_nm", .kind = .double },
    .{ .name = "layer_index", .kind = .int64 },
    .{ .name = "fourier_index", .kind = .int64 },
    .{ .name = "order_index", .kind = .int64 },
    .{ .name = "state_index", .kind = .int64 },
    .{ .name = "branch", .kind = .int64 },
    .{ .name = "term_count", .kind = .int64 },
    .{ .name = "nonzero_count", .kind = .int64 },
    .{ .name = "zero_count", .kind = .int64 },
    .{ .name = "min_term", .kind = .double },
    .{ .name = "max_term", .kind = .double },
    .{ .name = "sum", .kind = .double },
    .{ .name = "mean", .kind = .double },
    .{ .name = "l1_norm", .kind = .double },
    .{ .name = "l2_norm", .kind = .double },
    .{ .name = "result", .kind = .double },
};

const decision_columns = [_]Parquet.ColumnDef{
    .{ .name = "event_index", .kind = .int64 },
    .{ .name = "expr_id", .kind = .int32 },
    .{ .name = "wavelength_nm", .kind = .double },
    .{ .name = "layer_index", .kind = .int64 },
    .{ .name = "fourier_index", .kind = .int64 },
    .{ .name = "order_index", .kind = .int64 },
    .{ .name = "state_index", .kind = .int64 },
    .{ .name = "branch", .kind = .int64 },
    .{ .name = "lhs", .kind = .double },
    .{ .name = "rhs", .kind = .double },
    .{ .name = "threshold", .kind = .double },
    .{ .name = "margin", .kind = .double },
    .{ .name = "taken", .kind = .int32 },
    .{ .name = "work_if_taken", .kind = .int64 },
    .{ .name = "work_if_not_taken", .kind = .int64 },
};

const catalog_columns = [_]Parquet.ColumnDef{
    .{ .name = "expr_id", .kind = .int32 },
    .{ .name = "expr_name", .kind = .byte_array, .utf8 = true },
    .{ .name = "row_table", .kind = .byte_array, .utf8 = true },
    .{ .name = "subsystem", .kind = .byte_array, .utf8 = true },
    .{ .name = "equation", .kind = .byte_array, .utf8 = true },
    .{ .name = "result_name", .kind = .byte_array, .utf8 = true },
    .{ .name = "inputs", .kind = .byte_array, .utf8 = true },
    .{ .name = "units", .kind = .byte_array, .utf8 = true },
    .{ .name = "source_file", .kind = .byte_array, .utf8 = true },
    .{ .name = "function", .kind = .byte_array, .utf8 = true },
    .{ .name = "capture_reason", .kind = .byte_array, .utf8 = true },
};

const ExpressionMeta = struct {
    expr: Expr,
    expr_name: []const u8,
    row_table: []const u8,
    subsystem: []const u8,
    equation: []const u8,
    result_name: []const u8,
    inputs: []const u8,
    units: []const u8,
    source_file: []const u8,
    function: []const u8,
    capture_reason: []const u8,
};

const expressions = [_]ExpressionMeta{
    .{
        .expr = .sampling_kernel_shape,
        .expr_name = "sampling_kernel_shape",
        .row_table = "reduction_expression_rows",
        .subsystem = "instrument_grid",
        .equation = "integrated_rows = count(enabled radiance/irradiance kernels); side_samples = count(non-inline integration samples)",
        .result_name = "side_sample_count",
        .inputs = "row_count,radiance_integrated_rows,irradiance_integrated_rows,radiance_sample_count,irradiance_sample_count",
        .units = "count",
        .source_file = "src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig",
        .function = "recordWavelengthSamplingPlan",
        .capture_reason = "Find integration kernels that create side storage and extra forward work.",
    },
    .{
        .expr = .forward_miss_reuse,
        .expr_name = "forward_miss_reuse",
        .row_table = "reduction_expression_rows",
        .subsystem = "instrument_grid",
        .equation = "unique_fraction = miss_count / sample_index_count",
        .result_name = "unique_fraction",
        .inputs = "sample_index_count,miss_count",
        .units = "fraction",
        .source_file = "src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig",
        .function = "buildForwardMissPlan",
        .capture_reason = "Quantify wavelength-cache reuse created by spectral integration.",
    },
    .{
        .expr = .reflectance_assembly,
        .expr_name = "reflectance_assembly",
        .row_table = "reduction_expression_rows",
        .subsystem = "instrument_grid",
        .equation = "rho_i = pi * radiance_i / max(irradiance_i * mu0, 1e-9)",
        .result_name = "max_reflectance",
        .inputs = "sample_count,denominator_clamp_count,min_denominator",
        .units = "reflectance",
        .source_file = "src/forward_model/instrument_grid/grid_calculation/simulate.zig",
        .function = "assembleReflectance",
        .capture_reason = "Detect denominator clamps and reflectance outliers.",
    },
    .{
        .expr = .jacobian_column,
        .expr_name = "jacobian_column",
        .row_table = "reduction_expression_rows",
        .subsystem = "instrument_grid",
        .equation = "mean_j = sum_i J_i / N",
        .result_name = "mean_jacobian",
        .inputs = "state_index,column_sum,sample_count",
        .units = "state derivative",
        .source_file = "src/forward_model/instrument_grid/grid_calculation/simulate.zig",
        .function = "processJacobianSamples",
        .capture_reason = "Find derivative columns with negligible or extreme contribution.",
    },
    .{
        .expr = .labos_effective_scattering_depth,
        .expr_name = "labos_effective_scattering_depth",
        .row_table = "scalar_expression_rows",
        .subsystem = "labos",
        .equation = "tau_eff = tau * omega0 * max_l(|beta_l| / (2l + 1))",
        .result_name = "effective_scattering_depth",
        .inputs = "optical_depth,single_scatter_albedo,max_beta_eff",
        .units = "optical depth",
        .source_file = "src/forward_model/radiative_transfer/labos/layers.zig",
        .function = "calcRTlayersIntoWithBasis",
        .capture_reason = "Study when LABOS layer-doubling work is physically relevant.",
    },
    .{
        .expr = .labos_doubling_trigger,
        .expr_name = "labos_doubling_trigger",
        .row_table = "decision_rows",
        .subsystem = "labos",
        .equation = "uses_doubling = tau_eff > threshold_doubl",
        .result_name = "uses_doubling",
        .inputs = "effective_scattering_depth,threshold_doubl",
        .units = "boolean",
        .source_file = "src/forward_model/radiative_transfer/labos/layers.zig",
        .function = "calcRTlayersIntoWithBasis",
        .capture_reason = "Measure threshold margins around expensive layer doubling.",
    },
    .{
        .expr = .labos_qseries_skip,
        .expr_name = "labos_qseries_skip",
        .row_table = "decision_rows",
        .subsystem = "labos",
        .equation = "qseries_is_zero = abs(trace(R)^2) <= threshold_mul",
        .result_name = "qseries_is_zero",
        .inputs = "trace_r,threshold_mul",
        .units = "boolean",
        .source_file = "src/forward_model/radiative_transfer/labos/layers.zig",
        .function = "doDouble/doDouble12x10Step",
        .capture_reason = "Identify q-series products whose contribution is below the fast-mode cutoff.",
    },
    .{
        .expr = .labos_qseries_rd_product,
        .expr_name = "labos_qseries_rd_product",
        .row_table = "decision_rows",
        .subsystem = "labos",
        .equation = "rd_nonzero = abs(trace(R) * trace(D)) > threshold_mul",
        .result_name = "rd_nonzero",
        .inputs = "trace_r,trace_d,threshold_mul,qseries_is_zero",
        .units = "boolean",
        .source_file = "src/forward_model/radiative_transfer/labos/layers.zig",
        .function = "doDouble/doDouble12x10Step",
        .capture_reason = "Test whether q-series zero decisions imply downstream R-D products can also be skipped.",
    },
    .{
        .expr = .labos_qseries_tu_product,
        .expr_name = "labos_qseries_tu_product",
        .row_table = "decision_rows",
        .subsystem = "labos",
        .equation = "tu_nonzero = abs(trace(T) * trace(U)) > threshold_mul",
        .result_name = "tu_nonzero",
        .inputs = "trace_t,trace_u,threshold_mul,qseries_is_zero",
        .units = "boolean",
        .source_file = "src/forward_model/radiative_transfer/labos/layers.zig",
        .function = "doDouble/doDouble12x10Step",
        .capture_reason = "Test whether q-series zero decisions imply downstream T-U products can also be skipped.",
    },
    .{
        .expr = .labos_qseries_td_product,
        .expr_name = "labos_qseries_td_product",
        .row_table = "decision_rows",
        .subsystem = "labos",
        .equation = "td_nonzero = abs(trace(T) * trace(D)) > threshold_mul",
        .result_name = "td_nonzero",
        .inputs = "trace_t,trace_d,threshold_mul,qseries_is_zero",
        .units = "boolean",
        .source_file = "src/forward_model/radiative_transfer/labos/layers.zig",
        .function = "doDouble/doDouble12x10Step",
        .capture_reason = "Test whether q-series zero decisions imply downstream T-D products can also be skipped.",
    },
    .{
        .expr = .orders_convergence,
        .expr_name = "orders_convergence",
        .row_table = "decision_rows",
        .subsystem = "labos",
        .equation = "stop_orders = max_outgoing_upward < threshold_conv",
        .result_name = "stop_orders",
        .inputs = "max_outgoing_upward,threshold_conv",
        .units = "boolean",
        .source_file = "src/forward_model/radiative_transfer/labos/orders.zig",
        .function = "ordersScatIntoWithWorkspace",
        .capture_reason = "Study scattering-order convergence margins and iteration caps.",
    },
    .{
        .expr = .fourier_weighted_reflectance,
        .expr_name = "fourier_weighted_reflectance",
        .row_table = "scalar_expression_rows",
        .subsystem = "labos",
        .equation = "rho_m_weighted = c_m * rho_m, c_0=1, c_m=2*cos(m*relative_azimuth)",
        .result_name = "weighted_reflectance",
        .inputs = "term_reflectance,fourier_weight",
        .units = "reflectance",
        .source_file = "src/forward_model/radiative_transfer/labos/execute.zig",
        .function = "layerResolvedLabosWithWorkspace",
        .capture_reason = "Find Fourier terms that add no meaningful reflectance.",
    },
    .{
        .expr = .fourier_tail_break,
        .expr_name = "fourier_tail_break",
        .row_table = "decision_rows",
        .subsystem = "labos",
        .equation = "tail_break = m >= fourier_floor_scalar and abs(rho_m) <= fourier_tail_reflectance_epsilon",
        .result_name = "tail_break",
        .inputs = "term_reflectance,tail_threshold",
        .units = "boolean",
        .source_file = "src/forward_model/radiative_transfer/labos/execute.zig",
        .function = "layerResolvedLabosWithWorkspace",
        .capture_reason = "Quantify how early Fourier expansion can terminate.",
    },
    .{
        .expr = .labos_reflectance_clamp,
        .expr_name = "labos_reflectance_clamp",
        .row_table = "scalar_expression_rows",
        .subsystem = "labos",
        .equation = "rho_out = clamp(rho_raw, 0, 2)",
        .result_name = "clamped_reflectance",
        .inputs = "raw_reflectance",
        .units = "reflectance",
        .source_file = "src/forward_model/radiative_transfer/labos/execute.zig",
        .function = "layerResolvedLabosWithWorkspace",
        .capture_reason = "Detect physically suspicious raw reflectance values.",
    },
    .{
        .expr = .labos_jacobian_norm1,
        .expr_name = "labos_jacobian_norm1",
        .row_table = "scalar_expression_rows",
        .subsystem = "labos",
        .equation = "jacobian_norm1 = sum_s abs(d rho / d state_s)",
        .result_name = "jacobian_norm1",
        .inputs = "jacobian_vector",
        .units = "reflectance derivative",
        .source_file = "src/forward_model/radiative_transfer/labos/execute.zig",
        .function = "layerResolvedLabosWithWorkspace",
        .capture_reason = "Find forward samples with negligible derivative signal.",
    },
};

// instrumentation: telemetry collector
// captures: scalar/reduction/decision tables
// why: own file I/O and locks only inside the validation harness.
const Collector = struct {
    allocator: std.mem.Allocator,
    scalar_table: Parquet.TableWriter,
    reduction_table: Parquet.TableWriter,
    decision_table: Parquet.TableWriter,
    scalar_mutex: std.Thread.Mutex = .{},
    reduction_mutex: std.Thread.Mutex = .{},
    decision_mutex: std.Thread.Mutex = .{},
    error_mutex: std.Thread.Mutex = .{},
    next_event_index: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    scalar_rows: usize = 0,
    reduction_rows: usize = 0,
    decision_rows: usize = 0,
    first_error: ?anyerror = null,

    pub fn init(allocator: std.mem.Allocator, output_dir: []const u8) !Collector {
        try std.fs.cwd().makePath(output_dir);
        try writeExpressionCatalog(allocator, output_dir);

        var scalar_table = try createTable(
            allocator,
            output_dir,
            "scalar_expression_rows.parquet",
            scalar_columns[0..],
        );
        errdefer scalar_table.deinit();
        var reduction_table = try createTable(
            allocator,
            output_dir,
            "reduction_expression_rows.parquet",
            reduction_columns[0..],
        );
        errdefer reduction_table.deinit();
        var decision_table = try createTable(
            allocator,
            output_dir,
            "decision_rows.parquet",
            decision_columns[0..],
        );
        errdefer decision_table.deinit();

        return Collector{
            .allocator = allocator,
            .scalar_table = scalar_table,
            .reduction_table = reduction_table,
            .decision_table = decision_table,
        };
    }

    pub fn deinit(self: *Collector) void {
        self.scalar_table.deinit();
        self.reduction_table.deinit();
        self.decision_table.deinit();
        self.* = undefined;
    }

    pub fn finish(self: *Collector) !void {
        try self.raiseFirstError();
        try self.scalar_table.close();
        try self.reduction_table.close();
        try self.decision_table.close();
        try self.raiseFirstError();
    }

    pub fn counts(self: *const Collector) RowCounts {
        return .{
            .scalar = self.scalar_rows,
            .reduction = self.reduction_rows,
            .decision = self.decision_rows,
        };
    }

    fn writeScalar(self: *Collector, expr: Expr, coord: Coordinates, values: ScalarValues) !void {
        const result_abs = absOrNan(values.result);
        try self.writeCommon(&self.scalar_table, expr, coord);
        try self.scalar_table.appendDouble(8, values.input_0);
        try self.scalar_table.appendDouble(9, values.input_1);
        try self.scalar_table.appendDouble(10, values.input_2);
        try self.scalar_table.appendDouble(11, values.input_3);
        try self.scalar_table.appendDouble(12, values.param_0);
        try self.scalar_table.appendDouble(13, values.param_1);
        try self.scalar_table.appendDouble(14, values.result);
        try self.scalar_table.appendDouble(15, result_abs);
        try self.scalar_table.appendDouble(16, relativeScale(values));
        try self.scalar_table.appendInt32(17, boolInt(values.clamped));
        try self.scalar_table.appendInt32(18, boolInt(values.skipped));
        try self.scalar_table.appendInt32(19, boolInt(std.math.isFinite(values.result)));
        try self.scalar_table.finishRow();
        self.scalar_rows += 1;
    }

    fn writeReduction(self: *Collector, expr: Expr, coord: Coordinates, values: ReductionValues) !void {
        try self.writeCommon(&self.reduction_table, expr, coord);
        try self.reduction_table.appendInt64(8, index(values.term_count));
        try self.reduction_table.appendInt64(9, index(values.nonzero_count));
        try self.reduction_table.appendInt64(10, index(values.zero_count));
        try self.reduction_table.appendDouble(11, values.min_term);
        try self.reduction_table.appendDouble(12, values.max_term);
        try self.reduction_table.appendDouble(13, values.sum);
        try self.reduction_table.appendDouble(14, values.mean);
        try self.reduction_table.appendDouble(15, values.l1_norm);
        try self.reduction_table.appendDouble(16, values.l2_norm);
        try self.reduction_table.appendDouble(17, values.result);
        try self.reduction_table.finishRow();
        self.reduction_rows += 1;
    }

    fn writeDecision(self: *Collector, expr: Expr, coord: Coordinates, values: DecisionValues) !void {
        try self.writeCommon(&self.decision_table, expr, coord);
        try self.decision_table.appendDouble(8, values.lhs);
        try self.decision_table.appendDouble(9, values.rhs);
        try self.decision_table.appendDouble(10, values.threshold);
        try self.decision_table.appendDouble(11, values.lhs - values.threshold);
        try self.decision_table.appendInt32(12, boolInt(values.taken));
        try self.decision_table.appendInt64(13, index(values.work_if_taken));
        try self.decision_table.appendInt64(14, index(values.work_if_not_taken));
        try self.decision_table.finishRow();
        self.decision_rows += 1;
    }

    fn writeCommon(self: *Collector, table: *Parquet.TableWriter, expr: Expr, coord: Coordinates) !void {
        try table.appendInt64(0, try self.nextEventIndex());
        try table.appendInt32(1, exprId(expr));
        try table.appendDouble(2, coord.wavelength_nm);
        try table.appendInt64(3, coord.layer_index);
        try table.appendInt64(4, coord.fourier_index);
        try table.appendInt64(5, coord.order_index);
        try table.appendInt64(6, coord.state_index);
        try table.appendInt64(7, coord.branch);
    }

    fn nextEventIndex(self: *Collector) !i64 {
        const event_index = self.next_event_index.fetchAdd(1, .monotonic);
        return std.math.cast(i64, event_index) orelse error.IntegerOverflow;
    }

    fn setFirstError(self: *Collector, err: anyerror) void {
        self.error_mutex.lock();
        defer self.error_mutex.unlock();
        if (self.first_error == null) self.first_error = err;
    }

    fn raiseFirstError(self: *Collector) !void {
        self.error_mutex.lock();
        defer self.error_mutex.unlock();
        if (self.first_error) |err| return err;
    }
};

pub const CollectorHandle = Collector;

// instrumentation: telemetry activation
// captures: hook writes during one harness run
// why: let worker threads emit rows without global product state.
var active_collector_ptr = std.atomic.Value(usize).init(0);

// instrumentation: telemetry activation
// captures: active collector pointer
// why: bound row capture to the current harness process.
pub fn setCollector(collector: *Collector) void {
    active_collector_ptr.store(@intFromPtr(collector), .release);
}

// instrumentation: telemetry activation
// captures: collector teardown
// why: stop hooks from writing after the harness closes files.
pub fn clearCollector() void {
    active_collector_ptr.store(0, .release);
}

// instrumentation: calculation telemetry
// captures: integration kernel counts
// why: quantify spectral sampling fan-out.
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

// instrumentation: calculation telemetry
// captures: unique forward-cache misses
// why: measure wavelength reuse from integration plans.
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

// instrumentation: calculation telemetry
// captures: reflectance denominator clamps and maxima
// why: detect unstable output assembly.
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

// instrumentation: calculation telemetry
// captures: Jacobian column sums and maxima
// why: find weak derivative signals for OE pruning.
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

// instrumentation: calculation telemetry
// captures: LABOS layer-doubling threshold inputs
// why: study which layer/Fourier coordinates need doubling.
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

// instrumentation: calculation telemetry
// captures: q-series skip margin per doubling step
// why: identify coordinates where Q=(I-RR)^-1-I is negligible.
pub fn labosDoublingStep(
    i_fourier: usize,
    layer_index: usize,
    phase_max_index: usize,
    doubling_step_index: usize,
    trace_r: f64,
    trace_t: f64,
    threshold_mul: f64,
    qseries_is_zero: bool,
) void {
    recordDecision(
        .labos_qseries_skip,
        .{
            .layer_index = index(layer_index),
            .fourier_index = index(i_fourier),
            .order_index = index(doubling_step_index),
            .state_index = index(phase_max_index),
        },
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

// instrumentation: calculation telemetry
// captures: downstream R-D/T-U/T-D product gates
// why: test if q-zero branches imply more matrix work can be skipped.
pub fn labosDoublingDownstreamGates(
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
    const coord: Coordinates = .{
        .layer_index = index(layer_index),
        .fourier_index = index(i_fourier),
        .order_index = index(doubling_step_index),
        .state_index = index(phase_max_index),
        .branch = if (qseries_is_zero) 1 else 0,
    };
    recordDecision(
        .labos_qseries_rd_product,
        coord,
        .{
            .lhs = @abs(trace_r * trace_d),
            .rhs = trace_d,
            .threshold = threshold_mul,
            .taken = rd_nonzero,
            .work_if_taken = 1,
            .work_if_not_taken = 0,
        },
    );
    recordDecision(
        .labos_qseries_tu_product,
        coord,
        .{
            .lhs = @abs(trace_t * trace_u),
            .rhs = trace_u,
            .threshold = threshold_mul,
            .taken = tu_nonzero,
            .work_if_taken = 1,
            .work_if_not_taken = 0,
        },
    );
    recordDecision(
        .labos_qseries_td_product,
        coord,
        .{
            .lhs = @abs(trace_t * trace_d),
            .rhs = trace_d,
            .threshold = threshold_mul,
            .taken = td_nonzero,
            .work_if_taken = 1,
            .work_if_not_taken = 0,
        },
    );
}

// instrumentation: calculation telemetry
// captures: scattering-order stop margins
// why: tune order convergence without losing reflectance.
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

// instrumentation: calculation telemetry
// captures: Fourier term contribution and tail stop
// why: locate late terms with negligible reflectance.
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

// instrumentation: calculation telemetry
// captures: raw/clamped LABOS reflectance and Jacobian norm
// why: detect suspicious outputs and weak derivatives.
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
    collector.scalar_mutex.lock();
    defer collector.scalar_mutex.unlock();
    collector.writeScalar(expr, coord, values) catch |err| {
        collector.setFirstError(err);
    };
}

fn recordReduction(expr: Expr, coord: Coordinates, values: ReductionValues) void {
    const collector = activeCollector() orelse return;
    collector.reduction_mutex.lock();
    defer collector.reduction_mutex.unlock();
    collector.writeReduction(expr, coord, values) catch |err| {
        collector.setFirstError(err);
    };
}

fn recordDecision(expr: Expr, coord: Coordinates, values: DecisionValues) void {
    const collector = activeCollector() orelse return;
    collector.decision_mutex.lock();
    defer collector.decision_mutex.unlock();
    collector.writeDecision(expr, coord, values) catch |err| {
        collector.setFirstError(err);
    };
}

fn activeCollector() ?*Collector {
    const ptr = active_collector_ptr.load(.acquire);
    if (ptr == 0) return null;
    return @ptrFromInt(ptr);
}

fn createTable(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    name: []const u8,
    columns: []const Parquet.ColumnDef,
) !Parquet.TableWriter {
    const file = try createOutputFile(allocator, output_dir, name);
    errdefer file.close();
    return Parquet.TableWriter.init(allocator, file, columns, .{});
}

fn writeExpressionCatalog(allocator: std.mem.Allocator, output_dir: []const u8) !void {
    var table = try createTable(
        allocator,
        output_dir,
        "expression_catalog.parquet",
        catalog_columns[0..],
    );
    defer table.deinit();

    for (expressions) |expression| {
        try table.appendInt32(0, exprId(expression.expr));
        try table.appendBytes(1, expression.expr_name);
        try table.appendBytes(2, expression.row_table);
        try table.appendBytes(3, expression.subsystem);
        try table.appendBytes(4, expression.equation);
        try table.appendBytes(5, expression.result_name);
        try table.appendBytes(6, expression.inputs);
        try table.appendBytes(7, expression.units);
        try table.appendBytes(8, expression.source_file);
        try table.appendBytes(9, expression.function);
        try table.appendBytes(10, expression.capture_reason);
        try table.finishRow();
    }
    try table.close();
}

fn createOutputFile(allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.fs.cwd().createFile(path, .{ .truncate = true });
}

fn exprId(expr: Expr) i32 {
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

fn boolInt(value: bool) i32 {
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
