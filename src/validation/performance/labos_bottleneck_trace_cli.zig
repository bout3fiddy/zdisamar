const std = @import("std");
const internal = @import("internal");

const InstrumentGrid = internal.forward_model.instrument_grid;
const RadiativeTransfer = internal.forward_model.radiative_transfer;
const Trace = internal.forward_model.performance_trace;

const default_jacobian_trace_output_dir = "validation/outputs/performance/o2a-jacobian-trace";

const Config = struct {
    output_dir: []const u8 = "validation/outputs/performance/labos-bottleneck",
    output_dir_set: bool = false,
    case_yaml_path: []const u8 = internal.disamar_reference.yaml.default_yaml_path,
    derivative_sweep: bool = false,
};

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
    comptime {
        if (!Trace.enabled) @compileError("labos-bottleneck-trace must be built with enable_labos_trace=true");
    }
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
    var loaded = loaded: {
        const zone = Trace.staticZone(@src(), "trace_cli.load_case");
        defer zone.end();
        break :loaded try internal.disamar_reference.yaml.loadResolvedCaseFromFile(
            allocator,
            config.case_yaml_path,
        );
    };
    defer loaded.deinit();
    {
        const zone = Trace.staticZone(@src(), "trace_cli.apply_overrides");
        defer zone.end();
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
    }
    var prepare_trace: internal.disamar_reference.metrics.O2APrepareTrace = .{};
    var prepared_case = prepared_case: {
        const zone = Trace.staticZone(@src(), "trace_cli.prepare_case");
        defer zone.end();
        break :prepared_case try internal.disamar_reference.metrics.prepareResolvedVendorO2ACaseWithTrace(
            allocator,
            &loaded.resolved,
            &prepare_trace,
        );
    };
    const prepare_ns = prepare_timer.read();
    defer prepared_case.deinit(allocator);

    if (config.derivative_sweep) {
        try runDerivativeSweep(allocator, config.output_dir, prepare_ns, &prepared_case);
        return;
    }

    try runSingleTrace(allocator, config.output_dir, prepare_ns, prepare_trace, &prepared_case);
}

fn runSingleTrace(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    prepare_ns: u64,
    prepare_trace: internal.disamar_reference.metrics.O2APrepareTrace,
    prepared_case: anytype,
) !void {
    const zone = Trace.staticZone(@src(), "trace_cli.single_trace");
    defer zone.end();

    var trace = Trace.Run.init();
    var implementations = internal.forward_model.implementations.exact();
    implementations.trace = &trace;

    var storage: InstrumentGrid.ProductStorage = .{};
    defer storage.deinit(allocator);

    var forward_timer = try std.time.Timer.start();
    const product = product: {
        const simulate_zone = Trace.staticZone(@src(), "trace_cli.simulate_product");
        defer simulate_zone.end();
        break :product try InstrumentGrid.simulateProductWithWorkspace(
            allocator,
            &storage,
            &prepared_case.scene,
            prepared_case.route,
            &prepared_case.prepared,
            implementations,
        );
    };
    const forward_ns = forward_timer.read();
    trace.setForwardWallNs(forward_ns);

    try writeSummary(output_dir, prepare_ns, prepare_trace, forward_ns, product.summary, &trace);
    try writeSections(output_dir, &trace);
    try writeCounters(output_dir, &trace);
    try writeWorkerSections(output_dir, &trace);

    std.debug.print(
        "wrote LABOS bottleneck trace to {s} (forward_s={d:.6}, workers={})\n",
        .{
            output_dir,
            @as(f64, @floatFromInt(forward_ns)) / 1.0e9,
            trace.worker_count,
        },
    );
}

