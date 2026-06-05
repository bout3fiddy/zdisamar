const std = @import("std");
const internal = @import("internal");

const InstrumentGrid = internal.forward_model.instrument_grid;
const o2a_reference = internal.o2a_reference;
const RadiativeTransfer = internal.forward_model.radiative_transfer;
const Trace = internal.forward_model.performance_trace;

// migration note: Zig 0.15.2 trace CLI -----------------------------------------------------------|
// This retained trace harness intentionally uses the Zig 0.15.2 process, timer, and file APIs.    |
// The abandoned 0.16 migration routed it through std.process.Init and std.Io runtime plumbing.    |
// end migration note: Zig 0.15.2 trace CLI -------------------------------------------------------|
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

// instrumentation: LABOS trace harness
// captures: prepare/forward/copy wall time and optional ztracy zones
// why: inspect forward-model phase shape at the retained session boundary.
// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage:
//     output_dir=16 B, cached_repeats=8 B, output_dir_set=1 B, derivative_sweep=1 B, jacobian=1 B,
//     phase_timing=1 B, trace_case=1 B; padding: 3 B (24 bits)
//   unused bits: 24 padding + 28 bool-storage slack = 52 bits
//   out-of-line: output_dir carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above
const Config = struct {
    output_dir: []const u8 = default_labos_trace_output_dir,
    cached_repeats: usize = default_cached_repeats,
    output_dir_set: bool = false,
    derivative_sweep: bool = false,
    jacobian: bool = false,
    phase_timing: bool = true,
    trace_case: TraceCase = .default,
};

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: name=16 B, state_label=16 B, states=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: name, state_label, states carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
const TraceVariant = struct {
    name: []const u8,
    state_label: []const u8,
    states: []const RadiativeTransfer.Jacobian.State = &.{},
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

const ProductRunSummary = struct {
    forward_ns: u64,
    result_copy_ns: u64,
    summary: InstrumentGrid.InstrumentGridSummary,
    phase_timing: InstrumentGrid.storage.TracePhaseTiming,

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

    // instrumentation: trace frame
    // captures: one harness run boundary
    // why: align timeline messages with summary timing.
    const main_zone = Trace.staticZone(@src(), "trace_cli.main");
    defer main_zone.end();

    // instrumentation: trace frame markers
    // captures: start/end messages and frame boundaries
    // why: make the CLI run easy to find in Tracy captures.
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
    const input = switch (config.trace_case) {
        .default => o2a_reference.defaultInput(),
        .benchmark_jacobian => o2a_reference.benchmarkJacobianInput(),
    };
    var prepared_case = prepared_case: {

        // instrumentation: trace zone
        // captures: O2 A input preparation
        // why: separate setup cost from RTM execution.
        const zone = Trace.staticZone(@src(), "trace_cli.prepare_case");
        defer zone.end();
        break :prepared_case try o2a_reference.prepareResolvedVendorO2ACase(
            allocator,
            &input,
        );
    };
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
        config.phase_timing,
    );
}

