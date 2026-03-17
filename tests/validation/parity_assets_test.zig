const std = @import("std");

const ParityTolerances = struct {
    absolute: f64,
    relative: f64,
};

const RuntimeProfile = struct {
    observation_regime: []const u8,
    solver_mode: []const u8,
    derivative_mode: []const u8,
    spectral_samples: u32,
};

const ParityCase = struct {
    id: []const u8,
    component: []const u8,
    upstream_case: []const u8,
    upstream_reference_output: ?[]const u8 = null,
    runtime_profile: RuntimeProfile,
    expected_route_family: []const u8,
    expected_derivative_mode: []const u8,
    expected_derivative_semantics: ?[]const u8 = null,
    metrics: []const []const u8,
    tolerances: ParityTolerances,
    status: []const u8,
};

const ParityMatrix = struct {
    version: u32,
    upstream: []const u8,
    parity_level: []const u8,
    cases: []const ParityCase,
};

const PerfScenario = struct {
    id: []const u8,
    plan_template: []const u8,
    iterations: u32,
    max_runtime_ms: u32,
    upstream_anchor: []const u8,
    status: []const u8,
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
    required_native_capability_slot: []const u8,
    required_native_entry_symbol: []const u8,
};

const BundleAsset = struct {
    id: []const u8,
    path: []const u8,
    format: []const u8,
    sha256: []const u8,
    columns: []const []const u8,
};

const BundleUpstream = struct {
    vendor_root: []const u8,
    source_paths: []const []const u8,
    reference_snapshot: []const u8,
};

const BundleManifest = struct {
    version: u32,
    bundle_id: []const u8,
    owner_package: []const u8,
    description: []const u8,
    upstream: BundleUpstream,
    assets: []const BundleAsset,
};

const VendorImport = struct {
    bundle_manifest: []const u8,
    local_asset: []const u8,
    upstream_candidates: []const []const u8,
};

const VendorImportRegistry = struct {
    version: u32,
    upstream_root: []const u8,
    imports: []const VendorImport,
};

fn readValidationFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 1024 * 1024);
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn assertAssetDigest(path: []const u8, expected_sha: []const u8) !void {
    const content = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 1024 * 1024);
    defer std.testing.allocator.free(content);

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(content, &digest, .{});

    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    var expected: [71]u8 = undefined;
    const expected_digest = try std.fmt.bufPrint(
        &expected,
        "sha256:{s}",
        .{digest_hex[0..]},
    );
    try std.testing.expectEqualStrings(expected_digest, expected_sha);
}

