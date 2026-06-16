const std = @import("std");
const internal = @import("internal");

const CostTiming = internal.instrumentation.cost_timing;
const Jacobian = internal.rtm.jacobian_states;
const Trace = internal.instrumentation.trace;
const zdisamar = internal.public;

const default_labos_trace_output_dir = "scaffolding/instrumentation/trace/evidence/labos-bottleneck";
const default_jacobian_trace_output_dir = "scaffolding/instrumentation/trace/evidence/o2a-jacobian-trace";
const default_cached_repeats: usize = 3;

const TraceCase = enum {
    default,
    benchmark_jacobian,

    fn label(self: TraceCase) []const u8 {
        return switch (self) {
            .default => "default",
            .benchmark_jacobian => "benchmark_jacobian",
        };
    }
};

const Config = struct {
    output_dir: []const u8 = default_labos_trace_output_dir,
    cached_repeats: usize = default_cached_repeats,
    output_dir_set: bool = false,
    derivative_sweep: bool = false,
    jacobian: bool = false,
    cost_timing: bool = false,
    trace_case: TraceCase = .default,
};

const TraceVariant = struct {
    name: []const u8,
    state_label: []const u8,
    states: []const Jacobian.State = &.{},
};

const derivative_variants = [_]TraceVariant{
    .{
        .name = "forward_only",
        .state_label = "none",
    },
    .{
        .name = "aerosol_optical_depth",
        .state_label = "aerosol_optical_depth",
        .states = &.{.aerosol_optical_depth},
    },
    .{
        .name = "aerosol_layer_pressure",
        .state_label = "aerosol_layer_mid_pressure_hpa",
        .states = &.{.aerosol_layer_mid_pressure_hpa},
    },
    .{
        .name = "aerosol_two_state",
        .state_label = "aerosol_optical_depth+aerosol_layer_mid_pressure_hpa",
        .states = &.{ .aerosol_optical_depth, .aerosol_layer_mid_pressure_hpa },
    },
};

const benchmark_jacobian_variant = TraceVariant{
    .name = "benchmark_jacobian",
    .state_label = "aerosol_optical_depth+aerosol_layer_mid_pressure_hpa",
    .states = &.{ .aerosol_optical_depth, .aerosol_layer_mid_pressure_hpa },
};

const PreparedTraceCase = struct {
    case: zdisamar.O2Case,
    prepared: zdisamar.PreparedO2A,
    session: zdisamar.O2SessionMemory,
    solve_config: zdisamar.SolveConfig,

    fn deinit(self: *PreparedTraceCase, allocator: std.mem.Allocator) void {
        self.session.deinit(allocator);
        self.prepared.deinit(allocator);
        self.* = undefined;
    }
};

const ProductSummary = struct {
    sample_count: usize,
    wavelength_start_nm: f64,
    wavelength_end_nm: f64,
    mean_radiance: f64,
    mean_irradiance: f64,
    mean_reflectance: f64,
};

const ProductRunSummary = struct {
    forward_ns: u64,
    result_copy_ns: u64,
    summary: ProductSummary,

    fn totalWithCopyNs(self: ProductRunSummary) u64 {
        return self.forward_ns + self.result_copy_ns;
    }
};

pub fn main() !void {
    return mainInner() catch |err| {
        std.debug.print("labos-bottleneck-trace failed: {}\n", .{err});
        return err;
    };
}

fn mainInner() !void {
    const main_zone = Trace.staticZone(@src(), "trace_cli.main");
    defer main_zone.end();

    Trace.message("zdisamar labos trace start");
    Trace.frameMark();
    defer Trace.frameMark();
    defer Trace.message("zdisamar labos trace end");

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var config = try parseArgs(args);
    if (config.derivative_sweep and !config.output_dir_set) {
        config.output_dir = default_jacobian_trace_output_dir;
    }
    try std.fs.cwd().makePath(config.output_dir);

    var prepare_timer = try std.time.Timer.start();
    var prepared_case = try prepareTraceCase(allocator, config.trace_case);
    const prepare_ns = prepare_timer.read();
    defer prepared_case.deinit(allocator);

    if (config.derivative_sweep) {
        try runDerivativeSweep(allocator, config.output_dir, prepare_ns, &prepared_case);
        return;
    }

    try runSingleTrace(
        allocator,
        config.output_dir,
        prepare_ns,
        &prepared_case,
        config.trace_case.label(),
        config.jacobian,
        config.cached_repeats,
        config.cost_timing,
    );
}

