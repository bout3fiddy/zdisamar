const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const retrieval = @import("zdisamar_internal").retrieval;

const MeasurementSpace = internal.kernels.transport.measurement;
const StateParameter = zdisamar.StateParameter;

const RealEvaluatorContext = struct {
    allocator: std.mem.Allocator,
    plan: *const zdisamar.PreparedPlan,
};

const OeReferenceAnchor = struct {
    version: u32,
    scenario: []const u8,
    iterations: u32,
    converged: bool,
    cost: f64,
    dfs: f64,
    state_estimate: []const f64,
    tolerances: struct {
        cost_relative: f64,
        dfs_absolute: f64,
        state_absolute: f64,
    },
};

const LoadedOeReferenceAnchor = struct {
    raw: []u8,
    parsed: std.json.Parsed(OeReferenceAnchor),

    fn deinit(self: *LoadedOeReferenceAnchor, allocator: std.mem.Allocator) void {
        self.parsed.deinit();
        allocator.free(self.raw);
        self.* = undefined;
    }
};

fn matrixIndex(row: usize, column: usize, ncols: usize) usize {
    return row * ncols + column;
}

fn matrixTrace(values: []const f64, dimension: usize) f64 {
    var total: f64 = 0.0;
    for (0..dimension) |index| {
        total += values[matrixIndex(index, index, dimension)];
    }
    return total;
}

fn makeOutputRoot(prefix: []const u8, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "zig-cache/oe-parity/{s}-{d}",
        .{ prefix, @as(u64, @intCast(@abs(std.time.nanoTimestamp()))) },
    );
}

fn replaceAllAlloc(
    allocator: std.mem.Allocator,
    haystack: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, cursor, needle)) |match_index| {
        try output.appendSlice(allocator, haystack[cursor..match_index]);
        try output.appendSlice(allocator, replacement);
        cursor = match_index + needle.len;
    }
    try output.appendSlice(allocator, haystack[cursor..]);
    return output.toOwnedSlice(allocator);
}

fn realEvaluator(context: *const RealEvaluatorContext) retrieval.common.forward_model.Evaluator {
    return .{
        .context = context,
        .evaluateSummary = realEvaluateSummary,
        .evaluateProduct = realEvaluateProduct,
    };
}

fn realObservedProduct(
    allocator: std.mem.Allocator,
    context: *const RealEvaluatorContext,
    scene: zdisamar.Scene,
) !MeasurementSpace.MeasurementSpaceProduct {
    return realEvaluateProduct(allocator, context, scene);
}

fn realEvaluateSummary(
    context_ptr: *const anyopaque,
    scene: zdisamar.Scene,
) anyerror!MeasurementSpace.MeasurementSpaceSummary {
    const context: *const RealEvaluatorContext = @ptrCast(@alignCast(context_ptr));
    var measurement = try realEvaluateProduct(context.allocator, context_ptr, scene);
    defer measurement.deinit(context.allocator);
    return measurement.summary;
}

fn realEvaluateProduct(
    allocator: std.mem.Allocator,
    context_ptr: *const anyopaque,
    scene: zdisamar.Scene,
) anyerror!MeasurementSpace.MeasurementSpaceProduct {
    const context: *const RealEvaluatorContext = @ptrCast(@alignCast(context_ptr));
    return simulateSceneProduct(allocator, context.plan, scene);
}

fn simulateSceneProduct(
    allocator: std.mem.Allocator,
    plan: *const zdisamar.PreparedPlan,
    scene: zdisamar.Scene,
) !MeasurementSpace.MeasurementSpaceProduct {
    var prepared_optics = try plan.providers.optics.prepareForScene(allocator, &scene);
    defer prepared_optics.deinit(allocator);
    return MeasurementSpace.simulateProduct(
        allocator,
        &scene,
        plan.transport_route,
        &prepared_optics,
        .{
            .transport = plan.providers.transport,
            .surface = plan.providers.surface,
            .instrument = plan.providers.instrument,
            .noise = plan.providers.noise,
        },
    );
}

