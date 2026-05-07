const std = @import("std");
const internal = @import("internal");

const InstrumentGrid = internal.forward_model.instrument_grid;
const Trace = internal.forward_model.performance_trace;

const Config = struct {
    output_dir: []const u8 = "validation/outputs/performance/labos-bottleneck",
    case_yaml_path: []const u8 = internal.disamar_reference.yaml.default_yaml_path,
};

pub fn main() !void {
    return mainInner() catch |err| {
        std.debug.print("labos-bottleneck-trace failed: {}\n", .{err});
        return err;
    };
}

fn mainInner() !void {
    comptime {
        if (!Trace.enabled) @compileError("labos-bottleneck-trace must be built with enable_labos_trace=true");
    }

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const config = try parseArgs(args);
    try std.fs.cwd().makePath(config.output_dir);

    var prepare_timer = try std.time.Timer.start();
    var loaded = try internal.disamar_reference.yaml.loadResolvedCaseFromFile(
        allocator,
        config.case_yaml_path,
    );
    defer loaded.deinit();
    internal.disamar_reference.yaml.applyExecutionOverrides(&loaded.resolved, .{
        .spectral_grid = .{
            .start_nm = 755.0,
            .end_nm = 776.0,
            .sample_count = 701,
        },
        .adaptive_points_per_fwhm = 20,
        .adaptive_strong_line_min_divisions = 8,
        .adaptive_strong_line_max_divisions = 40,
        .line_mixing_factor = 1.0,
        .isotopes_sim = &.{ 1, 2, 3 },
        .threshold_line_sim = 3.0e-5,
        .cutoff_sim_cm1 = 200.0,
    });
    var prepared_case = try internal.disamar_reference.yaml.prepareResolvedVendorO2ACase(
        allocator,
        &loaded.resolved,
    );
    const prepare_ns = prepare_timer.read();
    defer prepared_case.deinit(allocator);

    var trace = Trace.Run.init();
    var implementations = internal.forward_model.implementations.exact();
    implementations.trace = &trace;

    var storage: InstrumentGrid.ProductStorage = .{};
    defer storage.deinit(allocator);

    var forward_timer = try std.time.Timer.start();
    const product = try InstrumentGrid.simulateProductWithWorkspace(
        allocator,
        &storage,
        &prepared_case.scene,
        prepared_case.route,
        &prepared_case.prepared,
        implementations,
    );
    const forward_ns = forward_timer.read();
    trace.setForwardWallNs(forward_ns);

    try writeSummary(config.output_dir, prepare_ns, forward_ns, product.summary, &trace);
    try writeSections(config.output_dir, &trace);
    try writeCounters(config.output_dir, &trace);
    try writeWorkerSections(config.output_dir, &trace);

    std.debug.print(
        "wrote LABOS bottleneck trace to {s} (forward_s={d:.6}, workers={})\n",
        .{
            config.output_dir,
            @as(f64, @floatFromInt(forward_ns)) / 1.0e9,
            trace.worker_count,
        },
    );
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
        } else if (std.mem.eql(u8, arg, "--case")) {
            index += 1;
            if (index >= args.len) return error.MissingCasePath;
            config.case_yaml_path = args[index];
        } else {
            return error.UnsupportedArgument;
        }
    }
    return config;
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
    trace: *const Trace.Run,
) !void {
    var file = try openOutputFile(std.heap.page_allocator, output_dir, "summary.json");
    defer file.close();

    var writer = file.writer(&.{});
    const labos_cpu_ns = trace.totalWorkerSectionNs(.labos_execute);
    const rt_layer_cpu_ns = trace.totalWorkerSectionNs(.rt_layer_build);
    const orders_cpu_ns = trace.totalWorkerSectionNs(.orders_total);
    const forward_input_cpu_ns = trace.totalWorkerSectionNs(.forward_input);
    try writer.interface.print(
        \\{{
        \\  "trace_enabled": true,
        \\  "prepare_ns": {},
        \\  "forward_wall_ns": {},
        \\  "prepare_s": {d:.9},
        \\  "forward_wall_s": {d:.9},
        \\  "worker_count": {},
        \\  "sample_count": {},
        \\  "wavelength_start_nm": {d:.8},
        \\  "wavelength_end_nm": {d:.8},
        \\  "mean_radiance": {e:.17},
        \\  "mean_irradiance": {e:.17},
        \\  "mean_reflectance": {e:.17},
        \\  "high_resolution_misses": {},
        \\  "fourier_terms": {},
        \\  "layer_visits": {},
        \\  "doubled_layers": {},
        \\  "doubling_steps": {},
        \\  "labos_execute_cpu_ns": {},
        \\  "rt_layer_build_cpu_ns": {},
        \\  "orders_cpu_ns": {},
        \\  "forward_input_cpu_ns": {}
        \\}}
        \\
    ,
        .{
            prepare_ns,
            forward_ns,
            @as(f64, @floatFromInt(prepare_ns)) / 1.0e9,
            @as(f64, @floatFromInt(forward_ns)) / 1.0e9,
            trace.worker_count,
            summary.sample_count,
            summary.wavelength_start_nm,
            summary.wavelength_end_nm,
            summary.mean_radiance,
            summary.mean_irradiance,
            summary.mean_reflectance,
            trace.totalCounter(.high_resolution_misses),
            trace.totalCounter(.fourier_terms),
            trace.totalCounter(.layer_visits),
            trace.totalCounter(.doubled_layers),
            trace.totalCounter(.doubling_steps),
            labos_cpu_ns,
            rt_layer_cpu_ns,
            orders_cpu_ns,
            forward_input_cpu_ns,
        },
    );
    try writer.interface.flush();
}

