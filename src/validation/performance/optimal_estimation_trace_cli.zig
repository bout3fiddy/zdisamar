const std = @import("std");
const internal = @import("internal");

const InstrumentGrid = internal.forward_model.instrument_grid;
const OptimalEstimation = internal.optimal_estimation;
const Trace = internal.forward_model.performance_trace;
const o2a_reference = internal.o2a_reference;

const default_output_dir = "out/optimal-estimation-trace";
const measurement_sigma_reflectance = 1.0e-3;

const Config = struct {
    output_dir: []const u8 = default_output_dir,
    max_iterations: usize = 3,
};

pub fn main() !void {
    return mainInner() catch |err| {
        std.debug.print("optimal-estimation-trace failed: {}\n", .{err});
        return err;
    };
}

fn mainInner() !void {
    const main_zone = Trace.staticZone(@src(), "oe_trace.main");
    defer main_zone.end();
    Trace.message("zdisamar optimal estimation trace start");
    Trace.frameMark();
    defer Trace.frameMark();
    defer Trace.message("zdisamar optimal estimation trace end");

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const config = try parseArgs(args);
    try std.fs.cwd().makePath(config.output_dir);

    const input = o2a_reference.defaultInput();

    var reference_timer = try std.time.Timer.start();
    var prepared_case = try o2a_reference.prepareResolvedVendorO2ACase(allocator, &input);
    const reference_prepare_ns = reference_timer.read();
    defer prepared_case.deinit(allocator);

    const sample_count = prepared_case.reference.len;
    var measurement_wavelength_nm = try allocator.alloc(f64, sample_count);
    defer allocator.free(measurement_wavelength_nm);
    var measurement_reflectance = try allocator.alloc(f64, sample_count);
    defer allocator.free(measurement_reflectance);
    var measurement_variance = try allocator.alloc(f64, sample_count);
    defer allocator.free(measurement_variance);
    for (prepared_case.reference, 0..) |sample, index| {
        measurement_wavelength_nm[index] = sample.wavelength_nm;
        measurement_reflectance[index] = sample.reflectance;
        measurement_variance[index] = measurement_sigma_reflectance * measurement_sigma_reflectance;
    }

    const profile_altitude_km = [_]f64{ 0.0, 5.0, 10.0, 20.0, 40.0 };
    const profile_pressure_hpa = [_]f64{ 1013.25, 540.48, 264.36, 54.75, 2.87 };
    const pressure_profile = try OptimalEstimation.buildPressureProfile(
        allocator,
        &profile_altitude_km,
        &profile_pressure_hpa,
    );
    defer OptimalEstimation.freePressureProfile(allocator, pressure_profile);

    const reference_mid_pressure_hpa =
        0.5 * (input.aerosol.placement.top_pressure_hpa + input.aerosol.placement.bottom_pressure_hpa);
    const layer_thickness_hpa =
        input.aerosol.placement.bottom_pressure_hpa - input.aerosol.placement.top_pressure_hpa;
    var state_specs = [_]OptimalEstimation.StateSpec{
        .{
            .state = .aerosol_optical_depth,
            .initial = 0.85 * input.aerosol.optical_depth + 0.02,
            .prior = 0.85 * input.aerosol.optical_depth + 0.02,
            .variance = 1.0,
            .lower_bound = 0.0,
            .upper_bound = OptimalEstimation.no_upper_bound,
        },
        .{
            .state = .aerosol_layer_mid_pressure_hpa,
            .initial = reference_mid_pressure_hpa + 20.0,
            .prior = reference_mid_pressure_hpa + 20.0,
            .variance = 150.0 * 150.0,
            .lower_bound = 225.0,
            .upper_bound = input.surface_pressure_hpa - 100.0,
            .thickness_hpa = layer_thickness_hpa,
            .interval_index_1based = input.aerosol.placement.interval_index_1based,
            .pressure_altitude_profile = pressure_profile,
        },
    };

    var product_storage: InstrumentGrid.ProductStorage = .{};
    defer product_storage.deinit(allocator);

    var retrieval_timer = try std.time.Timer.start();
    var result = try OptimalEstimation.runO2A(
        allocator,
        &input,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
        &state_specs,
        &product_storage,
        .{
            .max_iterations = config.max_iterations,
            .state_vector_convergence_threshold = 1.0,
            .max_change_transformed_state = 1.0,
        },
    );
    const retrieval_ns = retrieval_timer.read();
    defer result.deinit(allocator);

    try writeSummary(
        config.output_dir,
        reference_prepare_ns,
        retrieval_ns,
        sample_count,
        config.max_iterations,
        &input,
        reference_mid_pressure_hpa,
        &result,
    );

    std.debug.print(
        "wrote optimal-estimation trace summary to {s} (retrieval_s={d:.6}, iterations={})\n",
        .{
            config.output_dir,
            @as(f64, @floatFromInt(retrieval_ns)) / 1.0e9,
            result.iteration_count,
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
        } else if (std.mem.eql(u8, arg, "--max-iterations")) {
            index += 1;
            if (index >= args.len) return error.MissingMaxIterations;
            config.max_iterations = try std.fmt.parseInt(usize, args[index], 10);
        } else {
            return error.UnsupportedArgument;
        }
    }
    return config;
}