fn runDerivativeSweep(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    prepare_ns: u64,
    prepared_case: anytype,
) !void {
    var summary_file = try openOutputFile(std.heap.page_allocator, output_dir, "summary.json");
    defer summary_file.close();
    var summary_writer = summary_file.writer(&.{});

    var sections_file = try openOutputFile(std.heap.page_allocator, output_dir, "sections.csv");
    defer sections_file.close();
    var sections_writer = sections_file.writer(&.{});
    defer sections_writer.interface.flush() catch {};
    try sections_writer.interface.writeAll("variant,scope,section,ns,seconds,forward_wall_percent,labos_cpu_percent\n");

    var counters_file = try openOutputFile(std.heap.page_allocator, output_dir, "counters.csv");
    defer counters_file.close();
    var counters_writer = counters_file.writer(&.{});
    defer counters_writer.interface.flush() catch {};
    try counters_writer.interface.writeAll("variant,counter,count\n");

    var worker_sections_file = try openOutputFile(std.heap.page_allocator, output_dir, "worker_sections.csv");
    defer worker_sections_file.close();
    var worker_sections_writer = worker_sections_file.writer(&.{});
    defer worker_sections_writer.interface.flush() catch {};
    try worker_sections_writer.interface.writeAll("variant,worker_index,section,ns,seconds\n");

    try summary_writer.interface.print(
        \\{{
        \\  "trace_enabled": true,
        \\  "prepare_ns": {},
        \\  "prepare_s": {d:.9},
        \\  "variants": [
        \\
    ,
        .{
            prepare_ns,
            @as(f64, @floatFromInt(prepare_ns)) / 1.0e9,
        },
    );

    for (derivative_variants, 0..) |variant, variant_index| {
        var trace = Trace.Run.init();
        var implementations = internal.forward_model.implementations.exact();
        implementations.trace = &trace;

        const route = derivativeRoute(prepared_case.route, variant);
        var storage: InstrumentGrid.ProductStorage = .{};
        defer storage.deinit(allocator);

        var forward_timer = try std.time.Timer.start();
        const product = try InstrumentGrid.simulateProductWithWorkspace(
            allocator,
            &storage,
            &prepared_case.scene,
            route,
            &prepared_case.prepared,
            implementations,
        );
        const forward_ns = forward_timer.read();
        trace.setForwardWallNs(forward_ns);

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
            &trace,
        );
        try writeVariantSections(&sections_writer.interface, variant.name, &trace);
        try writeVariantCounters(&counters_writer.interface, variant.name, &trace);
        try writeVariantWorkerSections(&worker_sections_writer.interface, variant.name, &trace);
    }

    try summary_writer.interface.writeAll(
        \\  ]
        \\}
        \\
    );
    try summary_writer.interface.flush();

    std.debug.print(
        "wrote O2 A Jacobian trace sweep to {s} (variants={})\n",
        .{ output_dir, derivative_variants.len },
    );
}

fn derivativeRoute(route: RadiativeTransfer.Route, variant: TraceVariant) RadiativeTransfer.Route {
    var resolved = route;
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
        } else if (std.mem.eql(u8, arg, "--case")) {
            index += 1;
            if (index >= args.len) return error.MissingCasePath;
            config.case_yaml_path = args[index];
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
    trace: *const Trace.Run,
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
        \\      "worker_count": {},
        \\      "sample_count": {},
        \\      "wavelength_start_nm": {d:.8},
        \\      "wavelength_end_nm": {d:.8},
        \\      "mean_radiance": {e:.17},
        \\      "mean_irradiance": {e:.17},
        \\      "mean_reflectance": {e:.17},
        \\      "high_resolution_misses": {},
        \\      "fourier_terms": {},
        \\      "layer_visits": {},
        \\      "doubled_layers": {},
        \\      "doubling_steps": {},
        \\      "labos_execute_cpu_ns": {},
        \\      "rt_layer_build_cpu_ns": {},
        \\      "orders_cpu_ns": {},
        \\      "forward_input_cpu_ns": {},
        \\      "reflectance_integral_cpu_ns": {},
        \\      "aod_weighting_cpu_ns": {},
        \\      "pressure_weighting_cpu_ns": {},
        \\      "jacobian_assembly_cpu_ns": {},
        \\      "simulate_jacobian_processing_wall_ns": {}
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
            trace.totalWorkerSectionNs(.labos_execute),
            trace.totalWorkerSectionNs(.rt_layer_build),
            trace.totalWorkerSectionNs(.orders_total),
            trace.totalWorkerSectionNs(.forward_input),
            trace.totalWorkerSectionNs(.reflectance_integral),
            trace.totalWorkerSectionNs(.reflectance_aerosol_optical_depth_weighting),
            trace.totalWorkerSectionNs(.reflectance_aerosol_layer_pressure_weighting),
            trace.totalWorkerSectionNs(.reflectance_jacobian_assembly),
            trace.wall_sections_ns[@intFromEnum(Trace.Section.simulate_jacobian_processing)],
        },
    );
}

fn writeVariantSections(writer: *std.Io.Writer, variant_name: []const u8, trace: *const Trace.Run) !void {
    const forward_wall = @max(trace.forward_wall_ns, 1);
    const labos_cpu = @max(trace.totalWorkerSectionNs(.labos_execute), 1);
    inline for (@typeInfo(Trace.Section).@"enum".fields) |field| {
        const section: Trace.Section = @enumFromInt(field.value);
        const wall_ns = trace.wall_sections_ns[@intFromEnum(section)];
        if (wall_ns != 0) {
            try writeVariantSectionRow(writer, variant_name, "wall", section, wall_ns, forward_wall, labos_cpu);
        }
        const cpu_ns = trace.totalWorkerSectionNs(section);
        if (cpu_ns != 0) {
            try writeVariantSectionRow(writer, variant_name, "worker_cpu", section, cpu_ns, forward_wall, labos_cpu);
        }
    }
}