fn prepareTraceCase(allocator: std.mem.Allocator, trace_case: TraceCase) !PreparedTraceCase {
    var case = zdisamar.defaultO2Case();
    if (trace_case == .benchmark_jacobian) {
        case.spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 759.0,
            .sample_count = 101,
        };
    }

    var prepared = try zdisamar.prepareO2A(allocator, case);
    errdefer prepared.deinit(allocator);

    return .{
        .case = case,
        .prepared = prepared,
        .session = zdisamar.initO2SessionMemory(allocator),
        .solve_config = forwardSolveConfig(case),
    };
}

fn forwardSolveConfig(case: zdisamar.O2Case) zdisamar.SolveConfig {
    var solve_config = zdisamar.o2aSolveConfig(case);
    solve_config.derivative_mode = .none;
    solve_config.derivative_state_mask = 0;
    return solve_config;
}

fn runSingleTrace(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    prepare_ns: u64,
    prepared_case: *PreparedTraceCase,
    case_label: []const u8,
    include_jacobian: bool,
    cached_repeats: usize,
    cost_timing_requested: bool,
) !void {
    const zone = Trace.staticZone(@src(), "trace_cli.single_trace");
    defer zone.end();

    var solve_config = prepared_case.solve_config;
    var derivative_states: []const u8 = "none";
    if (include_jacobian) {
        solve_config = derivativeSolveConfig(prepared_case.solve_config, benchmark_jacobian_variant);
        derivative_states = benchmark_jacobian_variant.state_label;
    }

    const first_run = try runProductTrace(
        "trace_cli.simulate_product",
        allocator,
        &prepared_case.session,
        &prepared_case.prepared,
        solve_config,
    );

    const cached_runs = try allocator.alloc(ProductRunSummary, cached_repeats);
    defer allocator.free(cached_runs);
    for (cached_runs) |*cached_run| {
        cached_run.* = try runProductTrace(
            "trace_cli.simulate_product.cached",
            allocator,
            &prepared_case.session,
            &prepared_case.prepared,
            solve_config,
        );
    }

    try writeSummary(
        output_dir,
        prepare_ns,
        first_run,
        cached_runs,
        case_label,
        derivative_states,
        cost_timing_requested and CostTiming.enabled,
    );

    std.debug.print(
        "wrote LABOS bottleneck trace summary to {s} (first_s={d:.6}, cached_s={d:.6}, repeats={})\n",
        .{
            output_dir,
            @as(f64, @floatFromInt(first_run.forward_ns)) / 1.0e9,
            @as(f64, @floatFromInt(cached_runs[0].forward_ns)) / 1.0e9,
            cached_runs.len,
        },
    );
}

fn runProductTrace(
    comptime zone_name: [*:0]const u8,
    allocator: std.mem.Allocator,
    session: *zdisamar.O2SessionMemory,
    prepared: *const zdisamar.PreparedO2A,
    solve_config: zdisamar.SolveConfig,
) !ProductRunSummary {
    var forward_timer = try std.time.Timer.start();
    var result = result: {
        const simulate_zone = Trace.staticZone(@src(), zone_name);
        defer simulate_zone.end();
        break :result try zdisamar.runO2AWithSessionMemory(
            allocator,
            session,
            prepared,
            solve_config,
        );
    };
    const forward_ns = forward_timer.read();
    defer result.deinit(allocator);

    return .{
        .forward_ns = forward_ns,
        .result_copy_ns = 0,
        .summary = summarizeProduct(result),
    };
}

