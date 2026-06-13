const std = @import("std");
const internal = @import("internal");
const Sink = @import("perturbation_sensitivity_sink");

const InstrumentGrid = internal.spectrum;
const Jacobian = internal.rtm.jacobian_states;
const OptimalEstimation = internal.retrieval.root;
const Perturbation = internal.instrumentation.sensitivity;
const o2a_reference = internal.o2a_reference;

const default_output_dir = "out/scaffolding/perturbation/data/o2a-default";
const measurement_sigma_reflectance = 1.0e-3;

// instrumentation: perturbation harness
// captures: paired baseline/perturbed residual summaries
// why: avoid massive event databases.
const Config = struct {
    output_dir: []const u8 = default_output_dir,
    start_nm: f64 = 758.0,
    end_nm: f64 = 770.0,
    sample_count: u32 = 241,
    max_iterations: usize = 3,
};

const ExperimentSpec = struct {
    name: []const u8,

    // instrumentation: perturbation channel
    // captures: model expression family targeted by an experiment
    // why: keep perturbation knobs tied to compile-time channel enums instead of strings.
    channel: Perturbation.Channel,
    mode: Sink.Mode,
    min_fourier: i32 = Sink.any_index,
    max_fourier: i32 = Sink.any_index,
    min_order: i32 = Sink.any_index,
    max_order: i32 = Sink.any_index,
    branch_filter: i32 = Sink.any_index,
    state_filter: i32 = Sink.any_index,
    scale: f64 = 1.0,
    rationale: []const u8,
};

const SpectrumDelta = struct {
    max_abs_reflectance_delta: f64 = 0.0,
    mean_abs_reflectance_delta: f64 = 0.0,
    rms_reflectance_delta: f64 = 0.0,
    max_reflectance_wavelength_nm: f64 = 0.0,
    max_abs_radiance_delta: f64 = 0.0,
    rms_radiance_delta: f64 = 0.0,
};

const RetrievalOutcome = struct {
    wall_ns: u64,
    converged: bool,
    iteration_count: u16,
    aerosol_optical_depth: f64,
    aerosol_layer_mid_pressure_hpa: f64,
};

// instrumentation: perturbation plan set
// captures: channel filters and replacement modes
// why: test pruning hypotheses against final spectra/retrievals.
const experiments = [_]ExperimentSpec{
    .{
        .name = "fourier_zero_ge_8",
        .channel = .fourier_weighted_reflectance,
        .mode = .zero,
        .min_fourier = 8,
        .rationale = "zero Fourier reflectance terms at and above order 8",
    },
    .{
        .name = "fourier_zero_ge_12",
        .channel = .fourier_weighted_reflectance,
        .mode = .zero,
        .min_fourier = 12,
        .rationale = "zero Fourier reflectance terms at and above order 12",
    },
    .{
        .name = "fourier_zero_ge_16",
        .channel = .fourier_weighted_reflectance,
        .mode = .zero,
        .min_fourier = 16,
        .rationale = "zero Fourier reflectance terms at and above order 16",
    },
    .{
        .name = "fourier_zero_ge_24",
        .channel = .fourier_weighted_reflectance,
        .mode = .zero,
        .min_fourier = 24,
        .rationale = "zero Fourier reflectance terms at and above order 24",
    },
    .{
        .name = "fourier_tail_stop_ge_8",
        .channel = .fourier_tail_break,
        .mode = .force_true,
        .min_fourier = 8,
        .rationale = "force the Fourier tail stop once order 8 is reached",
    },
    .{
        .name = "fourier_tail_stop_ge_12",
        .channel = .fourier_tail_break,
        .mode = .force_true,
        .min_fourier = 12,
        .rationale = "force the Fourier tail stop once order 12 is reached",
    },
    .{
        .name = "fourier_tail_stop_ge_16",
        .channel = .fourier_tail_break,
        .mode = .force_true,
        .min_fourier = 16,
        .rationale = "force the Fourier tail stop once order 16 is reached",
    },
    .{
        .name = "orders_stop_ge_4",
        .channel = .orders_multiple_convergence,
        .mode = .force_true,
        .min_order = 4,
        .rationale = "force multiple-scattering convergence at order 4 or later",
    },
    .{
        .name = "orders_stop_ge_6",
        .channel = .orders_multiple_convergence,
        .mode = .force_true,
        .min_order = 6,
        .rationale = "force multiple-scattering convergence at order 6 or later",
    },
    .{
        .name = "orders_stop_ge_8",
        .channel = .orders_multiple_convergence,
        .mode = .force_true,
        .min_order = 8,
        .rationale = "force multiple-scattering convergence at order 8 or later",
    },
    .{
        .name = "qseries_skip_ge_3",
        .channel = .qseries_skip,
        .mode = .force_true,
        .min_order = 3,
        .rationale = "force q-series skip from doubling step 3 onward",
    },
    .{
        .name = "qseries_skip_ge_5",
        .channel = .qseries_skip,
        .mode = .force_true,
        .min_order = 5,
        .rationale = "force q-series skip from doubling step 5 onward",
    },
    .{
        .name = "qzero_rd_suppress",
        .channel = .qseries_rd_product,
        .mode = .force_false,
        .branch_filter = 1,
        .rationale = "suppress R-D product work only inside q-zero branches",
    },
    .{
        .name = "qzero_tu_suppress",
        .channel = .qseries_tu_product,
        .mode = .force_false,
        .branch_filter = 1,
        .rationale = "suppress T-U product work only inside q-zero branches",
    },
    .{
        .name = "qzero_td_suppress",
        .channel = .qseries_td_product,
        .mode = .force_false,
        .branch_filter = 1,
        .rationale = "suppress T-D product work only inside q-zero branches",
    },
    .{
        .name = "aod_tangent_zero_ge_12",
        .channel = .aerosol_aod_tangent,
        .mode = .zero,
        .min_fourier = 12,
        .state_filter = @intFromEnum(Jacobian.State.aerosol_optical_depth),
        .rationale = "zero late Fourier AOD tangent contributions",
    },
    .{
        .name = "pressure_tangent_zero_ge_12",
        .channel = .aerosol_pressure_tangent,
        .mode = .zero,
        .min_fourier = 12,
        .state_filter = @intFromEnum(Jacobian.State.aerosol_layer_mid_pressure_hpa),
        .rationale = "zero late Fourier aerosol-pressure tangent contributions",
    },
};