fn writeSummary(
    output_dir: []const u8,
    reference_prepare_ns: u64,
    retrieval_ns: u64,
    sample_count: usize,
    max_iterations: usize,
    input: *const o2a_reference.O2AInput,
    reference_mid_pressure_hpa: f64,
    result: *const OptimalEstimation.Result,
) !void {
    var file = try openOutputFile(std.heap.page_allocator, output_dir, "summary.json");
    defer file.close();

    const retrieved_aod = result.state[0];
    const retrieved_mid_pressure_hpa = result.state[1];
    const reference_aod = input.aerosol.optical_depth;
    var writer = file.writer(&.{});
    try writer.interface.print(
        \\{{
        \\  "trace_enabled": {},
        \\  "sample_count": {},
        \\  "max_iterations": {},
        \\  "iteration_count": {},
        \\  "converged": {},
        \\  "reference_prepare_ns": {},
        \\  "reference_prepare_s": {d:.9},
        \\  "retrieval_wall_ns": {},
        \\  "retrieval_wall_s": {d:.9},
        \\  "measurement_sigma_reflectance": {e:.17},
        \\  "reference_state": {{
        \\    "aerosol_optical_depth": {e:.17},
        \\    "aerosol_layer_mid_pressure_hpa": {e:.17}
        \\  }},
        \\  "retrieved_state": {{
        \\    "aerosol_optical_depth": {e:.17},
        \\    "aerosol_layer_mid_pressure_hpa": {e:.17}
        \\  }},
        \\  "residuals": {{
        \\    "aerosol_optical_depth_abs_error": {e:.17},
        \\    "aerosol_layer_mid_pressure_abs_error_hpa": {e:.17}
        \\  }}
        \\}}
        \\
    ,
        .{
            Trace.enabled,
            sample_count,
            max_iterations,
            result.iteration_count,
            result.converged,
            reference_prepare_ns,
            @as(f64, @floatFromInt(reference_prepare_ns)) / 1.0e9,
            retrieval_ns,
            @as(f64, @floatFromInt(retrieval_ns)) / 1.0e9,
            measurement_sigma_reflectance,
            reference_aod,
            reference_mid_pressure_hpa,
            retrieved_aod,
            retrieved_mid_pressure_hpa,
            @abs(retrieved_aod - reference_aod),
            @abs(retrieved_mid_pressure_hpa - reference_mid_pressure_hpa),
        },
    );
    try writer.interface.flush();
}

fn openOutputFile(allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.fs.cwd().createFile(path, .{ .truncate = true });
}
