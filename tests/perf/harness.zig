const std = @import("std");
const zdisamar = @import("zdisamar");

pub const PerfScenario = struct {
    id: []const u8,
    plan_template: []const u8,
    iterations: u32,
    max_runtime_ms: u32,
    upstream_anchor: []const u8,
    status: []const u8,
};

pub const PerfMatrix = struct {
    version: u32,
    scenarios: []const PerfScenario,
};

pub const ScenarioMeasurement = struct {
    id: []u8,
    iterations: u32,
    budget_ms: u64,
    elapsed_ms: u64,
    checksum: u64,
    upstream_anchor_present: bool,
};

pub const BenchReport = struct {
    version: u32,
    scenario_count: usize,
    total_elapsed_ms: u64,
    scenarios: []ScenarioMeasurement,

    pub fn deinit(self: *BenchReport, allocator: std.mem.Allocator) void {
        for (self.scenarios) |scenario| allocator.free(scenario.id);
        allocator.free(self.scenarios);
        self.* = undefined;
    }
};

pub fn loadMatrix(allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(PerfMatrix) {
    const raw = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(raw);

    return try std.json.parseFromSlice(
        PerfMatrix,
        allocator,
        raw,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );
}

pub fn measureMatrix(allocator: std.mem.Allocator, matrix: PerfMatrix) !BenchReport {
    const upstream_root = "vendor/disamar-fortran";
    const upstream_present = pathExists(upstream_root);
    const scenarios = try allocator.alloc(ScenarioMeasurement, matrix.scenarios.len);
    var initialized_scenarios: usize = 0;
    errdefer {
        for (scenarios[0..initialized_scenarios]) |scenario| {
            allocator.free(scenario.id);
        }
        allocator.free(scenarios);
    }

    var engine = zdisamar.Engine.init(allocator, .{ .max_prepared_plans = 4096 });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var workspace = engine.createWorkspace("perf-matrix-suite");
    var total_elapsed_ms: u64 = 0;

    for (matrix.scenarios, 0..) |scenario, index| {
        try ensureExecutableScenario(scenario);

        const anchor_present = if (upstream_present)
            try upstreamAnchorPresent(upstream_root, scenario.upstream_anchor)
        else
            false;

        const template = try scenarioTemplate(scenario.plan_template);
        const iterations: u32 = @min(scenario.iterations, 64);
        const budget_ms: u64 = @as(u64, scenario.max_runtime_ms) * 25 + 100;

        const start_ns = std.time.nanoTimestamp();
        var checksum: u64 = 0;
        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            workspace.reset();
            var plan = try engine.preparePlan(template);
            defer plan.deinit();
            const request = zdisamar.Request.init(.{
                .id = "scene-perf-matrix",
                .spectral_grid = requestSpectralGrid(plan.template),
                .observation_model = .{
                    .regime = plan.template.scene_blueprint.observation_regime,
                },
            });
            var result = try engine.execute(&plan, &workspace, &request);
            defer result.deinit(allocator);
            if (result.status != .success) return error.UnexpectedPerfResult;
            checksum +%= result.plan_id;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_ns;
        const elapsed_ms: u64 = @intCast(@max(@divTrunc(elapsed_ns, std.time.ns_per_ms), 0));

        scenarios[index] = .{
            .id = try allocator.dupe(u8, scenario.id),
            .iterations = iterations,
            .budget_ms = budget_ms,
            .elapsed_ms = elapsed_ms,
            .checksum = checksum,
            .upstream_anchor_present = anchor_present,
        };
        initialized_scenarios += 1;
        total_elapsed_ms += elapsed_ms;
    }

    return .{
        .version = matrix.version,
        .scenario_count = matrix.scenarios.len,
        .total_elapsed_ms = total_elapsed_ms,
        .scenarios = scenarios,
    };
}

pub fn assertBudgets(report: BenchReport) !void {
    for (report.scenarios) |scenario| {
        try std.testing.expect(scenario.checksum > 0);
        try std.testing.expect(scenario.elapsed_ms <= scenario.budget_ms);
    }
}

pub fn writeReportFile(report: BenchReport, output_path: []const u8) !void {
    if (std.fs.path.dirname(output_path)) |dir_path| {
        try std.fs.cwd().makePath(dir_path);
    }

    const file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer file.close();
    var file_writer = file.writer(&.{});
    try std.json.Stringify.value(report, .{ .whitespace = .indent_2 }, &file_writer.interface);
    try file_writer.interface.flush();
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn upstreamAnchorPresent(upstream_root: []const u8, upstream_anchor: []const u8) !bool {
    var anchor_path_buffer: [512]u8 = undefined;
    const anchor_path = try std.fmt.bufPrint(
        &anchor_path_buffer,
        "{s}/{s}",
        .{ upstream_root, upstream_anchor },
    );
    std.fs.cwd().access(anchor_path, .{}) catch return false;
    return true;
}

fn ensureExecutableScenario(scenario: PerfScenario) !void {
    if (!std.mem.eql(u8, scenario.status, "scaffold_executable")) {
        return error.UnexpectedPerfScenarioStatus;
    }
}

fn scenarioTemplate(name: []const u8) !zdisamar.PlanTemplate {
    if (std.mem.eql(u8, name, "default_scalar")) return .{};
    if (std.mem.eql(u8, name, "derivative_enabled")) return .{
        .solver_mode = .scalar,
        .scene_blueprint = .{
            .derivative_mode = .semi_analytical,
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 96,
            },
            .measurement_count_hint = 96,
        },
    };
    if (std.mem.eql(u8, name, "layout_axis_sampling")) return .{
        .scene_blueprint = .{
            .layer_count_hint = 48,
            .state_parameter_count_hint = 4,
            .measurement_count_hint = 128,
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 128,
            },
        },
    };
    if (std.mem.eql(u8, name, "layout_aosoa_block_access")) return .{
        .scene_blueprint = .{
            .layer_count_hint = 64,
            .state_parameter_count_hint = 6,
            .measurement_count_hint = 192,
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 192,
            },
        },
    };
    if (std.mem.eql(u8, name, "kernel_interpolation_linear")) return .{
        .scene_blueprint = .{
            .spectral_grid = .{
                .start_nm = 410.0,
                .end_nm = 470.0,
                .sample_count = 128,
            },
            .measurement_count_hint = 128,
        },
    };
    if (std.mem.eql(u8, name, "kernel_quadrature_trapezoid")) return .{
        .scene_blueprint = .{
            .spectral_grid = .{
                .start_nm = 430.0,
                .end_nm = 450.0,
                .sample_count = 64,
            },
            .measurement_count_hint = 64,
        },
    };
    if (std.mem.eql(u8, name, "kernel_linalg_vector_ops")) return .{
        .scene_blueprint = .{
            .state_parameter_count_hint = 8,
            .measurement_count_hint = 96,
            .spectral_grid = .{
                .start_nm = 415.0,
                .end_nm = 475.0,
                .sample_count = 96,
            },
        },
    };
    if (std.mem.eql(u8, name, "transport_dispatch_adding")) return .{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 72,
            },
            .measurement_count_hint = 72,
        },
    };
    if (std.mem.eql(u8, name, "transport_dispatch_labos")) return .{
        .solver_mode = .polarized,
        .scene_blueprint = .{
            .observation_regime = .limb,
            .derivative_mode = .semi_analytical,
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 88,
            },
            .measurement_count_hint = 88,
        },
    };
    if (std.mem.eql(u8, name, "transport_derivative_contract")) return .{
        .solver_mode = .scalar,
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .numerical,
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 72,
            },
            .measurement_count_hint = 72,
        },
    };
    return error.UnknownPerfTemplate;
}

fn requestSpectralGrid(template: zdisamar.PlanTemplate) zdisamar.SpectralGrid {
    if (template.scene_blueprint.spectral_grid.sample_count > 0) {
        return template.scene_blueprint.spectral_grid;
    }
    return .{
        .start_nm = 405.0,
        .end_nm = 465.0,
        .sample_count = 32,
    };
}
