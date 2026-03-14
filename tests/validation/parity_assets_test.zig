const std = @import("std");

const ParityTolerances = struct {
    absolute: f64,
    relative: f64,
};

const ParityCase = struct {
    id: []const u8,
    component: []const u8,
    upstream_case: []const u8,
    metrics: []const []const u8,
    tolerances: ParityTolerances,
    status: []const u8,
};

const ParityMatrix = struct {
    version: u32,
    upstream: []const u8,
    cases: []const ParityCase,
};

const PerfScenario = struct {
    id: []const u8,
    plan_template: []const u8,
    iterations: u32,
    max_runtime_ms: u32,
};

const PerfMatrix = struct {
    version: u32,
    scenarios: []const PerfScenario,
};

const PluginCase = struct {
    id: []const u8,
    lane: []const u8,
    capability_slot: []const u8,
    status: []const u8,
};

const PluginValidationMatrix = struct {
    version: u32,
    cases: []const PluginCase,
};

const ReleasePackage = struct {
    name: []const u8,
    version: []const u8,
};

const ReleaseReadiness = struct {
    version: u32,
    required_commands: []const []const u8,
    required_packages: []const ReleasePackage,
    required_plugin_versions: []const []const u8,
    required_artifacts: []const []const u8,
};

const ProvenanceGolden = struct {
    engine_version: []const u8,
    model_family_default: []const u8,
    solver_route_default: []const u8,
    transport_family_default: []const u8,
    derivative_mode_default: []const u8,
    numerical_mode_default: []const u8,
    plugin_inventory_generation_min: u64,
    required_plugin_version: []const u8,
    required_dataset_hash: []const u8,
};

fn readValidationFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 1024 * 1024);
}

test "parity matrix defines bounded upstream comparisons and tolerances" {
    const raw = try readValidationFile("validation/compatibility/parity_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        ParityMatrix,
        std.testing.allocator,
        raw,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expect(parsed.value.cases.len > 0);

    for (parsed.value.cases) |case| {
        try std.testing.expect(case.id.len > 0);
        try std.testing.expect(case.component.len > 0);
        try std.testing.expect(case.upstream_case.len > 0);
        try std.testing.expect(case.metrics.len > 0);
        try std.testing.expect(case.tolerances.absolute > 0);
        try std.testing.expect(case.tolerances.relative > 0);
        try std.testing.expect(case.status.len > 0);
    }
}

test "perf matrix defines scenarios and execution budgets" {
    const raw = try readValidationFile("validation/perf/perf_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        PerfMatrix,
        std.testing.allocator,
        raw,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expect(parsed.value.scenarios.len > 0);

    for (parsed.value.scenarios) |scenario| {
        try std.testing.expect(scenario.id.len > 0);
        try std.testing.expect(scenario.plan_template.len > 0);
        try std.testing.expect(scenario.iterations > 0);
        try std.testing.expect(scenario.max_runtime_ms > 0);
    }
}

test "plugin validation matrix enforces explicit lane coverage" {
    const raw = try readValidationFile("validation/plugin_tests/plugin_validation_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        PluginValidationMatrix,
        std.testing.allocator,
        raw,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expect(parsed.value.cases.len > 0);

    for (parsed.value.cases) |case| {
        const supported_lane =
            std.mem.eql(u8, case.lane, "declarative") or std.mem.eql(u8, case.lane, "native");
        try std.testing.expect(case.id.len > 0);
        try std.testing.expect(case.capability_slot.len > 0);
        try std.testing.expect(case.status.len > 0);
        try std.testing.expect(supported_lane);
    }
}

test "golden provenance fixture defines default release evidence keys" {
    const raw = try readValidationFile("validation/golden/result_provenance_golden.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        ProvenanceGolden,
        std.testing.allocator,
        raw,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expect(parsed.value.engine_version.len > 0);
    try std.testing.expect(parsed.value.model_family_default.len > 0);
    try std.testing.expect(parsed.value.solver_route_default.len > 0);
    try std.testing.expect(parsed.value.transport_family_default.len > 0);
    try std.testing.expect(parsed.value.derivative_mode_default.len > 0);
    try std.testing.expect(parsed.value.numerical_mode_default.len > 0);
    try std.testing.expect(parsed.value.plugin_inventory_generation_min > 0);
    try std.testing.expect(parsed.value.required_plugin_version.len > 0);
    try std.testing.expect(parsed.value.required_dataset_hash.len > 0);
}

test "release readiness matrix ties commands packages and evidence together" {
    const raw = try readValidationFile("validation/release/release_readiness.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        ReleaseReadiness,
        std.testing.allocator,
        raw,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expect(parsed.value.required_commands.len > 0);
    try std.testing.expect(parsed.value.required_packages.len > 0);
    try std.testing.expect(parsed.value.required_plugin_versions.len > 0);
    try std.testing.expect(parsed.value.required_artifacts.len > 0);

    for (parsed.value.required_commands) |command| {
        try std.testing.expect(command.len > 0);
    }

    for (parsed.value.required_packages) |package| {
        try std.testing.expect(package.name.len > 0);
        try std.testing.expect(package.version.len > 0);
    }

    for (parsed.value.required_plugin_versions) |plugin_version| {
        try std.testing.expect(plugin_version.len > 0);
        try std.testing.expect(std.mem.indexOfScalar(u8, plugin_version, '@') != null);
    }

    for (parsed.value.required_artifacts) |artifact| {
        try std.testing.expect(artifact.len > 0);
        try std.fs.cwd().access(artifact, .{});
    }
}