fn runDerivativeSweep(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    prepare_ns: u64,
    prepared_case: *const PreparedTraceCase,
) !void {
    const zone = Trace.staticZone(@src(), "trace_cli.derivative_sweep");
    defer zone.end();

    var summary_file = try openOutputFile(std.heap.page_allocator, output_dir, "summary.json");
    defer summary_file.close();
    var summary_writer = summary_file.writer(&.{});

    try summary_writer.interface.print(
        \\{{
        \\  "trace_enabled": {},
        \\  "prepare_ns": {},
        \\  "prepare_s": {d:.9},
        \\  "variants": [
        \\
    ,
        .{
            Trace.enabled,
            prepare_ns,
            @as(f64, @floatFromInt(prepare_ns)) / 1.0e9,
        },
    );

    for (derivative_variants, 0..) |variant, variant_index| {
        var session = zdisamar.initO2SessionMemory(allocator);
        defer session.deinit(allocator);

        const solve_config = derivativeSolveConfig(prepared_case.solve_config, variant);
        const run = try runProductTrace(
            "trace_cli.simulate_product.variant",
            allocator,
            &session,
            &prepared_case.prepared,
            solve_config,
        );
        try writeVariantSummary(
            &summary_writer.interface,
            variant_index != 0,
            variant,
            run,
        );
    }

    try summary_writer.interface.writeAll(
        \\  ]
        \\}
        \\
    );
    try summary_writer.interface.flush();

    std.debug.print(
        "wrote Jacobian trace sweep summary to {s} (variants={})\n",
        .{ output_dir, derivative_variants.len },
    );
}

fn derivativeSolveConfig(
    solve_config: zdisamar.SolveConfig,
    variant: TraceVariant,
) zdisamar.SolveConfig {
    var resolved = solve_config;
    if (variant.states.len == 0) {
        resolved.derivative_mode = .none;
        resolved.derivative_state_mask = 0;
        return resolved;
    }

    resolved.derivative_mode = .semi_analytical;
    var mask: Jacobian.StateMask = 0;
    for (variant.states) |state| mask |= Jacobian.stateMask(state);
    resolved.derivative_state_mask = Jacobian.sanitizedMask(mask);
    return resolved;
}

fn parseArgs(args: []const []const u8) !Config {
    var config: Config = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];

        if (std.mem.eql(u8, arg, "--output-dir")) {
            index += 1;
            if (index >= args.len) return error.MissingOutputDir;

            config.output_dir = args[index];
            config.output_dir_set = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--derivative-sweep")) {
            config.derivative_sweep = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--jacobian")) {
            config.jacobian = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--no-cost-timing")) {
            config.cost_timing = false;
            continue;
        }

        if (std.mem.eql(u8, arg, "--case")) {
            index += 1;
            if (index >= args.len) return error.MissingTraceCase;

            if (std.mem.eql(u8, args[index], "default")) {
                config.trace_case = .default;
                continue;
            }

            if (std.mem.eql(u8, args[index], "benchmark-jacobian")) {
                config.trace_case = .benchmark_jacobian;
                continue;
            }

            return error.UnsupportedTraceCase;
        }

        if (std.mem.eql(u8, arg, "--cached-repeats")) {
            index += 1;
            if (index >= args.len) return error.MissingCachedRepeats;

            config.cached_repeats = try std.fmt.parseUnsigned(usize, args[index], 10);
            if (config.cached_repeats == 0) return error.InvalidCachedRepeats;
            continue;
        }

        return error.UnsupportedArgument;
    }

    return config;
}

fn summarizeProduct(result: zdisamar.O2SpectrumRunResult) ProductSummary {
    const spectrum = result.spectrum;
    const assembly = result.summary.reflectance_assembly;
    const sample_count = spectrum.sampleCount();
    return .{
        .sample_count = sample_count,
        .wavelength_start_nm = if (sample_count == 0) 0.0 else spectrum.wavelength_nm[0],
        .wavelength_end_nm = if (sample_count == 0) 0.0 else spectrum.wavelength_nm[sample_count - 1],
        .mean_radiance = mean(assembly.radiance_sum, assembly.sample_count),
        .mean_irradiance = mean(assembly.irradiance_sum, assembly.sample_count),
        .mean_reflectance = mean(assembly.reflectance_sum, assembly.sample_count),
    };
}