fn maskedResidualNorm(
    measurement: zdisamar.Measurement,
    wavelengths_nm: []const f64,
    truth: []const f64,
    candidate: []const f64,
) f64 {
    std.debug.assert(wavelengths_nm.len == truth.len);
    std.debug.assert(truth.len == candidate.len);

    var total: f64 = 0.0;
    for (wavelengths_nm, truth, candidate) |wavelength_nm, truth_value, candidate_value| {
        if (!measurement.includesWavelength(wavelength_nm)) continue;
        const delta = truth_value - candidate_value;
        total += delta * delta;
    }
    return std.math.sqrt(total);
}

fn loadOeReferenceAnchor(allocator: std.mem.Allocator) !LoadedOeReferenceAnchor {
    const raw = try std.fs.cwd().readFileAlloc(
        allocator,
        "validation/golden/oe_reference_anchor.json",
        16 * 1024,
    );
    errdefer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(
        OeReferenceAnchor,
        allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    return .{ .raw = raw, .parsed = parsed };
}

test "oe parity executes the full expert o2a scenario and improves the masked spectral fit" {
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try makeOutputRoot("expert", &root_buffer);
    defer std.fs.cwd().deleteTree(root) catch {};

    const expert_bytes = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "data/examples/zdisamar_expert_o2a.yaml",
        128 * 1024,
    );
    defer std.testing.allocator.free(expert_bytes);

    const output_replacement = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/", .{root});
    defer std.testing.allocator.free(output_replacement);
    const expert_yaml = try replaceAllAlloc(std.testing.allocator, expert_bytes, "file://out/", output_replacement);
    defer std.testing.allocator.free(expert_yaml);

    var document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        "zdisamar_expert_o2a.yaml",
        "data/examples",
        expert_yaml,
    );
    defer document.deinit();

    var resolved: ?*zdisamar.canonical_config.ResolvedExperiment = try document.resolve(std.testing.allocator);
    defer if (resolved) |owned| owned.deinit();

    var program = try zdisamar.canonical_config.compileResolved(std.testing.allocator, resolved.?);
    resolved = null;
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 2), program.stages.len);
    const retrieval_stage = program.stages[1].stage;
    const inverse = retrieval_stage.inverse.?;
    try std.testing.expectEqual(@as(usize, 6), inverse.state_vector.parameters.len);
    try std.testing.expectEqual(@as(@TypeOf(inverse.state_vector.parameters[1].target), .aerosol_layer_center_km), inverse.state_vector.parameters[1].target);
    try std.testing.expectEqual(@as(@TypeOf(inverse.state_vector.parameters[3].target), .wavelength_shift_nm), inverse.state_vector.parameters[3].target);
    try std.testing.expectEqual(@as(@TypeOf(inverse.state_vector.parameters[4].target), .multiplicative_offset), inverse.state_vector.parameters[4].target);
    try std.testing.expectEqual(@as(@TypeOf(inverse.state_vector.parameters[5].target), .stray_light), inverse.state_vector.parameters[5].target);
    try std.testing.expectEqual(@as(usize, 1), inverse.covariance_blocks.len);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1 }, inverse.covariance_blocks[0].parameter_indices);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var retrieval_plan = try engine.preparePlan(retrieval_stage.plan);
    defer retrieval_plan.deinit();
    var initial_product = try simulateSceneProduct(std.testing.allocator, &retrieval_plan, retrieval_stage.scene);
    defer initial_product.deinit(std.testing.allocator);

    const execution = try program.execute(std.testing.allocator, &engine);
    defer {
        var outcome = execution;
        outcome.deinit();
    }

    try std.testing.expectEqual(@as(usize, 2), execution.stage_outcomes.len);
    try std.testing.expectEqual(zdisamar.Result.Status.success, execution.stage_outcomes[0].result.status);
    try std.testing.expectEqual(zdisamar.Result.Status.success, execution.stage_outcomes[1].result.status);

    const truth_product = execution.stage_outcomes[0].result.measurement_space_product.?;
    const retrieval_result = execution.stage_outcomes[1].result.retrieval.?;
    const fitted_product = execution.stage_outcomes[1].result.retrieval_products.fitted_measurement.?;

    const initial_residual = maskedResidualNorm(inverse.measurements, truth_product.wavelengths, truth_product.radiance, initial_product.radiance);
    const final_residual = maskedResidualNorm(inverse.measurements, truth_product.wavelengths, truth_product.radiance, fitted_product.radiance);

    try std.testing.expect(final_residual < initial_residual);
    try std.testing.expectEqual(@as(usize, 6), retrieval_result.state_estimate.values.len);
    try std.testing.expect(retrieval_result.jacobian != null);
    try std.testing.expect(retrieval_result.averaging_kernel != null);
    try std.testing.expect(retrieval_result.posterior_covariance != null);
    try std.testing.expect(execution.stage_outcomes[1].result.retrieval_products.jacobian != null);
    try std.testing.expect(execution.stage_outcomes[1].result.retrieval_products.averaging_kernel != null);
    try std.testing.expect(execution.stage_outcomes[1].result.retrieval_products.posterior_covariance != null);

    const jacobian = retrieval_result.jacobian.?;
    const averaging_kernel = retrieval_result.averaging_kernel.?;
    const posterior = retrieval_result.posterior_covariance.?;
    try std.testing.expectEqual(inverse.measurements.sample_count, jacobian.row_count);
    try std.testing.expectEqual(@as(u32, 6), jacobian.column_count);
    try std.testing.expectEqual(@as(u32, 6), averaging_kernel.row_count);
    try std.testing.expectEqual(@as(u32, 6), averaging_kernel.column_count);
    try std.testing.expectEqual(@as(u32, 6), posterior.row_count);
    try std.testing.expectEqual(@as(u32, 6), posterior.column_count);
    try std.testing.expectApproxEqAbs(
        retrieval_result.dfs,
        matrixTrace(averaging_kernel.values, @as(usize, @intCast(averaging_kernel.row_count))),
        1.0e-8,
    );
}