pub fn main() !void {
    return mainInner() catch |err| {
        std.debug.print("perturbation-sensitivity failed: {}\n", .{err});
        return err;
    };
}

fn mainInner() !void {

    // instrumentation: perturbation harness gate
    // captures: compile-time enablement of perturbation channels
    // why: fail loudly when this validation CLI is built against the product no-op facade.
    if (!Perturbation.enabled) return error.PerturbationSensitivityDisabled;

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const config = try parseArgs(args);
    try std.fs.cwd().makePath(config.output_dir);

    var input = o2a_reference.defaultInput();
    input.spectral_grid.start_nm = config.start_nm;
    input.spectral_grid.end_nm = config.end_nm;
    input.spectral_grid.sample_count = config.sample_count;

    var prepared_case = try o2a_reference.prepareResolvedVendorO2ACase(allocator, &input);
    defer prepared_case.deinit(allocator);

    var forward_config = prepared_case.rtm_config;
    forward_config.derivative_mode = .none;
    forward_config.derivative_state_mask = 0;

    // instrumentation: perturbation baseline
    // captures: unmodified forward and OE outputs
    // why: compare every ablation to the same observable boundary.
    Sink.clearPlan();
    Sink.resetCounters();
    var baseline_storage: InstrumentGrid.ProductStorage = .{};
    defer baseline_storage.deinit(allocator);
    var baseline_forward_timer = try std.time.Timer.start();
    const baseline_product = try InstrumentGrid.simulateProductWithWorkspace(
        allocator,
        &baseline_storage,
        &prepared_case.scene,
        forward_config,
        &prepared_case.prepared,
    );
    const baseline_forward_ns = baseline_forward_timer.read();

    const sample_count = baseline_product.reflectance.len;
    const baseline_wavelengths = try allocator.dupe(f64, baseline_product.wavelengths);
    defer allocator.free(baseline_wavelengths);
    const baseline_reflectance = try allocator.dupe(f64, baseline_product.reflectance);
    defer allocator.free(baseline_reflectance);
    const baseline_radiance = try allocator.dupe(f64, baseline_product.radiance);
    defer allocator.free(baseline_radiance);

    const measurement_variance = try allocator.alloc(f64, sample_count);
    defer allocator.free(measurement_variance);
    for (measurement_variance) |*variance| {
        variance.* = measurement_sigma_reflectance * measurement_sigma_reflectance;
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

    Sink.clearPlan();
    Sink.resetCounters();
    const baseline_retrieval = try runRetrieval(
        allocator,
        &input,
        baseline_wavelengths,
        baseline_reflectance,
        measurement_variance,
        &state_specs,
        config.max_iterations,
    );

    var output_file = try openOutputFile(allocator, config.output_dir, "summary.json");
    defer output_file.close();
    var writer = output_file.writer(&.{});
    try writeHeader(
        &writer.interface,
        config,
        sample_count,
        baseline_forward_ns,
        baseline_product.summary,
        baseline_retrieval,
        input.aerosol.optical_depth,
        reference_mid_pressure_hpa,
    );

    var first_experiment = true;
    var experiment_index: usize = 0;
    while (experiment_index < experiments.len) : (experiment_index += 1) {
        const spec = experiments[experiment_index];
        const experiment_id: u32 = @intCast(experiment_index + 1);
        const plan = planFromSpec(experiment_id, spec);

        // instrumentation: perturbation run
        // captures: changed hook counts plus final residuals
        // why: rank pruning ideas without storing per-event rows.
        Sink.resetCounters();
        Sink.setPlan(plan);

        var forward_ns: u64 = 0;
        var spectrum_delta: SpectrumDelta = .{};
        {
            var storage: InstrumentGrid.ProductStorage = .{};
            defer storage.deinit(allocator);
            var forward_timer = try std.time.Timer.start();
            const product = try InstrumentGrid.simulateProductWithWorkspace(
                allocator,
                &storage,
                &prepared_case.scene,
                forward_config,
                &prepared_case.prepared,
            );
            forward_ns = forward_timer.read();
            spectrum_delta = compareSpectra(
                baseline_wavelengths,
                baseline_reflectance,
                baseline_radiance,
                product.reflectance,
                product.radiance,
            );
        }

        const retrieval = try runRetrieval(
            allocator,
            &input,
            baseline_wavelengths,
            baseline_reflectance,
            measurement_variance,
            &state_specs,
            config.max_iterations,
        );
        const counters = Sink.snapshot(@intFromEnum(spec.channel));
        Sink.clearPlan();

        if (!first_experiment) try writer.interface.writeAll(",\n");
        first_experiment = false;
        try writeExperiment(
            &writer.interface,
            experiment_id,
            spec,
            forward_ns,
            spectrum_delta,
            baseline_retrieval,
            retrieval,
            counters,
        );
    }

    try writer.interface.writeAll(
        \\
        \\  ]
        \\}
        \\
    );

    std.debug.print(
        "wrote compact perturbation sensitivity summary to {s}/summary.json (experiments={})\n",
        .{ config.output_dir, experiments.len },
    );
}

