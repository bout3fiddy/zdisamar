const std = @import("std");
const internal = @import("internal");
const timing = internal.common.runtime_io;
const TelemetrySink = @import("calculation_telemetry_sink");

const CalculationTelemetry = internal.forward_model.calculation_telemetry;
const InstrumentGrid = internal.forward_model.instrument_grid;
const OptimalEstimation = internal.optimal_estimation;
const o2a_reference = internal.o2a_reference;

const default_output_dir = "out/fastmode-diagnosis-telemetry/raw";

const Config = struct {
    input_dir: []const u8 = "out/fastmode-diagnosis-telemetry/input",
    output_dir: []const u8 = default_output_dir,
    batch_workers: usize = 2,
};

const MeasurementPayload = struct {
    wavelength_nm: []f64,
    reflectance: []f64,
    variance: []f64,
};

const RequestPayload = struct {
    scene_index: u32,
    starts: [][2]f64,
    pressure_profile_altitude_km: []f64,
    pressure_profile_pressure_hpa: []f64,
    fast_measurement: MeasurementPayload,
    correction_measurement: MeasurementPayload,
};

pub fn main(init: std.process.Init) !void {
    return mainInner(init) catch |err| {
        std.debug.print("fastmode-diagnosis-telemetry failed: {}\n", .{err});
        return err;
    };
}

fn mainInner(init: std.process.Init) !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const config = try parseArgs(args);
    try std.Io.Dir.cwd().createDirPath(init.io, config.output_dir);

    const fast_case_json = try readInputFile(init.io, allocator, config.input_dir, "fast_case.json");
    defer allocator.free(fast_case_json);
    var fast_case = try o2a_reference.parseInputJson(allocator, fast_case_json);
    defer fast_case.deinit();

    const correction_case_json = try readInputFile(init.io, allocator, config.input_dir, "correction_case.json");
    defer allocator.free(correction_case_json);
    var correction_case = try o2a_reference.parseInputJson(allocator, correction_case_json);
    defer correction_case.deinit();

    const request_json = try readInputFile(init.io, allocator, config.input_dir, "request.json");
    defer allocator.free(request_json);
    var parsed_request = try std.json.parseFromSlice(RequestPayload, allocator, request_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_request.deinit();
    const request = parsed_request.value;
    try validateRequest(request);

    var collector = try TelemetrySink.CollectorHandle.init(init.io, allocator, config.output_dir);
    defer collector.deinit();
    TelemetrySink.setCollector(&collector);
    defer TelemetrySink.clearCollector();

    var telemetry_context = CalculationTelemetry.Context{};
    telemetry_context.scene_index = std.math.cast(i64, request.scene_index) orelse std.math.maxInt(i64);
    CalculationTelemetry.setContext(telemetry_context);
    defer CalculationTelemetry.clearContext();

    const pressure_profile = try OptimalEstimation.buildPressureProfile(
        allocator,
        request.pressure_profile_altitude_km,
        request.pressure_profile_pressure_hpa,
    );
    defer OptimalEstimation.freePressureProfile(allocator, pressure_profile);

    const first_start = request.starts[0];
    const layer_thickness_hpa =
        fast_case.value.aerosol.placement.bottom_pressure_hpa -
        fast_case.value.aerosol.placement.top_pressure_hpa;
    var state_template = [_]OptimalEstimation.StateSpec{
        .{
            .state = .aerosol_optical_depth,
            .initial = first_start[0],
            .prior = first_start[0],
            .variance = 0.8,
            .lower_bound = 0.02,
            .upper_bound = 5.0,
        },
        .{
            .state = .aerosol_layer_mid_pressure_hpa,
            .initial = first_start[1],
            .prior = first_start[1],
            .variance = 150.0 * 150.0,
            .lower_bound = 225.0,
            .upper_bound = fast_case.value.surface_pressure_hpa - 100.0,
            .thickness_hpa = layer_thickness_hpa,
            .interval_index_1based = fast_case.value.aerosol.placement.interval_index_1based,
            .pressure_altitude_profile = pressure_profile,
        },
    };

    const initial_states = try flattenStarts(allocator, request.starts);
    defer allocator.free(initial_states);
    const prior_states = try flattenStarts(allocator, request.starts);
    defer allocator.free(prior_states);
    const correction_prior_states = try flattenStarts(allocator, request.starts);
    defer allocator.free(correction_prior_states);

    var fast_storage: InstrumentGrid.ProductStorage = .{};
    defer fast_storage.deinit(allocator);
    var correction_storage: InstrumentGrid.ProductStorage = .{};
    defer correction_storage.deinit(allocator);

    var timer = timing.Timer.start(init.io);
    var result = try OptimalEstimation.runO2AFastmodeBatch(
        allocator,
        &fast_case.value,
        request.fast_measurement.wavelength_nm,
        request.fast_measurement.reflectance,
        request.fast_measurement.variance,
        &state_template,
        initial_states,
        prior_states,
        &fast_storage,
        .{
            .max_iterations = 10,
            .state_vector_convergence_threshold = 30.0,
            .max_change_transformed_state = 1.0,
        },
        &correction_case.value,
        request.correction_measurement.wavelength_nm,
        request.correction_measurement.reflectance,
        request.correction_measurement.variance,
        &state_template,
        correction_prior_states,
        &correction_storage,
        .{
            .max_iterations = 1,
            .state_vector_convergence_threshold = 30.0,
            .max_change_transformed_state = 1.0,
        },
        config.batch_workers,
    );
    const retrieval_ns = timer.read();
    defer result.deinit(allocator);

    try collector.finish();
    const counts = collector.counts();
    try writeSummary(init.io, config, request, retrieval_ns, counts, &result);

    std.debug.print(
        "wrote fastmode diagnosis telemetry to {s} (scalar={}, reduction={}, decision={})\n",
        .{ config.output_dir, counts.scalar, counts.reduction, counts.decision },
    );
}