fn writeVariantSectionRow(
    writer: *std.Io.Writer,
    variant_name: []const u8,
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
        "{s},{s},{s},{},{d:.9},{d:.6},{d:.6}\n",
        .{ variant_name, scope, section.name(), ns, seconds, forward_pct, labos_pct },
    );
}

fn writeVariantCounters(writer: *std.Io.Writer, variant_name: []const u8, trace: *const Trace.Run) !void {
    inline for (@typeInfo(Trace.Counter).@"enum".fields) |field| {
        const counter: Trace.Counter = @enumFromInt(field.value);
        const count = trace.totalCounter(counter);
        if (count != 0) {
            try writer.print("{s},{s},{}\n", .{ variant_name, counter.name(), count });
        }
    }
}

fn writeVariantWorkerSections(writer: *std.Io.Writer, variant_name: []const u8, trace: *const Trace.Run) !void {
    for (trace.workers[0..trace.worker_count], 0..) |worker_state, worker_index| {
        inline for (@typeInfo(Trace.Section).@"enum".fields) |field| {
            const section: Trace.Section = @enumFromInt(field.value);
            const ns = worker_state.sections_ns[@intFromEnum(section)];
            if (ns != 0) {
                try writer.print(
                    "{s},{},{s},{},{d:.9}\n",
                    .{
                        variant_name,
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

fn openOutputFile(allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.fs.cwd().createFile(path, .{ .truncate = true });
}

fn writeSummary(
    output_dir: []const u8,
    prepare_ns: u64,
    prepare_trace: internal.disamar_reference.metrics.O2APrepareTrace,
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
        \\  "prepare_load_inputs_ns": {},
        \\  "prepare_build_scene_ns": {},
        \\  "prepare_optical_prepare_ns": {},
        \\  "prepare_optical_context_init_ns": {},
        \\  "prepare_optical_absorbers_build_ns": {},
        \\  "prepare_optical_accumulation_ns": {},
        \\  "prepare_optical_finalize_ns": {},
        \\  "prepare_optical_shared_geometry_ns": {},
        \\  "prepare_weak_cutoff_grid_ns": {},
        \\  "prepare_solar_rewindow_ns": {},
        \\  "prepare_route_prepare_ns": {},
        \\  "forward_wall_ns": {},
        \\  "prepare_s": {d:.9},
        \\  "prepare_load_inputs_s": {d:.9},
        \\  "prepare_build_scene_s": {d:.9},
        \\  "prepare_optical_prepare_s": {d:.9},
        \\  "prepare_optical_context_init_s": {d:.9},
        \\  "prepare_optical_absorbers_build_s": {d:.9},
        \\  "prepare_optical_accumulation_s": {d:.9},
        \\  "prepare_optical_finalize_s": {d:.9},
        \\  "prepare_optical_shared_geometry_s": {d:.9},
        \\  "prepare_weak_cutoff_grid_s": {d:.9},
        \\  "prepare_solar_rewindow_s": {d:.9},
        \\  "prepare_route_prepare_s": {d:.9},
        \\  "forward_wall_s": {d:.9},
    ,
        .{
            prepare_ns,
            prepare_trace.load_inputs_ns,
            prepare_trace.build_scene_ns,
            prepare_trace.optical_prepare_ns,
            prepare_trace.optical_context_init_ns,
            prepare_trace.optical_absorbers_build_ns,
            prepare_trace.optical_accumulation_ns,
            prepare_trace.optical_finalize_ns,
            prepare_trace.optical_shared_geometry_ns,
            prepare_trace.weak_cutoff_grid_ns,
            prepare_trace.solar_rewindow_ns,
            prepare_trace.route_prepare_ns,
            forward_ns,
            @as(f64, @floatFromInt(prepare_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.load_inputs_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.build_scene_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.optical_prepare_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.optical_context_init_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.optical_absorbers_build_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.optical_accumulation_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.optical_finalize_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.optical_shared_geometry_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.weak_cutoff_grid_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.solar_rewindow_ns)) / 1.0e9,
            @as(f64, @floatFromInt(prepare_trace.route_prepare_ns)) / 1.0e9,
            @as(f64, @floatFromInt(forward_ns)) / 1.0e9,
        },
    );
    try writer.interface.print(
        \\
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