fn runRetrieval(
    allocator: std.mem.Allocator,
    input: *const o2a_reference.O2AInput,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_specs: []const OptimalEstimation.StateSpec,
    max_iterations: usize,
) !RetrievalOutcome {
    var product_storage: InstrumentGrid.ProductStorage = .{};
    defer product_storage.deinit(allocator);

    var timer = try std.time.Timer.start();
    var result = try OptimalEstimation.runO2A(
        allocator,
        input,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
        state_specs,
        &product_storage,
        .{
            .max_iterations = max_iterations,
            .state_vector_convergence_threshold = 1.0,
            .max_change_transformed_state = 1.0,
        },
    );
    const wall_ns = timer.read();
    defer result.deinit(allocator);

    return .{
        .wall_ns = wall_ns,
        .converged = result.converged,
        .iteration_count = result.iteration_count,
        .aerosol_optical_depth = result.state[0],
        .aerosol_layer_mid_pressure_hpa = result.state[1],
    };
}

fn compareSpectra(
    wavelengths: []const f64,
    baseline_reflectance: []const f64,
    baseline_radiance: []const f64,
    perturbed_reflectance: []const f64,
    perturbed_radiance: []const f64,
) SpectrumDelta {

    // instrumentation: perturbation summary
    // captures: aggregate spectral deltas
    // why: discard full spectra after computing final-observable movement.

    var delta: SpectrumDelta = .{};
    var sum_abs_reflectance: f64 = 0.0;
    var sum_sq_reflectance: f64 = 0.0;
    var sum_sq_radiance: f64 = 0.0;
    const count = @min(baseline_reflectance.len, perturbed_reflectance.len);
    for (0..count) |index| {
        const reflectance_abs = @abs(perturbed_reflectance[index] - baseline_reflectance[index]);
        sum_abs_reflectance += reflectance_abs;
        sum_sq_reflectance += reflectance_abs * reflectance_abs;
        if (reflectance_abs > delta.max_abs_reflectance_delta) {
            delta.max_abs_reflectance_delta = reflectance_abs;
            delta.max_reflectance_wavelength_nm = wavelengths[index];
        }
        const radiance_abs = @abs(perturbed_radiance[index] - baseline_radiance[index]);
        delta.max_abs_radiance_delta = @max(delta.max_abs_radiance_delta, radiance_abs);
        sum_sq_radiance += radiance_abs * radiance_abs;
    }
    if (count != 0) {
        const denominator: f64 = @floatFromInt(count);
        delta.mean_abs_reflectance_delta = sum_abs_reflectance / denominator;
        delta.rms_reflectance_delta = @sqrt(sum_sq_reflectance / denominator);
        delta.rms_radiance_delta = @sqrt(sum_sq_radiance / denominator);
    }
    return delta;
}

