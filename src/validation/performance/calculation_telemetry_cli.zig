const std = @import("std");
const internal = @import("internal");
const TelemetrySink = @import("calculation_telemetry_sink");

const InstrumentGrid = internal.forward_model.instrument_grid;
const o2a_reference = internal.o2a_reference;
const RadiativeTransfer = internal.forward_model.radiative_transfer;
const CalculationTelemetry = internal.forward_model.calculation_telemetry;

const default_output_dir = "out/calculation-telemetry-staging/o2a-default";
const default_start_nm: f64 = 760.0;
const default_end_nm: f64 = 761.0;
const default_sample_count: u32 = 21;
const default_high_resolution_step_nm: f64 = 0.1;

// layout(64-bit):
//   size: 56 B, align: 8 B
//   field storage: output_dir=16 B, three f64 controls=24 B, sample_count=4 B, output_dir_set=1 B, jacobian=1 B, multiple_scattering=1 B; padding: 9 B
//   unused bits: 72 padding + 21 bool-storage slack = 93 bits
//   out-of-line: output_dir carries a command-line slice; referenced storage is not included
//   count: one stack value in the data-pipeline executable
//   footprint: per instance = 56 B (0.055 KiB)
const Config = struct {
    output_dir: []const u8 = default_output_dir,
    start_nm: f64 = default_start_nm,
    end_nm: f64 = default_end_nm,
    sample_count: u32 = default_sample_count,
    high_resolution_step_nm: f64 = default_high_resolution_step_nm,
    output_dir_set: bool = false,
    jacobian: bool = false,
    multiple_scattering: bool = false,
};

pub fn main() !void {
    return mainInner() catch |err| {
        std.debug.print("calculation-telemetry failed: {}\n", .{err});
        return err;
    };
}

fn mainInner() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const config = try parseArgs(args);
    try std.fs.cwd().makePath(config.output_dir);

    var collector = try TelemetrySink.CollectorHandle.init(allocator, config.output_dir);
    defer collector.deinit();
    TelemetrySink.setCollector(&collector);
    defer TelemetrySink.clearCollector();

    var prepare_timer = try std.time.Timer.start();
    var input = o2a_reference.defaultInput();
    input.spectral_grid.start_nm = config.start_nm;
    input.spectral_grid.end_nm = config.end_nm;
    input.spectral_grid.sample_count = config.sample_count;
    input.observation.high_resolution_step_nm = config.high_resolution_step_nm;
    if (!config.multiple_scattering) input.rtm_controls.scattering = .single;
    var prepared_case = try o2a_reference.prepareResolvedVendorO2ACase(
        allocator,
        &input,
    );
    const prepare_ns = prepare_timer.read();
    defer prepared_case.deinit(allocator);

    const route = telemetryRoute(prepared_case.route, config.jacobian);
    const implementations = internal.forward_model.implementations.exact();
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

    try collector.finish();
    try writeSummary(config, prepare_ns, forward_ns, product.summary, collector.counts());

    std.debug.print(
        "wrote calculation telemetry CSV staging rows to {s} (scalar={}, reduction={}, decision={})\n",
        .{
            config.output_dir,
            collector.counts().scalar,
            collector.counts().reduction,
            collector.counts().decision,
        },
    );
}

fn telemetryRoute(route: RadiativeTransfer.Route, include_jacobian: bool) RadiativeTransfer.Route {
    var resolved = route;
    if (!include_jacobian) {
        resolved.derivative_mode = .none;
        resolved.derivative_state_mask = 0;
        return resolved;
    }
    resolved.derivative_mode = .semi_analytical;
    var mask: RadiativeTransfer.Jacobian.StateMask = 0;
    mask |= RadiativeTransfer.Jacobian.stateMask(.aerosol_optical_depth);
    mask |= RadiativeTransfer.Jacobian.stateMask(.aerosol_layer_mid_pressure_hpa);
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
        } else if (std.mem.eql(u8, arg, "--jacobian")) {
            config.jacobian = true;
        } else if (std.mem.eql(u8, arg, "--multiple-scattering")) {
            config.multiple_scattering = true;
        } else if (std.mem.eql(u8, arg, "--sample-count")) {
            index += 1;
            if (index >= args.len) return error.MissingSampleCount;
            config.sample_count = try std.fmt.parseInt(u32, args[index], 10);
        } else if (std.mem.eql(u8, arg, "--start-nm")) {
            index += 1;
            if (index >= args.len) return error.MissingStartNm;
            config.start_nm = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--end-nm")) {
            index += 1;
            if (index >= args.len) return error.MissingEndNm;
            config.end_nm = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--high-resolution-step-nm")) {
            index += 1;
            if (index >= args.len) return error.MissingHighResolutionStep;
            config.high_resolution_step_nm = try std.fmt.parseFloat(f64, args[index]);
        } else {
            return error.UnsupportedArgument;
        }
    }
    return config;
}

fn writeSummary(
    config: Config,
    prepare_ns: u64,
    forward_ns: u64,
    summary: InstrumentGrid.InstrumentGridSummary,
    counts: TelemetrySink.RowCounts,
) !void {
    var file = try openOutputFile(std.heap.page_allocator, config.output_dir, "run_summary.json");
    defer file.close();

    var writer = file.writer(&.{});
    try writer.interface.print(
        \\{{
        \\  "calculation_telemetry_requested": {},
        \\  "calculation_telemetry_enabled": {},
        \\  "jacobian": {},
        \\  "multiple_scattering": {},
        \\  "start_nm": {d:.8},
        \\  "end_nm": {d:.8},
        \\  "requested_sample_count": {},
        \\  "high_resolution_step_nm": {d:.8},
        \\  "prepare_ns": {},
        \\  "forward_wall_ns": {},
        \\  "prepare_s": {d:.9},
        \\  "forward_wall_s": {d:.9},
        \\  "sample_count": {},
        \\  "wavelength_start_nm": {d:.8},
        \\  "wavelength_end_nm": {d:.8},
        \\  "mean_radiance": {e:.17},
        \\  "mean_irradiance": {e:.17},
        \\  "mean_reflectance": {e:.17},
        \\  "scalar_rows": {},
        \\  "reduction_rows": {},
        \\  "decision_rows": {}
        \\}}
        \\
    ,
        .{
            CalculationTelemetry.requested,
            CalculationTelemetry.enabled,
            config.jacobian,
            config.multiple_scattering,
            config.start_nm,
            config.end_nm,
            config.sample_count,
            config.high_resolution_step_nm,
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
            counts.scalar,
            counts.reduction,
            counts.decision,
        },
    );
    try writer.interface.flush();
}

fn openOutputFile(allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.fs.cwd().createFile(path, .{ .truncate = true });
}
