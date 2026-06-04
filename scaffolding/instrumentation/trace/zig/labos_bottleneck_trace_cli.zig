const std = @import("std");
const internal = @import("internal");

const InstrumentGrid = internal.forward_model.instrument_grid;
const o2a_reference = internal.o2a_reference;
const RadiativeTransfer = internal.forward_model.radiative_transfer;
const Trace = internal.forward_model.performance_trace;

const default_labos_trace_output_dir = "scaffolding/instrumentation/trace/evidence/labos-bottleneck";
const default_jacobian_trace_output_dir = "scaffolding/instrumentation/trace/evidence/o2a-jacobian-trace";

// instrumentation: LABOS trace harness
// captures: prepare/forward wall time and optional ztracy zones
// why: inspect forward-model phase shape.
// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: output_dir=16 B, output_dir_set=1 B, derivative_sweep=1 B; padding: 6 B (48 bits)
//   unused bits: 48 padding + 14 bool-storage slack = 62 bits
//   out-of-line: output_dir carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total also includes referenced storage above
const Config = struct {
    output_dir: []const u8 = default_labos_trace_output_dir,
    output_dir_set: bool = false,
    derivative_sweep: bool = false,
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
    const input = o2a_reference.defaultInput();
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

    try runSingleTrace(allocator, config.output_dir, prepare_ns, &prepared_case);
}

fn runSingleTrace(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    prepare_ns: u64,
    prepared_case: anytype,
) !void {

    // instrumentation: trace zone
    // captures: single forward product run
    // why: measure the retained LABOS bottleneck boundary.
    const zone = Trace.staticZone(@src(), "trace_cli.single_trace");
    defer zone.end();

    var storage: InstrumentGrid.ProductStorage = .{};
    defer storage.deinit(allocator);

    var forward_timer = try std.time.Timer.start();
    const product = product: {

        // instrumentation: trace zone
        // captures: instrument-grid product simulation
        // why: isolate forward RTM work inside the harness.
        const simulate_zone = Trace.staticZone(@src(), "trace_cli.simulate_product");
        defer simulate_zone.end();
        break :product try InstrumentGrid.simulateProductWithWorkspace(
            allocator,
            &storage,
            &prepared_case.scene,
            prepared_case.rtm_config,
            &prepared_case.prepared,
        );
    };
    const forward_ns = forward_timer.read();

    try writeSummary(output_dir, prepare_ns, forward_ns, product.summary);

    std.debug.print(
        "wrote LABOS bottleneck trace summary to {s} (forward_s={d:.6})\n",
        .{
            output_dir,
            @as(f64, @floatFromInt(forward_ns)) / 1.0e9,
        },
    );
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
        } else if (std.mem.eql(u8, arg, "--derivative-sweep")) {
            config.derivative_sweep = true;
        } else {
            return error.UnsupportedArgument;
        }
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
    forward_ns: u64,
    summary: InstrumentGrid.InstrumentGridSummary,
) !void {
    var file = try openOutputFile(std.heap.page_allocator, output_dir, "summary.json");
    defer file.close();

    var writer = file.writer(&.{});
    try writer.interface.print(
        \\{{
        \\  "trace_enabled": {},
        \\  "prepare_ns": {},
        \\  "forward_wall_ns": {},
        \\  "prepare_s": {d:.9},
        \\  "forward_wall_s": {d:.9},
        \\  "sample_count": {},
        \\  "wavelength_start_nm": {d:.8},
        \\  "wavelength_end_nm": {d:.8},
        \\  "mean_radiance": {e:.17},
        \\  "mean_irradiance": {e:.17},
        \\  "mean_reflectance": {e:.17}
        \\}}
        \\
    ,
        .{
            Trace.enabled,
            prepare_ns,
            forward_ns,
            @as(f64, @floatFromInt(prepare_ns)) / 1.0e9,
            @as(f64, @floatFromInt(forward_ns)) / 1.0e9,
            summary.sample_count,
            summary.wavelength_start_nm,
            summary.wavelength_end_nm,
            summary.mean_radiance,
            summary.mean_irradiance,
            summary.mean_reflectance,
        },
    );
    try writer.interface.flush();
}
