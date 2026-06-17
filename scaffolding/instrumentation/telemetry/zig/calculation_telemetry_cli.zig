const std = @import("std");
const internal = @import("internal");
const TelemetrySink = @import("calculation_telemetry_sink");

const InstrumentGrid = internal.spectrum;
const o2a_reference = internal.o2a_reference;
const RadiativeTransfer = struct {
    const Jacobian = internal.rtm.jacobian_states;
    const SolveConfig = internal.rtm.controls.SolveConfig;
};
const CalculationTelemetry = internal.instrumentation.telemetry;

const default_output_dir = "out/calculation-telemetry-staging/o2a-default";
const default_start_nm: f64 = 760.0;
const default_end_nm: f64 = 761.0;
const default_sample_count: u32 = 21;
const default_high_resolution_step_nm: f64 = 0.1;

// instrumentation: calculation telemetry harness
// captures: configured run and row counts
// why: make expression data reproducible.
// Configuration remains CLI-owned. The forward model only sees the resolved
// typed input and the compile-time telemetry facade.
const Config = struct {
    output_dir: []const u8 = default_output_dir,
    scene_id: ?[]const u8 = null,
    start_nm: f64 = default_start_nm,
    end_nm: f64 = default_end_nm,
    sample_count: u32 = default_sample_count,
    high_resolution_step_nm: f64 = default_high_resolution_step_nm,
    surface_pressure_hpa: ?f64 = null,
    surface_albedo: ?f64 = null,
    aerosol_optical_depth: ?f64 = null,
    aerosol_single_scatter_albedo: ?f64 = null,
    aerosol_asymmetry_factor: ?f64 = null,
    aerosol_layer_top_pressure_hpa: ?f64 = null,
    aerosol_layer_bottom_pressure_hpa: ?f64 = null,
    solar_zenith_deg: ?f64 = null,
    viewing_zenith_deg: ?f64 = null,
    relative_azimuth_deg: ?f64 = null,
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

    // instrumentation: calculation telemetry activation
    // captures: all enabled facade hooks
    // why: rtm_config model events into Parquet tables for this process.
    var collector = try TelemetrySink.CollectorHandle.init(allocator, config.output_dir);
    defer collector.deinit();
    TelemetrySink.setCollector(&collector);
    defer TelemetrySink.clearCollector();

    var prepare_timer = try std.time.Timer.start();
    var input = o2a_reference.defaultInput();
    if (config.scene_id) |scene_id| input.scene_id = scene_id;
    input.spectral_grid.start_nm = config.start_nm;
    input.spectral_grid.end_nm = config.end_nm;
    input.spectral_grid.sample_count = config.sample_count;

    input.observation.high_resolution_step_nm = config.high_resolution_step_nm;
    var interval_storage: [16]@TypeOf(input.intervals[0]) = undefined;
    if (input.intervals.len > interval_storage.len) return error.InvalidIntervalCount;
    @memcpy(interval_storage[0..input.intervals.len], input.intervals);
    input.intervals = interval_storage[0..input.intervals.len];
    if (config.surface_pressure_hpa) |value| input.surface_pressure_hpa = value;

    if (config.surface_albedo) |value| input.surface_albedo = value;
    if (config.aerosol_optical_depth) |value| input.aerosol.optical_depth = value;
    if (config.aerosol_single_scatter_albedo) |value| input.aerosol.single_scatter_albedo = value;
    if (config.aerosol_asymmetry_factor) |value| input.aerosol.asymmetry_factor = value;
    if (config.aerosol_layer_top_pressure_hpa) |value| input.aerosol.placement.top_pressure_hpa = value;
    if (config.aerosol_layer_bottom_pressure_hpa) |value| input.aerosol.placement.bottom_pressure_hpa = value;

    if (config.surface_pressure_hpa != null or
        config.aerosol_layer_top_pressure_hpa != null or
        config.aerosol_layer_bottom_pressure_hpa != null)
    {
        updateFitIntervals(&input, interval_storage[0..input.intervals.len]);
    }
    if (config.solar_zenith_deg) |value| input.geometry.solar_zenith_deg = value;

    if (config.viewing_zenith_deg) |value| input.geometry.viewing_zenith_deg = value;
    if (config.relative_azimuth_deg) |value| input.geometry.relative_azimuth_deg = value;
    if (!config.multiple_scattering) input.rtm_controls.scattering = .single;
    var prepared_case = try o2a_reference.prepareResolvedVendorO2ACase(
        allocator,
        &input,
    );

    const prepare_ns = prepare_timer.read();
    defer prepared_case.deinit(allocator);

    const rtm_config = telemetrySolveConfig(prepared_case.rtm_config, config.jacobian);
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

    try collector.finish();
    try writeSummary(config, input, prepare_ns, forward_ns, product.summary, collector.counts());

    std.debug.print(
        "wrote calculation telemetry parquet rows to {s} (scalar={}, reduction={}, decision={})\n",
        .{
            config.output_dir,
            collector.counts().scalar,
            collector.counts().reduction,
            collector.counts().decision,
        },
    );
}

