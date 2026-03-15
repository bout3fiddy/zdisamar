const std = @import("std");
const zdisamar = @import("zdisamar");
const retrieval = @import("retrieval");

const RuntimeProfile = struct {
    observation_regime: []const u8,
    solver_mode: []const u8,
    derivative_mode: []const u8,
    spectral_samples: u32,
};

const ParityCase = struct {
    id: []const u8,
    component: []const u8,
    retrieval_method: ?[]const u8 = null,
    upstream_case: []const u8,
    upstream_reference_output: ?[]const u8 = null,
    upstream_numeric_anchor: ?[]const u8 = null,
    runtime_profile: RuntimeProfile,
    expected_route_family: []const u8,
    expected_derivative_mode: []const u8,
    expected_jacobians_used: ?bool = null,
    status: []const u8,
    tolerances: struct {
        absolute: f64,
        relative: f64,
    },
};

const ParityMatrix = struct {
    version: u32,
    upstream: []const u8,
    parity_level: []const u8,
    cases: []const ParityCase,
};

fn parseObservationRegime(value: []const u8) !zdisamar.ObservationRegime {
    if (std.mem.eql(u8, value, "nadir")) return .nadir;
    if (std.mem.eql(u8, value, "limb")) return .limb;
    if (std.mem.eql(u8, value, "occultation")) return .occultation;
    return error.InvalidObservationRegime;
}

fn parseSolverMode(value: []const u8) !zdisamar.SolverMode {
    if (std.mem.eql(u8, value, "scalar")) return .scalar;
    if (std.mem.eql(u8, value, "polarized")) return .polarized;
    if (std.mem.eql(u8, value, "derivative_enabled")) return .derivative_enabled;
    return error.InvalidSolverMode;
}

fn parseDerivativeMode(value: []const u8) !zdisamar.DerivativeMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "semi_analytical")) return .semi_analytical;
    if (std.mem.eql(u8, value, "analytical_plugin")) return .analytical_plugin;
    if (std.mem.eql(u8, value, "numerical")) return .numerical;
    return error.InvalidDerivativeMode;
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

const VendorRetrievalAnchor = struct {
    iterations: u32,
    solution_has_converged: bool,
    chi2: f64,
    dfs: f64,
};

fn parseRetrievalMethod(value: []const u8) !retrieval.common.contracts.Method {
    if (std.mem.eql(u8, value, "oe")) return .oe;
    if (std.mem.eql(u8, value, "doas")) return .doas;
    if (std.mem.eql(u8, value, "dismas")) return .dismas;
    return error.InvalidRetrievalMethod;
}

fn makeRetrievalRequest(
    case: ParityCase,
    regime: zdisamar.ObservationRegime,
    derivative_mode: zdisamar.DerivativeMode,
) !zdisamar.Request {
    const method = try parseRetrievalMethod(case.retrieval_method orelse return error.MissingRetrievalMethod);
    const state_parameter_names: []const []const u8 = switch (method) {
        .oe => &[_][]const u8{ "albedo", "aerosol" },
        .doas => &[_][]const u8{"slant_column"},
        .dismas => &[_][]const u8{ "state_a", "state_b", "state_c" },
    };
    const measurement_product = switch (method) {
        .oe => "radiance",
        .doas => "slant_column",
        .dismas => "multi_band_signal",
    };

    const scene: zdisamar.Scene = .{
        .id = case.id,
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = case.runtime_profile.spectral_samples,
        },
        .observation_model = .{
            .instrument = "compatibility-harness",
            .regime = regime,
            .sampling = "synthetic",
            .noise_model = "shot_noise",
        },
        .atmosphere = .{
            .layer_count = 24,
        },
    };

    return .{
        .scene = scene,
        .inverse_problem = .{
            .id = case.id,
            .state_vector = .{
                .parameter_names = state_parameter_names,
                .value_count = @intCast(state_parameter_names.len),
            },
            .measurements = .{
                .product = measurement_product,
                .sample_count = case.runtime_profile.spectral_samples,
            },
        },
        .expected_derivative_mode = derivative_mode,
        .diagnostics = .{ .jacobians = derivative_mode != .none },
    };
}