fn runSingleTrace(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    prepare_ns: u64,
    prepared_case: anytype,
    case_label: []const u8,
    include_jacobian: bool,
    cached_repeats: usize,
    phase_timing_enabled: bool,
) !void {

    // instrumentation: trace zone
    // captures: first-use and repeated cached forward product runs
    // why: measure the retained LABOS bottleneck boundary and the session-cache boundary.
    const zone = Trace.staticZone(@src(), "trace_cli.single_trace");
    defer zone.end();

    var storage: InstrumentGrid.ProductStorage = .{};
    defer storage.deinit(allocator);

    var rtm_config = prepared_case.rtm_config;
    var derivative_states: []const u8 = "none";
    if (include_jacobian) {
        rtm_config = derivativeSolveConfig(prepared_case.rtm_config, benchmark_jacobian_variant);
        derivative_states = benchmark_jacobian_variant.state_label;
    }
    const output_states = if (include_jacobian) benchmark_jacobian_variant.states else &.{};

    const first_run = try runProductTrace(
        "trace_cli.simulate_product",
        allocator,
        &storage,
        &prepared_case.scene,
        rtm_config,
        &prepared_case.prepared,
        output_states,
        phase_timing_enabled,
    );

    const cached_runs = try allocator.alloc(ProductRunSummary, cached_repeats);
    defer allocator.free(cached_runs);
    for (cached_runs) |*cached_run| {
        cached_run.* = try runProductTrace(
            "trace_cli.simulate_product.cached",
            allocator,
            &storage,
            &prepared_case.scene,
            rtm_config,
            &prepared_case.prepared,
            output_states,
            phase_timing_enabled,
        );
    }

    try writeSummary(
        output_dir,
        prepare_ns,
        first_run,
        cached_runs,
        case_label,
        derivative_states,
        phase_timing_enabled,
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
    storage: *InstrumentGrid.ProductStorage,
    scene: anytype,
    rtm_config: RadiativeTransfer.SolveConfig,
    prepared: anytype,
    output_states: []const RadiativeTransfer.Jacobian.State,
    phase_timing_enabled: bool,
) !ProductRunSummary {

    // instrumentation: trace phase clock
    // captures: simulation phases plus owned-result copy for one product run
    // why: match the session benchmark boundary while keeping the phase clock opt-in.
    var phase_timing: InstrumentGrid.storage.TracePhaseTiming = .{};
    if (phase_timing_enabled) {
        storage.setTracePhaseTiming(&phase_timing);
    }
    defer storage.clearTracePhaseTiming();

    var forward_timer = try std.time.Timer.start();
    const product = product: {

        // instrumentation: trace zone
        // captures: one instrument-grid product simulation
        // why: isolate RTM work from owned-output copy at the session boundary.
        const simulate_zone = Trace.staticZone(@src(), zone_name);
        defer simulate_zone.end();
        break :product try InstrumentGrid.simulateProductWithWorkspace(
            allocator,
            storage,
            scene,
            rtm_config,
            prepared,
        );
    };
    const forward_ns = forward_timer.read();

    var copy_timer = try std.time.Timer.start();
    var owned_product = if (output_states.len == 0)
        try product.toOwned(allocator)
    else
        try product.toOwnedWithJacobianStates(allocator, output_states);
    const result_copy_ns = copy_timer.read();
    defer owned_product.deinit(allocator);

    return .{
        .forward_ns = forward_ns,
        .result_copy_ns = result_copy_ns,
        .summary = product.summary,
        .phase_timing = phase_timing,
    };
}

fn runDerivativeSweep(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    prepare_ns: u64,
    prepared_case: anytype,
) !void {

    // instrumentation: trace sweep
    // captures: forward and Jacobian rtm_config variants
    // why: compare derivative-state cost at the same scene boundary.
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
        const rtm_config = derivativeSolveConfig(prepared_case.rtm_config, variant);
        var storage: InstrumentGrid.ProductStorage = .{};
        defer storage.deinit(allocator);

        var forward_timer = try std.time.Timer.start();
        const product = try InstrumentGrid.simulateProductWithWorkspace(
            allocator,
            &storage,
            &prepared_case.scene,
            rtm_config,
            &prepared_case.prepared,
        );
        const forward_ns = forward_timer.read();

        var copy_timer = try std.time.Timer.start();
        var owned_product = try product.toOwned(allocator);
        const result_copy_ns = copy_timer.read();
        defer owned_product.deinit(allocator);

        try writeVariantSummary(
            &summary_writer.interface,
            variant_index != 0,
            variant,
            forward_ns,
            result_copy_ns,
            product.summary,
        );
    }

    try summary_writer.interface.writeAll(
        \\  ]
        \\}
        \\
    );
    try summary_writer.interface.flush();

    std.debug.print(
        "wrote O2 A Jacobian trace sweep summary to {s} (variants={})\n",
        .{ output_dir, derivative_variants.len },
    );
}