test "oe reference scenario matches the golden spectral-fit anchor" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .providers = .{ .retrieval_algorithm = "builtin.oe_solver" },
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .semi_analytical,
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 48 },
            .measurement_count_hint = 48,
        },
    });
    defer plan.deinit();

    const context: RealEvaluatorContext = .{
        .allocator = std.testing.allocator,
        .plan = &plan,
    };
    const evaluator = realEvaluator(&context);

    var observed_product = try realObservedProduct(std.testing.allocator, &context, .{
        .id = "truth-scene-oe-anchor",
        .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 48 },
        .surface = .{ .albedo = 0.16 },
        .aerosol = .{ .enabled = true, .optical_depth = 0.10, .layer_center_km = 3.0, .layer_width_km = 1.0 },
        .observation_model = .{ .instrument = .synthetic, .noise_model = .shot_noise, .wavelength_shift_nm = 0.012 },
    });
    defer observed_product.deinit(std.testing.allocator);

    const problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = .{
            .id = "scene-retrieval-oe-anchor",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 48 },
            .surface = .{ .albedo = 0.08 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.05, .layer_center_km = 3.0, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = .synthetic, .noise_model = .shot_noise },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-oe-anchor",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.04 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 3.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = -0.2, .max = 0.2 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 48,
                .source = .{ .external_observation = .{ .name = "truth_radiance" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = 48,
            .product = .init(&observed_product),
        },
    };

    const result = try retrieval.oe.solver.solveWithEvaluator(std.testing.allocator, problem, evaluator);
    defer {
        var owned = result;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(result.jacobian != null);
    try std.testing.expect(result.averaging_kernel != null);
    try std.testing.expect(result.posterior_covariance != null);

    var anchor = try loadOeReferenceAnchor(std.testing.allocator);
    defer anchor.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 1), anchor.parsed.value.version);
    try std.testing.expectEqualStrings("oe_reference_spectral_fit", anchor.parsed.value.scenario);
    try std.testing.expectEqual(anchor.parsed.value.iterations, result.iterations);
    try std.testing.expectEqual(anchor.parsed.value.converged, result.converged);
    try std.testing.expectApproxEqRel(anchor.parsed.value.cost, result.cost, anchor.parsed.value.tolerances.cost_relative);
    try std.testing.expectApproxEqAbs(anchor.parsed.value.dfs, result.dfs, anchor.parsed.value.tolerances.dfs_absolute);
    try std.testing.expectEqual(anchor.parsed.value.state_estimate.len, result.state_estimate.values.len);
    for (anchor.parsed.value.state_estimate, result.state_estimate.values) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected, actual, anchor.parsed.value.tolerances.state_absolute);
    }
}