test "parity matrix defines executable upstream contract and retrieval-check cases" {
    const raw = try readValidationFile("validation/compatibility/parity_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        ParityMatrix,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expectEqualStrings("hybrid_contract", parsed.value.parity_level);
    try std.testing.expect(parsed.value.cases.len > 0);

    for (parsed.value.cases) |case| {
        try std.testing.expect(case.id.len > 0);
        try std.testing.expect(case.component.len > 0);
        try std.testing.expect(case.upstream_case.len > 0);
        try std.testing.expect(case.runtime_profile.observation_regime.len > 0);
        try std.testing.expect(case.runtime_profile.solver_mode.len > 0);
        try std.testing.expect(case.runtime_profile.derivative_mode.len > 0);
        try std.testing.expect(case.runtime_profile.spectral_samples > 0);
        try std.testing.expect(case.expected_route_family.len > 0);
        try std.testing.expect(case.expected_derivative_mode.len > 0);
        if (case.expected_derivative_semantics) |expected_derivative_semantics| {
            try std.testing.expect(expected_derivative_semantics.len > 0);
        }
        try std.testing.expect(case.metrics.len > 0);
        try std.testing.expect(case.tolerances.absolute >= 0);
        try std.testing.expect(case.tolerances.relative >= 0);
        try std.testing.expect(case.status.len > 0);
    }
}

test "perf matrix defines executable performance scenarios and vendor anchors" {
    const raw = try readValidationFile("validation/perf/perf_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        PerfMatrix,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expect(parsed.value.scenarios.len > 0);

    for (parsed.value.scenarios) |scenario| {
        try std.testing.expect(scenario.id.len > 0);
        try std.testing.expect(scenario.plan_template.len > 0);
        try std.testing.expect(scenario.iterations > 0);
        try std.testing.expect(scenario.max_runtime_ms > 0);
        try std.testing.expect(scenario.upstream_anchor.len > 0);
        try std.testing.expect(scenario.status.len > 0);
    }
}

test "plugin validation matrix enforces explicit lane coverage" {
    const raw = try readValidationFile("validation/plugin_tests/plugin_validation_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        PluginValidationMatrix,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
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

test "bundle manifests define tracked assets with valid digests" {
    const manifest_paths = [_][]const u8{
        "data/climatologies/bundle_manifest.json",
        "data/cross_sections/bundle_manifest.json",
        "data/luts/bundle_manifest.json",
    };

    for (manifest_paths) |manifest_path| {
        const raw = try readValidationFile(manifest_path);
        defer std.testing.allocator.free(raw);

        const parsed = try std.json.parseFromSlice(
            BundleManifest,
            std.testing.allocator,
            raw,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
        try std.testing.expect(parsed.value.bundle_id.len > 0);
        try std.testing.expect(parsed.value.owner_package.len > 0);
        try std.testing.expect(parsed.value.description.len > 0);
        try std.testing.expect(parsed.value.upstream.vendor_root.len > 0);
        try std.testing.expect(parsed.value.upstream.source_paths.len > 0);
        try std.testing.expect(parsed.value.upstream.reference_snapshot.len > 0);
        try std.testing.expect(parsed.value.assets.len > 0);

        for (parsed.value.assets) |asset| {
            try std.testing.expect(asset.id.len > 0);
            try std.testing.expect(asset.path.len > 0);
            try std.testing.expect(asset.format.len > 0);
            try std.testing.expect(asset.columns.len > 0);
            try std.testing.expect(std.mem.startsWith(u8, asset.sha256, "sha256:"));
            try std.fs.cwd().access(asset.path, .{});
            try assertAssetDigest(asset.path, asset.sha256);
        }
    }
}

test "vendor import registry maps local bundles to upstream references" {
    const raw = try readValidationFile("validation/compatibility/vendor_import_registry.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        VendorImportRegistry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expect(parsed.value.upstream_root.len > 0);
    try std.testing.expect(parsed.value.imports.len > 0);

    const has_upstream_root = pathExists(parsed.value.upstream_root);
    for (parsed.value.imports) |entry| {
        try std.testing.expect(entry.bundle_manifest.len > 0);
        try std.testing.expect(entry.local_asset.len > 0);
        try std.testing.expect(entry.upstream_candidates.len > 0);
        try std.fs.cwd().access(entry.bundle_manifest, .{});
        try std.fs.cwd().access(entry.local_asset, .{});

        if (has_upstream_root) {
            var saw_upstream_candidate = false;
            for (entry.upstream_candidates) |candidate| {
                var buffer: [512]u8 = undefined;
                const joined = try std.fmt.bufPrint(&buffer, "{s}/{s}", .{
                    parsed.value.upstream_root,
                    candidate,
                });
                if (pathExists(joined)) {
                    saw_upstream_candidate = true;
                    break;
                }
            }
            try std.testing.expect(saw_upstream_candidate);
        }
    }
}

test "golden provenance fixture defines default release evidence keys" {
    const raw = try readValidationFile("validation/golden/result_provenance_golden.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        ProvenanceGolden,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
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
    try std.testing.expectEqual(@as(usize, 0), parsed.value.required_native_capability_slot.len);
    try std.testing.expectEqual(@as(usize, 0), parsed.value.required_native_entry_symbol.len);
}

test "release readiness matrix ties commands packages and evidence together" {
    const raw = try readValidationFile("validation/release/release_readiness.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        ReleaseReadiness,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
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