fn executeRetrievalCase(case: ParityCase, request: zdisamar.Request) !retrieval.common.contracts.SolverOutcome {
    const problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(request);
    const method = try parseRetrievalMethod(case.retrieval_method orelse return error.MissingRetrievalMethod);
    return switch (method) {
        .oe => retrieval.oe.solver.solve(problem),
        .doas => retrieval.doas.solver.solve(problem),
        .dismas => retrieval.dismas.solver.solve(problem),
    };
}

fn parseVendorAsciiHdfAnchor(path: []const u8, allocator: std.mem.Allocator) !VendorRetrievalAnchor {
    const raw = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(raw);

    var in_root_group = false;
    var in_root_attributes = false;
    var anchor: VendorRetrievalAnchor = .{
        .iterations = 0,
        .solution_has_converged = false,
        .chi2 = 0.0,
        .dfs = 0.0,
    };
    var seen_iterations = false;
    var seen_converged = false;
    var seen_chi2 = false;
    var seen_dfs = false;

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        if (std.mem.eql(u8, line, "BeginGroup(/)")) {
            in_root_group = true;
            continue;
        }
        if (!in_root_group) continue;
        if (std.mem.eql(u8, line, "BeginAttributes")) {
            in_root_attributes = true;
            continue;
        }
        if (std.mem.eql(u8, line, "EndAttributes")) break;
        if (!in_root_attributes) continue;

        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..separator], " \t");
        const value = std.mem.trim(u8, line[separator + 1 ..], " \t");

        if (std.mem.eql(u8, key, "number of iterations")) {
            anchor.iterations = try std.fmt.parseInt(u32, value, 10);
            seen_iterations = true;
        } else if (std.mem.eql(u8, key, "solution_has_converged")) {
            if (std.mem.eql(u8, value, "true")) {
                anchor.solution_has_converged = true;
            } else if (std.mem.eql(u8, value, "false")) {
                anchor.solution_has_converged = false;
            } else return error.InvalidVendorBool;
            seen_converged = true;
        } else if (std.mem.eql(u8, key, "chi2")) {
            anchor.chi2 = try std.fmt.parseFloat(f64, value);
            seen_chi2 = true;
        } else if (std.mem.eql(u8, key, "DFS")) {
            anchor.dfs = try std.fmt.parseFloat(f64, value);
            seen_dfs = true;
        }
    }

    if (!seen_iterations or !seen_converged or !seen_chi2 or !seen_dfs) {
        return error.MissingVendorAnchorFields;
    }
    return anchor;
}

fn expectNear(actual: f64, expected: f64, absolute_tolerance: f64, relative_tolerance: f64) !void {
    const delta = @abs(actual - expected);
    if (delta <= absolute_tolerance) return;

    const scale = @max(@abs(expected), 1.0);
    try std.testing.expect(delta <= scale * relative_tolerance);
}