fn mean(sum: f64, count: usize) f64 {
    if (count == 0) return 0.0;
    return sum / @as(f64, @floatFromInt(count));
}

fn writeVariantSummary(
    writer: *std.Io.Writer,
    needs_comma: bool,
    variant: TraceVariant,
    run: ProductRunSummary,
) !void {
    if (needs_comma) try writer.writeAll(",\n");
    try writer.print(
        \\    {{
        \\      "variant": "{s}",
        \\      "derivative_states": "{s}",
        \\      "forward_wall_ns": {},
        \\      "forward_wall_s": {d:.9},
        \\      "result_copy_ns": {},
        \\      "result_copy_s": {d:.9},
        \\      "total_with_copy_ns": {},
        \\      "total_with_copy_s": {d:.9},
        \\      "sample_count": {},
        \\      "wavelength_start_nm": {d:.8},
        \\      "wavelength_end_nm": {d:.8},
        \\      "mean_radiance": {e:.17},
        \\      "mean_irradiance": {e:.17},
        \\      "mean_reflectance": {e:.17}
        \\    }}
    ,
        .{
            variant.name,
            variant.state_label,
            run.forward_ns,
            @as(f64, @floatFromInt(run.forward_ns)) / 1.0e9,
            run.result_copy_ns,
            @as(f64, @floatFromInt(run.result_copy_ns)) / 1.0e9,
            run.totalWithCopyNs(),
            @as(f64, @floatFromInt(run.totalWithCopyNs())) / 1.0e9,
            run.summary.sample_count,
            run.summary.wavelength_start_nm,
            run.summary.wavelength_end_nm,
            run.summary.mean_radiance,
            run.summary.mean_irradiance,
            run.summary.mean_reflectance,
        },
    );
}

fn openOutputFile(allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.fs.cwd().createFile(path, .{ .truncate = true });
}