fn writeSections(output_dir: []const u8, trace: *const Trace.Run) !void {
    var file = try openOutputFile(std.heap.page_allocator, output_dir, "sections.csv");
    defer file.close();
    var writer = file.writer(&.{});
    defer writer.interface.flush() catch {};

    try writer.interface.writeAll("scope,section,ns,seconds,forward_wall_percent,labos_cpu_percent\n");
    const forward_wall = @max(trace.forward_wall_ns, 1);
    const labos_cpu = @max(trace.totalWorkerSectionNs(.labos_execute), 1);
    inline for (@typeInfo(Trace.Section).@"enum".fields) |field| {
        const section: Trace.Section = @enumFromInt(field.value);
        const wall_ns = trace.wall_sections_ns[@intFromEnum(section)];
        if (wall_ns != 0) {
            try writeSectionRow(&writer.interface, "wall", section, wall_ns, forward_wall, labos_cpu);
        }
        const cpu_ns = trace.totalWorkerSectionNs(section);
        if (cpu_ns != 0) {
            try writeSectionRow(&writer.interface, "worker_cpu", section, cpu_ns, forward_wall, labos_cpu);
        }
    }
}

fn writeSectionRow(
    writer: *std.Io.Writer,
    scope: []const u8,
    section: Trace.Section,
    ns: u64,
    forward_wall: u64,
    labos_cpu: u64,
) !void {
    const seconds = @as(f64, @floatFromInt(ns)) / 1.0e9;
    const forward_pct = 100.0 * @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(forward_wall));
    const labos_pct = 100.0 * @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(labos_cpu));
    try writer.print(
        "{s},{s},{},{d:.9},{d:.6},{d:.6}\n",
        .{ scope, section.name(), ns, seconds, forward_pct, labos_pct },
    );
}

fn writeCounters(output_dir: []const u8, trace: *const Trace.Run) !void {
    var file = try openOutputFile(std.heap.page_allocator, output_dir, "counters.csv");
    defer file.close();
    var writer = file.writer(&.{});
    defer writer.interface.flush() catch {};

    try writer.interface.writeAll("counter,count\n");
    inline for (@typeInfo(Trace.Counter).@"enum".fields) |field| {
        const counter: Trace.Counter = @enumFromInt(field.value);
        const count = trace.totalCounter(counter);
        if (count != 0) {
            try writer.interface.print("{s},{}\n", .{ counter.name(), count });
        }
    }
}

fn writeWorkerSections(output_dir: []const u8, trace: *const Trace.Run) !void {
    var file = try openOutputFile(std.heap.page_allocator, output_dir, "worker_sections.csv");
    defer file.close();
    var writer = file.writer(&.{});
    defer writer.interface.flush() catch {};

    try writer.interface.writeAll("worker_index,section,ns,seconds\n");
    for (trace.workers[0..trace.worker_count], 0..) |worker_state, worker_index| {
        inline for (@typeInfo(Trace.Section).@"enum".fields) |field| {
            const section: Trace.Section = @enumFromInt(field.value);
            const ns = worker_state.sections_ns[@intFromEnum(section)];
            if (ns != 0) {
                try writer.interface.print(
                    "{},{s},{},{d:.9}\n",
                    .{
                        worker_index,
                        section.name(),
                        ns,
                        @as(f64, @floatFromInt(ns)) / 1.0e9,
                    },
                );
            }
        }
    }
}