fn telemetrySolveConfig(
    rtm_config: RadiativeTransfer.SolveConfig,
    include_jacobian: bool,
) RadiativeTransfer.SolveConfig {

    // instrumentation: calculation telemetry scope
    // captures: forward-only or two-state Jacobian path
    // why: choose which math expressions appear in the dataset.

    var resolved = rtm_config;
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
        } else if (std.mem.eql(u8, arg, "--scene-id")) {
            index += 1;
            if (index >= args.len) return error.MissingSceneId;

            config.scene_id = args[index];
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
        } else if (std.mem.eql(u8, arg, "--surface-pressure-hpa")) {
            index += 1;

            if (index >= args.len) return error.MissingSurfacePressure;
            config.surface_pressure_hpa = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--surface-albedo")) {
            index += 1;

            if (index >= args.len) return error.MissingSurfaceAlbedo;
            config.surface_albedo = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--aerosol-optical-depth")) {
            index += 1;

            if (index >= args.len) return error.MissingAerosolOpticalDepth;
            config.aerosol_optical_depth = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--aerosol-single-scatter-albedo")) {
            index += 1;

            if (index >= args.len) return error.MissingAerosolSingleScatterAlbedo;
            config.aerosol_single_scatter_albedo = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--aerosol-asymmetry-factor")) {
            index += 1;

            if (index >= args.len) return error.MissingAerosolAsymmetryFactor;
            config.aerosol_asymmetry_factor = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--aerosol-layer-top-pressure-hpa")) {
            index += 1;

            if (index >= args.len) return error.MissingAerosolLayerTopPressure;
            config.aerosol_layer_top_pressure_hpa = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--aerosol-layer-bottom-pressure-hpa")) {
            index += 1;

            if (index >= args.len) return error.MissingAerosolLayerBottomPressure;
            config.aerosol_layer_bottom_pressure_hpa = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--solar-zenith-deg")) {
            index += 1;

            if (index >= args.len) return error.MissingSolarZenith;
            config.solar_zenith_deg = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--viewing-zenith-deg")) {
            index += 1;

            if (index >= args.len) return error.MissingViewingZenith;
            config.viewing_zenith_deg = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--relative-azimuth-deg")) {
            index += 1;

            if (index >= args.len) return error.MissingRelativeAzimuth;
            config.relative_azimuth_deg = try std.fmt.parseFloat(f64, args[index]);
        } else {
            return error.UnsupportedArgument;
        }
    }
    return config;
}

fn updateFitIntervals(input: anytype, intervals: anytype) void {
    const fit_index = @as(u64, input.fit_interval_index_1based);
    const top_pressure = input.aerosol.placement.top_pressure_hpa;
    const bottom_pressure = input.aerosol.placement.bottom_pressure_hpa;

    for (intervals) |*interval| {
        const interval_index = @as(u64, interval.index_1based);
        if (interval_index + 1 == fit_index) {
            interval.bottom_pressure_hpa = top_pressure;
        } else if (interval_index == fit_index) {
            interval.top_pressure_hpa = top_pressure;

            interval.bottom_pressure_hpa = bottom_pressure;
        } else if (interval_index == fit_index + 1) {
            interval.top_pressure_hpa = bottom_pressure;
        }
        if (interval_index == input.layer_count) {
            interval.bottom_pressure_hpa = input.surface_pressure_hpa;
        }
    }
}

fn writeSummary(
    config: Config,
    input: anytype,
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
        \\  "scene_id": "{s}",
        \\  "jacobian": {},
        \\  "multiple_scattering": {},
        \\  "start_nm": {d:.8},
        \\  "end_nm": {d:.8},
        \\  "requested_sample_count": {},
        \\  "high_resolution_step_nm": {d:.8},
        \\  "surface_pressure_hpa": {e:.17},
        \\  "surface_albedo": {e:.17},
        \\  "aerosol_optical_depth": {e:.17},
        \\  "aerosol_single_scatter_albedo": {e:.17},
        \\  "aerosol_asymmetry_factor": {e:.17},
        \\  "aerosol_layer_top_pressure_hpa": {e:.17},
        \\  "aerosol_layer_bottom_pressure_hpa": {e:.17},
        \\  "solar_zenith_deg": {d:.8},
        \\  "viewing_zenith_deg": {d:.8},
        \\  "relative_azimuth_deg": {d:.8},
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

            // instrumentation: calculation telemetry metadata
            // captures: compile-time request/enabled flags in the run summary
            // why: make disabled or miswired telemetry captures obvious in generated JSON.
            CalculationTelemetry.requested,
            CalculationTelemetry.enabled,
            input.scene_id,
            config.jacobian,
            config.multiple_scattering,
            config.start_nm,
            config.end_nm,
            config.sample_count,
            config.high_resolution_step_nm,
            input.surface_pressure_hpa,
            input.surface_albedo,
            input.aerosol.optical_depth,
            input.aerosol.single_scatter_albedo,
            input.aerosol.asymmetry_factor,
            input.aerosol.placement.top_pressure_hpa,
            input.aerosol.placement.bottom_pressure_hpa,
            input.geometry.solar_zenith_deg,
            input.geometry.viewing_zenith_deg,
            input.geometry.relative_azimuth_deg,
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