fn derivativeSolveConfig(
    rtm_config: RadiativeTransfer.SolveConfig,
    variant: TraceVariant,
) RadiativeTransfer.SolveConfig {
    var resolved = rtm_config;
    if (variant.states.len == 0) {
        resolved.derivative_mode = .none;
        resolved.derivative_state_mask = 0;
        return resolved;
    }

    resolved.derivative_mode = .semi_analytical;
    var mask: RadiativeTransfer.Jacobian.StateMask = 0;
    for (variant.states) |state| mask |= RadiativeTransfer.Jacobian.stateMask(state);
    resolved.derivative_state_mask = RadiativeTransfer.Jacobian.sanitizedMask(mask);
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

        if (std.mem.eql(u8, arg, "--no-phase-timing")) {
            config.phase_timing = false;
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

fn writeVariantSummary(
    writer: *std.Io.Writer,
    needs_comma: bool,
    variant: TraceVariant,
    forward_ns: u64,
    result_copy_ns: u64,
    summary: InstrumentGrid.InstrumentGridSummary,
) !void {
    if (needs_comma) try writer.writeAll(",\n");
    const total_with_copy_ns = forward_ns + result_copy_ns;
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
            forward_ns,
            @as(f64, @floatFromInt(forward_ns)) / 1.0e9,
            result_copy_ns,
            @as(f64, @floatFromInt(result_copy_ns)) / 1.0e9,
            total_with_copy_ns,
            @as(f64, @floatFromInt(total_with_copy_ns)) / 1.0e9,
            summary.sample_count,
            summary.wavelength_start_nm,
            summary.wavelength_end_nm,
            summary.mean_radiance,
            summary.mean_irradiance,
            summary.mean_reflectance,
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
    phase_timing_enabled: bool,
) !void {
    var file = try openOutputFile(std.heap.page_allocator, output_dir, "summary.json");
    defer file.close();

    const cached_run = cached_runs[0];
    var writer = file.writer(&.{});
    try writer.interface.print(
        \\{{
        \\  "trace_enabled": {},
        \\  "phase_timing_enabled": {},
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
            phase_timing_enabled,
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
        \\    "mean_reflectance": {e:.17},
        \\    "phase_timing_ns": {{
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
        },
    );
    try writePhaseTiming(writer, run.phase_timing);
    try writer.writeAll(
        \\    },
        \\    "labos_phase_timing": {
        \\
    );
    try writeLabosPhaseTiming(writer, run.phase_timing.labos);
    try writer.writeAll(
        \\    },
        \\    "labos_phase_counts": {
        \\
    );
    try writeLabosPhaseCounts(writer, run.phase_timing.labos);
    try writer.print(
        \\    }}
        \\  }}{s}
        \\
    ,
        .{if (needs_comma) "," else ""},
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
            \\      "total_with_copy_s": {d:.9},
            \\      "phase_timing_ns": {{
            \\
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
        try writePhaseTiming(writer, run.phase_timing);
        try writer.writeAll(
            \\      },
            \\      "labos_phase_timing": {
            \\
        );
        try writeLabosPhaseTiming(writer, run.phase_timing.labos);
        try writer.writeAll(
            \\      },
            \\      "labos_phase_counts": {
            \\
        );
        try writeLabosPhaseCounts(writer, run.phase_timing.labos);
        try writer.writeAll(
            \\      }
            \\    }
        );
    }
    try writer.writeAll(
        \\
        \\  ]
        \\
    );
}

fn writeLabosPhaseTiming(
    writer: *std.Io.Writer,
    labos_timing: RadiativeTransfer.labos.PhaseTiming,
) !void {
    try writeLabosPhaseCounter(writer, "execute", labos_timing.execute, true);
    try writeLabosPhaseCounter(writer, "attenuation_fill", labos_timing.attenuation_fill, true);
    try writeLabosPhaseCounter(writer, "fourier_loop", labos_timing.fourier_loop, true);
    try writeLabosPhaseCounter(writer, "plm_basis", labos_timing.plm_basis, true);
    try writeLabosPhaseCounter(writer, "rt_layer_build", labos_timing.rt_layer_build, true);
    try writeLabosPhaseCounter(writer, "rt_layer_phase_matrix", labos_timing.rt_layer_phase_matrix, true);
    try writeLabosPhaseCounter(writer, "rt_layer_doubling", labos_timing.rt_layer_doubling, true);
    try writeLabosPhaseCounter(writer, "fixed_qseries_work", labos_timing.fixed_qseries_work, true);
    try writeLabosPhaseCounter(writer, "fixed_rd_update", labos_timing.fixed_rd_update, true);
    try writeLabosPhaseCounter(writer, "fixed_tu_update", labos_timing.fixed_tu_update, true);
    try writeLabosPhaseCounter(writer, "fixed_td_update", labos_timing.fixed_td_update, true);
    try writeLabosPhaseCounter(writer, "orders_total", labos_timing.orders_total, true);
    try writeLabosPhaseCounter(writer, "orders_initial_sources", labos_timing.orders_initial_sources, true);
    try writeLabosPhaseCounter(writer, "orders_initial_transport", labos_timing.orders_initial_transport, true);
    try writeLabosPhaseCounter(writer, "orders_local_down", labos_timing.orders_local_down, true);
    try writeLabosPhaseCounter(writer, "orders_local_up", labos_timing.orders_local_up, true);
    try writeLabosPhaseCounter(writer, "orders_transport", labos_timing.orders_transport, true);
    try writeLabosPhaseCounter(writer, "orders_accumulate", labos_timing.orders_accumulate, true);
    try writeLabosPhaseCounter(writer, "reflectance_integral", labos_timing.reflectance_integral, false);
}