fn writeSummary(
    output_dir: []const u8,
    prepare_ns: u64,
    first_run: ProductRunSummary,
    cached_runs: []const ProductRunSummary,
    case_label: []const u8,
    derivative_states: []const u8,
    cost_timing_enabled: bool,
) !void {
    var file = try openOutputFile(std.heap.page_allocator, output_dir, "summary.json");
    defer file.close();

    const cached_run = cached_runs[0];
    var writer = file.writer(&.{});
    try writer.interface.print(
        \\{{
        \\  "trace_enabled": {},
        \\  "cost_timing_enabled": {},
        \\  "case": "{s}",
        \\  "derivative_states": "{s}",
        \\  "prepare_ns": {},
        \\  "forward_wall_ns": {},
        \\  "cached_forward_wall_ns": {},
        \\  "forward_result_copy_ns": {},
        \\  "cached_result_copy_ns": {},
        \\  "forward_total_with_copy_ns": {},
        \\  "cached_total_with_copy_ns": {},
        \\  "cached_repeat_count": {},
        \\  "prepare_s": {d:.9},
        \\  "forward_wall_s": {d:.9},
        \\  "cached_forward_wall_s": {d:.9},
        \\  "forward_result_copy_s": {d:.9},
        \\  "cached_result_copy_s": {d:.9},
        \\  "forward_total_with_copy_s": {d:.9},
        \\  "cached_total_with_copy_s": {d:.9},
        \\  "sample_count": {},
        \\  "wavelength_start_nm": {d:.8},
        \\  "wavelength_end_nm": {d:.8},
        \\  "mean_radiance": {e:.17},
        \\  "mean_irradiance": {e:.17},
        \\  "mean_reflectance": {e:.17},
        \\
    ,
        .{
            Trace.enabled,
            cost_timing_enabled,
            case_label,
            derivative_states,
            prepare_ns,
            first_run.forward_ns,
            cached_run.forward_ns,
            first_run.result_copy_ns,
            cached_run.result_copy_ns,
            first_run.totalWithCopyNs(),
            cached_run.totalWithCopyNs(),
            cached_runs.len,
            @as(f64, @floatFromInt(prepare_ns)) / 1.0e9,
            @as(f64, @floatFromInt(first_run.forward_ns)) / 1.0e9,
            @as(f64, @floatFromInt(cached_run.forward_ns)) / 1.0e9,
            @as(f64, @floatFromInt(first_run.result_copy_ns)) / 1.0e9,
            @as(f64, @floatFromInt(cached_run.result_copy_ns)) / 1.0e9,
            @as(f64, @floatFromInt(first_run.totalWithCopyNs())) / 1.0e9,
            @as(f64, @floatFromInt(cached_run.totalWithCopyNs())) / 1.0e9,
            first_run.summary.sample_count,
            first_run.summary.wavelength_start_nm,
            first_run.summary.wavelength_end_nm,
            first_run.summary.mean_radiance,
            first_run.summary.mean_irradiance,
            first_run.summary.mean_reflectance,
        },
    );
    try writeProductRunSummary(
        &writer.interface,
        "first_run",
        first_run,
        true,
    );
    try writeProductRunSummary(
        &writer.interface,
        "cached_run",
        cached_run,
        false,
    );
    try writeCachedRuns(&writer.interface, cached_runs);
    try writer.interface.writeAll(
        \\}
        \\
    );
    try writer.interface.flush();
}

fn writeProductRunSummary(
    writer: *std.Io.Writer,
    name: []const u8,
    run: ProductRunSummary,
    needs_comma: bool,
) !void {
    try writer.print(
        \\  "{s}": {{
        \\    "forward_wall_ns": {},
        \\    "forward_wall_s": {d:.9},
        \\    "result_copy_ns": {},
        \\    "result_copy_s": {d:.9},
        \\    "total_with_copy_ns": {},
        \\    "total_with_copy_s": {d:.9},
        \\    "sample_count": {},
        \\    "wavelength_start_nm": {d:.8},
        \\    "wavelength_end_nm": {d:.8},
        \\    "mean_radiance": {e:.17},
        \\    "mean_irradiance": {e:.17},
        \\    "mean_reflectance": {e:.17}
        \\  }}{s}
        \\
    ,
        .{
            name,
            run.forward_ns,
            @as(f64, @floatFromInt(run.forward_ns)) / 1.0e9,
            run.result_copy_ns,
            @as(f64, @floatFromInt(run.result_copy_ns)) / 1.0e9,
            run.totalWithCopyNs(),
            @as(f64, @floatFromInt(run.totalWithCopyNs())) / 1.0e9,
            run.summary.sample_count,
            run.summary.wavelength_start_nm,
            run.summary.wavelength_end_nm,
            run.summary.mean_radiance,
            run.summary.mean_irradiance,
            run.summary.mean_reflectance,
            if (needs_comma) "," else "",
        },
    );
}

fn writeCachedRuns(
    writer: *std.Io.Writer,
    cached_runs: []const ProductRunSummary,
) !void {
    try writer.writeAll(
        \\,
        \\  "cached_runs": [
        \\
    );
    for (cached_runs, 0..) |run, index| {
        if (index != 0) try writer.writeAll(",\n");
        try writer.print(
            \\    {{
            \\      "repeat": {},
            \\      "forward_wall_ns": {},
            \\      "forward_wall_s": {d:.9},
            \\      "result_copy_ns": {},
            \\      "result_copy_s": {d:.9},
            \\      "total_with_copy_ns": {},
            \\      "total_with_copy_s": {d:.9}
            \\    }}
        ,
            .{
                index + 1,
                run.forward_ns,
                @as(f64, @floatFromInt(run.forward_ns)) / 1.0e9,
                run.result_copy_ns,
                @as(f64, @floatFromInt(run.result_copy_ns)) / 1.0e9,
                run.totalWithCopyNs(),
                @as(f64, @floatFromInt(run.totalWithCopyNs())) / 1.0e9,
            },
        );
    }
    try writer.writeAll(
        \\
        \\  ]
        \\
    );
}