fn planFromSpec(experiment_id: u32, spec: ExperimentSpec) Sink.Plan {
    return .{
        .experiment_id = experiment_id,
        .channel_id = @intFromEnum(spec.channel),
        .mode = spec.mode,
        .scale = spec.scale,
        .min_fourier = spec.min_fourier,
        .max_fourier = spec.max_fourier,
        .min_order = spec.min_order,
        .max_order = spec.max_order,
        .state_filter = spec.state_filter,
        .branch_filter = spec.branch_filter,
        .active = true,
    };
}

fn writeHeader(
    writer: *std.Io.Writer,
    config: Config,
    sample_count: usize,
    baseline_forward_ns: u64,
    summary: InstrumentGrid.InstrumentGridSummary,
    baseline_retrieval: RetrievalOutcome,
    reference_aod: f64,
    reference_mid_pressure_hpa: f64,
) !void {
    try writer.print(
        \\{{
        \\  "schema_version": 1,
        \\  "storage_policy": "compact_summary_only",
        \\  "wavelength_range_nm": {{
        \\    "start": {e:.17},
        \\    "end": {e:.17},
        \\    "sample_count": {}
        \\  }},
        \\  "measurement_sigma_reflectance": {e:.17},
        \\  "baseline": {{
        \\    "forward_wall_ns": {},
        \\    "mean_reflectance": {e:.17},
        \\    "mean_radiance": {e:.17},
        \\    "retrieval_wall_ns": {},
        \\    "retrieval_converged": {},
        \\    "retrieval_iterations": {},
        \\    "reference_aerosol_optical_depth": {e:.17},
        \\    "reference_aerosol_layer_mid_pressure_hpa": {e:.17},
        \\    "retrieved_aerosol_optical_depth": {e:.17},
        \\    "retrieved_aerosol_layer_mid_pressure_hpa": {e:.17}
        \\  }},
        \\  "experiments": [
        \\
    ,
        .{
            config.start_nm,
            config.end_nm,
            sample_count,
            measurement_sigma_reflectance,
            baseline_forward_ns,
            summary.mean_reflectance,
            summary.mean_radiance,
            baseline_retrieval.wall_ns,
            baseline_retrieval.converged,
            baseline_retrieval.iteration_count,
            reference_aod,
            reference_mid_pressure_hpa,
            baseline_retrieval.aerosol_optical_depth,
            baseline_retrieval.aerosol_layer_mid_pressure_hpa,
        },
    );
}

fn writeExperiment(
    writer: *std.Io.Writer,
    experiment_id: u32,
    spec: ExperimentSpec,
    forward_ns: u64,
    spectrum_delta: SpectrumDelta,
    baseline_retrieval: RetrievalOutcome,
    retrieval: RetrievalOutcome,
    counters: Sink.CounterSnapshot,
) !void {
    const aod_delta = retrieval.aerosol_optical_depth - baseline_retrieval.aerosol_optical_depth;
    const pressure_delta =
        retrieval.aerosol_layer_mid_pressure_hpa - baseline_retrieval.aerosol_layer_mid_pressure_hpa;
    const changed_fraction = if (counters.hit_count == 0)
        0.0
    else
        @as(f64, @floatFromInt(counters.changed_count)) / @as(f64, @floatFromInt(counters.hit_count));
    try writer.print(
        \\    {{
        \\      "experiment_id": {},
        \\      "name": "{s}",
        \\      "channel": "{s}",
        \\      "mode": "{s}",
        \\      "filters": {{
        \\        "min_fourier": {},
        \\        "max_fourier": {},
        \\        "min_order": {},
        \\        "max_order": {},
        \\        "branch": {},
        \\        "state": {}
        \\      }},
        \\      "scale": {e:.17},
        \\      "rationale": "{s}",
        \\      "forward": {{
        \\        "wall_ns": {},
        \\        "max_abs_reflectance_delta": {e:.17},
        \\        "mean_abs_reflectance_delta": {e:.17},
        \\        "rms_reflectance_delta": {e:.17},
        \\        "max_reflectance_wavelength_nm": {e:.17},
        \\        "max_abs_radiance_delta": {e:.17},
        \\        "rms_radiance_delta": {e:.17}
        \\      }},
        \\      "retrieval": {{
        \\        "wall_ns": {},
        \\        "converged": {},
        \\        "iterations": {},
        \\        "aerosol_optical_depth_delta": {e:.17},
        \\        "aerosol_layer_mid_pressure_delta_hpa": {e:.17},
        \\        "aerosol_optical_depth_abs_delta": {e:.17},
        \\        "aerosol_layer_mid_pressure_abs_delta_hpa": {e:.17}
        \\      }},
        \\      "suppression": {{
        \\        "hit_count": {},
        \\        "changed_count": {},
        \\        "changed_fraction": {e:.17}
        \\      }}
        \\    }}
    ,
        .{
            experiment_id,
            spec.name,
            channelName(spec.channel),
            modeName(spec.mode),
            spec.min_fourier,
            spec.max_fourier,
            spec.min_order,
            spec.max_order,
            spec.branch_filter,
            spec.state_filter,
            spec.scale,
            spec.rationale,
            forward_ns,
            spectrum_delta.max_abs_reflectance_delta,
            spectrum_delta.mean_abs_reflectance_delta,
            spectrum_delta.rms_reflectance_delta,
            spectrum_delta.max_reflectance_wavelength_nm,
            spectrum_delta.max_abs_radiance_delta,
            spectrum_delta.rms_radiance_delta,
            retrieval.wall_ns,
            retrieval.converged,
            retrieval.iteration_count,
            aod_delta,
            pressure_delta,
            @abs(aod_delta),
            @abs(pressure_delta),
            counters.hit_count,
            counters.changed_count,
            changed_fraction,
        },
    );
}

fn channelName(channel: Perturbation.Channel) []const u8 {

    // instrumentation: perturbation output label
    // captures: stable channel names for report rows
    // why: keep CSV summaries readable without leaking strings into model code.
    return switch (channel) {
        .fourier_weighted_reflectance => "fourier_weighted_reflectance",
        .fourier_tail_break => "fourier_tail_break",
        .qseries_skip => "qseries_skip",
        .qseries_rd_product => "qseries_rd_product",
        .qseries_tu_product => "qseries_tu_product",
        .qseries_td_product => "qseries_td_product",
        .orders_initial_convergence => "orders_initial_convergence",
        .orders_multiple_convergence => "orders_multiple_convergence",
        .aerosol_aod_tangent => "aerosol_aod_tangent",
        .aerosol_pressure_tangent => "aerosol_pressure_tangent",
    };
}

fn modeName(mode: Sink.Mode) []const u8 {
    return switch (mode) {
        .baseline => "baseline",
        .zero => "zero",
        .scale => "scale",
        .force_true => "force_true",
        .force_false => "force_false",
    };
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
        } else if (std.mem.eql(u8, arg, "--start-nm")) {
            index += 1;

            if (index >= args.len) return error.MissingStartNm;
            config.start_nm = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--end-nm")) {
            index += 1;

            if (index >= args.len) return error.MissingEndNm;
            config.end_nm = try std.fmt.parseFloat(f64, args[index]);
        } else if (std.mem.eql(u8, arg, "--sample-count")) {
            index += 1;

            if (index >= args.len) return error.MissingSampleCount;
            config.sample_count = try std.fmt.parseInt(u32, args[index], 10);
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

fn openOutputFile(allocator: std.mem.Allocator, output_dir: []const u8, name: []const u8) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ output_dir, name });
    defer allocator.free(path);
    return std.fs.cwd().createFile(path, .{ .truncate = true });
}