fn writeLabosPhaseCounts(
    writer: *std.Io.Writer,
    labos_timing: RadiativeTransfer.labos.PhaseTiming,
) !void {
    try writeLabosPhaseCount(writer, "fixed_doubling_steps", labos_timing.fixed_doubling_steps, true);
    try writeLabosPhaseCount(writer, "fixed_qseries_skipped", labos_timing.fixed_qseries_skipped, true);
    try writeLabosPhaseCount(writer, "fixed_qseries_retained", labos_timing.fixed_qseries_retained, true);
    try writeLabosPhaseCount(writer, "fixed_rd_skipped", labos_timing.fixed_rd_skipped, true);
    try writeLabosPhaseCount(writer, "fixed_rd_retained", labos_timing.fixed_rd_retained, true);
    try writeLabosPhaseCount(writer, "fixed_tu_skipped", labos_timing.fixed_tu_skipped, true);
    try writeLabosPhaseCount(writer, "fixed_tu_retained", labos_timing.fixed_tu_retained, true);
    try writeLabosPhaseCount(writer, "fixed_td_skipped", labos_timing.fixed_td_skipped, true);
    try writeLabosPhaseCount(writer, "fixed_td_retained", labos_timing.fixed_td_retained, false);
}

fn writeLabosPhaseCount(
    writer: *std.Io.Writer,
    name: []const u8,
    counter: anytype,
    needs_comma: bool,
) !void {
    try writer.print(
        \\      "{s}": {}{s}
        \\
    ,
        .{
            name,
            counter.count,
            if (needs_comma) "," else "",
        },
    );
}

fn writeLabosPhaseCounter(
    writer: *std.Io.Writer,
    name: []const u8,
    counter: anytype,
    needs_comma: bool,
) !void {
    const mean_ns = if (counter.count == 0)
        0.0
    else
        @as(f64, @floatFromInt(counter.ns)) / @as(f64, @floatFromInt(counter.count));
    try writer.print(
        \\      "{s}": {{"ns": {}, "count": {}, "mean_ns": {d:.3}}}{s}
        \\
    ,
        .{
            name,
            counter.ns,
            counter.count,
            mean_ns,
            if (needs_comma) "," else "",
        },
    );
}

fn writePhaseTiming(
    writer: *std.Io.Writer,
    phase_timing: InstrumentGrid.storage.TracePhaseTiming,
) !void {
    const radiance_fill_ns =
        phase_timing.radiance_cache_integration_ns +
        phase_timing.radiance_convolution_ns +
        phase_timing.radiance_postprocess_ns;
    const irradiance_fill_ns =
        phase_timing.irradiance_sampling_ns +
        phase_timing.irradiance_convolution_ns +
        phase_timing.irradiance_postprocess_ns;
    try writer.print(
        \\      "wavelength_sampling": {},
        \\      "forward_miss_collection": {},
        \\      "profile_spectroscopy_cache": {},
        \\      "forward_prefetch": {},
        \\      "radiance_cache_integration": {},
        \\      "radiance_convolution": {},
        \\      "radiance_postprocess": {},
        \\      "radiance_fill": {},
        \\      "irradiance_sampling": {},
        \\      "irradiance_convolution": {},
        \\      "irradiance_postprocess": {},
        \\      "irradiance_fill": {},
        \\      "reflectance_assembly": {},
        \\      "jacobian_processing": {}
        \\
    ,
        .{
            phase_timing.wavelength_sampling_ns,
            phase_timing.forward_miss_collection_ns,
            phase_timing.profile_spectroscopy_cache_ns,
            phase_timing.forward_prefetch_ns,
            phase_timing.radiance_cache_integration_ns,
            phase_timing.radiance_convolution_ns,
            phase_timing.radiance_postprocess_ns,
            radiance_fill_ns,
            phase_timing.irradiance_sampling_ns,
            phase_timing.irradiance_convolution_ns,
            phase_timing.irradiance_postprocess_ns,
            irradiance_fill_ns,
            phase_timing.reflectance_assembly_ns,
            phase_timing.jacobian_processing_ns,
        },
    );
}