fn validateRequest(request: RequestPayload) !void {
    if (request.starts.len == 0) return error.EmptyStarts;
    try validateMeasurement(request.fast_measurement);
    try validateMeasurement(request.correction_measurement);
    if (request.pressure_profile_altitude_km.len < 2 or
        request.pressure_profile_altitude_km.len != request.pressure_profile_pressure_hpa.len)
    {
        return error.InvalidPressureProfile;
    }
}

fn validateMeasurement(measurement: MeasurementPayload) !void {
    if (measurement.wavelength_nm.len == 0 or
        measurement.wavelength_nm.len != measurement.reflectance.len or
        measurement.wavelength_nm.len != measurement.variance.len)
    {
        return error.InvalidMeasurement;
    }
}

fn flattenStarts(allocator: std.mem.Allocator, starts: [][2]f64) ![]f64 {
    const values = try allocator.alloc(f64, starts.len * 2);
    for (starts, 0..) |start, index| {
        values[index * 2 + 0] = start[0];
        values[index * 2 + 1] = start[1];
    }
    return values;
}

fn parseArgs(args: []const [:0]const u8) !Config {
    var config: Config = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--input-dir")) {
            index += 1;
            if (index >= args.len) return error.MissingInputDir;
            config.input_dir = args[index];
        } else if (std.mem.eql(u8, arg, "--output-dir")) {
            index += 1;
            if (index >= args.len) return error.MissingOutputDir;
            config.output_dir = args[index];
        } else if (std.mem.eql(u8, arg, "--batch-workers")) {
            index += 1;
            if (index >= args.len) return error.MissingBatchWorkers;
            config.batch_workers = try std.fmt.parseInt(usize, args[index], 10);
        } else {
            return error.UnsupportedArgument;
        }
    }
    if (config.batch_workers == 0) return error.InvalidBatchWorkers;
    return config;
}

fn readInputFile(io: std.Io, allocator: std.mem.Allocator, input_dir: []const u8, name: []const u8) ![]u8 {
    const path = try std.fs.path.join(allocator, &.{ input_dir, name });
    defer allocator.free(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024));
}

fn writeSummary(
    io: std.Io,
    config: Config,
    request: RequestPayload,
    retrieval_ns: u64,
    counts: TelemetrySink.RowCounts,
    result: *const OptimalEstimation.FastmodeBatchResult,
) !void {
    var file = try openOutputFile(io, std.heap.page_allocator, config.output_dir, "run_summary.json");
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.print(
        \\{{
        \\  "calculation_telemetry_requested": {},
        \\  "calculation_telemetry_enabled": {},
        \\  "scene_index": {},
        \\  "start_count": {},
        \\  "batch_workers": {},
        \\  "fast_measurement_count": {},
        \\  "correction_measurement_count": {},
        \\  "retrieval_wall_ns": {},
        \\  "retrieval_wall_s": {d:.9},
        \\  "scalar_rows": {},
        \\  "reduction_rows": {},
        \\  "decision_rows": {},
        \\  "starts": [
        \\
    ,
        .{
            CalculationTelemetry.requested,
            CalculationTelemetry.enabled,
            request.scene_index,
            request.starts.len,
            config.batch_workers,
            request.fast_measurement.wavelength_nm.len,
            request.correction_measurement.wavelength_nm.len,
            retrieval_ns,
            @as(f64, @floatFromInt(retrieval_ns)) / 1.0e9,
            counts.scalar,
            counts.reduction,
            counts.decision,
        },
    );
    for (0..result.run_count) |run_index| {
        const state_offset = run_index * result.state_count;
        try writer.interface.print(
            "    {{\"start_index\": {}, \"start_aod\": {e:.17}, " ++
                "\"start_alh_hpa\": {e:.17}, \"retrieved_aod\": {e:.17}, " ++
                "\"retrieved_alh_hpa\": {e:.17}, \"iterations\": {}, " ++
                "\"converged\": {}, \"fast_stage_iterations\": {}, " ++
                "\"fast_stage_converged\": {}, \"full_correction_iterations\": {}, " ++
                "\"full_correction_converged\": {}}}{s}\n",
            .{
                run_index + 1,
                request.starts[run_index][0],
                request.starts[run_index][1],
                result.state[state_offset + 0],
                result.state[state_offset + 1],
                result.iteration_count[run_index],
                result.converged[run_index] != 0,
                result.fast_stage_iteration_count[run_index],
                result.fast_stage_converged[run_index] != 0,
                result.full_correction_iteration_count[run_index],
                result.full_correction_converged[run_index] != 0,
                if (run_index + 1 == result.run_count) "" else ",",
            },
        );
    }
    try writer.interface.writeAll(
        \\  ]
        \\}
        \\
    );
    try writer.interface.flush();
}

fn openOutputFile(io: std.Io, allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.Io.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
}