test "compatibility harness executes bounded parity matrix cases against vendor anchors" {
    const raw = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "validation/compatibility/parity_matrix.json",
        1024 * 1024,
    );
    defer std.testing.allocator.free(raw);

    const matrix = try std.json.parseFromSlice(
        ParityMatrix,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer matrix.deinit();

    try std.testing.expectEqual(@as(u32, 1), matrix.value.version);
    try std.testing.expectEqualStrings("hybrid_contract", matrix.value.parity_level);
    try std.testing.expect(matrix.value.cases.len > 0);

    const upstream_present = pathExists(matrix.value.upstream);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{ .max_prepared_plans = 64 });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var workspace = engine.createWorkspace("compatibility-suite");
    var executed_cases: usize = 0;

    for (matrix.value.cases) |case| {
        if (std.mem.eql(u8, case.component, "retrieval")) {
            const supported_status =
                std.mem.eql(u8, case.status, "retrieval_executed_contract") or
                std.mem.eql(u8, case.status, "retrieval_numeric_anchor");
            try std.testing.expect(supported_status);
        } else {
            try std.testing.expectEqualStrings("scaffold_executable", case.status);
        }
        if (upstream_present) {
            var upstream_case_path_buffer: [512]u8 = undefined;
            const upstream_case_path = try std.fmt.bufPrint(
                &upstream_case_path_buffer,
                "{s}/{s}",
                .{ matrix.value.upstream, case.upstream_case },
            );
            try std.fs.cwd().access(upstream_case_path, .{});

            if (case.upstream_reference_output) |reference_output| {
                var upstream_output_path_buffer: [512]u8 = undefined;
                const upstream_output_path = try std.fmt.bufPrint(
                    &upstream_output_path_buffer,
                    "{s}/{s}",
                    .{ matrix.value.upstream, reference_output },
                );
                try std.fs.cwd().access(upstream_output_path, .{});
            }
        }

        const solver_mode = try parseSolverMode(case.runtime_profile.solver_mode);
        const derivative_mode = try parseDerivativeMode(case.runtime_profile.derivative_mode);
        const regime = try parseObservationRegime(case.runtime_profile.observation_regime);

        const plan = try engine.preparePlan(.{
            .solver_mode = solver_mode,
            .scene_blueprint = .{
                .id = case.id,
                .observation_regime = regime,
                .derivative_mode = derivative_mode,
                .spectral_grid = .{
                    .start_nm = 405.0,
                    .end_nm = 465.0,
                    .sample_count = case.runtime_profile.spectral_samples,
                },
                .measurement_count_hint = case.runtime_profile.spectral_samples,
            },
        });

        workspace.reset();
        var scene_id_storage: [128]u8 = undefined;
        const scene_id = try std.fmt.bufPrint(&scene_id_storage, "scene-{s}", .{case.id});
        const request = if (std.mem.eql(u8, case.component, "retrieval"))
            try makeRetrievalRequest(case, regime, derivative_mode)
        else
            zdisamar.Request.init(.{
                .id = scene_id,
                .spectral_grid = .{
                    .start_nm = 405.0,
                    .end_nm = 465.0,
                    .sample_count = case.runtime_profile.spectral_samples,
                },
                .observation_model = .{
                    .regime = regime,
                },
            });
        const result = try engine.execute(&plan, &workspace, request);

        try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
        try std.testing.expectEqualStrings(case.expected_route_family, result.provenance.transport_family);
        try std.testing.expectEqualStrings(case.expected_derivative_mode, result.provenance.derivative_mode);

        if (std.mem.eql(u8, case.component, "retrieval")) {
            const outcome = try executeRetrievalCase(case, request);
            try std.testing.expectEqualStrings(case.retrieval_method.?, @tagName(outcome.method));
            try std.testing.expectEqualStrings(case.id, outcome.scene_id);
            try std.testing.expect(outcome.iterations > 0);
            try std.testing.expect(outcome.cost >= 0.0);
            try std.testing.expect(outcome.dfs > 0.0);
            try std.testing.expectEqual(case.expected_jacobians_used.?, outcome.jacobians_used);

            if (case.upstream_numeric_anchor) |numeric_anchor| {
                var upstream_anchor_path_buffer: [512]u8 = undefined;
                const upstream_anchor_path = try std.fmt.bufPrint(
                    &upstream_anchor_path_buffer,
                    "{s}/{s}",
                    .{ matrix.value.upstream, numeric_anchor },
                );
                const anchor = try parseVendorAsciiHdfAnchor(upstream_anchor_path, std.testing.allocator);

                const iteration_delta = @abs(@as(i64, @intCast(outcome.iterations)) - @as(i64, @intCast(anchor.iterations)));
                try std.testing.expect(@as(f64, @floatFromInt(iteration_delta)) <= case.tolerances.absolute);
                try std.testing.expectEqual(anchor.solution_has_converged, outcome.converged);
                try expectNear(outcome.cost, anchor.chi2, case.tolerances.absolute, case.tolerances.relative);
                try expectNear(outcome.dfs, anchor.dfs, case.tolerances.absolute, case.tolerances.relative);
            }
        }
        executed_cases += 1;
    }

    try std.testing.expect(executed_cases > 0);
}

test "compatibility harness parses bounded vendor retrieval diagnostics from asciiHDF" {
    const anchor = try parseVendorAsciiHdfAnchor(
        "vendor/disamar-fortran/test/disamar.asciiHDF",
        std.testing.allocator,
    );

    try std.testing.expect(anchor.iterations > 0);
    try std.testing.expect(anchor.solution_has_converged);
    try std.testing.expect(anchor.chi2 >= 0.0);
    try std.testing.expect(anchor.dfs > 0.0);
}
