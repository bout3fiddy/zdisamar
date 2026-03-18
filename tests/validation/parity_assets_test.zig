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
    upstream_numeric_anchor: ?[]const u8 = null,
    runtime_profile: RuntimeProfile,
    expected_route_family: []const u8,
    expected_derivative_mode: []const u8,
    expected_derivative_semantics: ?[]const u8 = null,
    expected_jacobians_used: ?bool = null,
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

const DoasDominoReferenceAnchor = struct {
    version: u32,
    scenario: []const u8,
    source_config: []const u8,
    iterations: u32,
    wavelength_amf_nm: f64,
    total_slant_column_molec_cm2: f64,
    stratospheric_vertical_column_molec_cm2: f64,
    stratospheric_slant_column_molec_cm2: f64,
    retrieved_trop_slant_column_molec_cm2: f64,
    retrieved_trop_vertical_column_molec_cm2: f64,
    trop_amf: f64,
    precision_trop_vertical_column_molec_cm2: f64,
    tolerances: struct {
        slant_column_relative: f64,
        vertical_column_relative: f64,
        amf_absolute: f64,
    },
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
        if (case.upstream_reference_output) |reference_output| try std.testing.expect(reference_output.len > 0);
        if (case.upstream_numeric_anchor) |numeric_anchor| try std.testing.expect(numeric_anchor.len > 0);
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

test "oe reference anchor defines stable retrieval diagnostics" {
    const raw = try readValidationFile("validation/golden/oe_reference_anchor.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        OeReferenceAnchor,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expect(parsed.value.scenario.len > 0);
    try std.testing.expect(parsed.value.iterations > 0);
    try std.testing.expect(parsed.value.converged);
    try std.testing.expect(parsed.value.cost >= 0.0);
    try std.testing.expect(parsed.value.dfs > 0.0);
    try std.testing.expect(parsed.value.state_estimate.len > 0);
    try std.testing.expect(parsed.value.tolerances.cost_relative > 0.0);
    try std.testing.expect(parsed.value.tolerances.dfs_absolute > 0.0);
    try std.testing.expect(parsed.value.tolerances.state_absolute > 0.0);
}

test "domino DOAS reference anchor captures vendor classic-DOAS outputs" {
    const raw = try readValidationFile("validation/golden/doas_domino_reference_anchor.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        DoasDominoReferenceAnchor,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expect(parsed.value.scenario.len > 0);
    try std.testing.expect(parsed.value.source_config.len > 0);
    try std.testing.expect(parsed.value.iterations > 0);
    try std.testing.expect(parsed.value.wavelength_amf_nm > 0.0);
    try std.testing.expect(parsed.value.total_slant_column_molec_cm2 > 0.0);
    try std.testing.expect(parsed.value.retrieved_trop_vertical_column_molec_cm2 > 0.0);
    try std.testing.expect(parsed.value.trop_amf > 0.0);
    try std.testing.expect(parsed.value.tolerances.slant_column_relative > 0.0);
    try std.testing.expect(parsed.value.tolerances.vertical_column_relative > 0.0);
    try std.testing.expect(parsed.value.tolerances.amf_absolute > 0.0);
}

// ── WP-01 config surface coverage assertions ────────────────────────────────
// These tests load the vendor config surface matrix and case catalog and assert
// that the WP-01 parity gate requirements are met: no unmapped or
// parsed_but_ignored entries, every exact/approximate entry has a zig_yaml_path,
// and all 18 required vendor sections are covered.

const VendorMatrixEntry = struct {
    section: []const u8,
    subsection: []const u8,
    key: []const u8,
    data_type: []const u8,
    sim_retr: []const u8,
    per_band: bool,
    per_interval: bool,
    per_gas: bool,
    example_configs: []const []const u8,
    zig_yaml_path: ?[]const u8,
    status: []const u8,
    runtime_consumer: ?[]const u8,
    notes: ?[]const u8,
};

const VendorCaseEntry = struct {
    config_file: []const u8,
    family: []const u8,
    retrieval_method: []const u8,
    primary_species: []const []const u8,
    spectral_region: []const u8,
    key_features: []const []const u8,
    validation_wp: []const []const u8,
    priority: u8,
    notes: ?[]const u8,
};

const VendorCaseCatalog = struct {
    schema_version: u32,
    description: []const u8,
    cases: []const VendorCaseEntry,
};

const required_vendor_sections = [_][]const u8{
    "GENERAL",
    "INSTRUMENT",
    "MUL_OFFSET",
    "STRAY_LIGHT",
    "RRS_RING",
    "REFERENCE_DATA",
    "GEOMETRY",
    "PRESSURE_TEMPERATURE",
    "ABSORBING_GAS",
    "SURFACE",
    "ATMOSPHERIC_INTERVALS",
    "CLOUD_AEROSOL_FRACTION",
    "CLOUD",
    "AEROSOL",
    "SUBCOLUMNS",
    "RETRIEVAL",
    "RADIATIVE_TRANSFER",
    "ADDITIONAL_OUTPUT",
};

fn readLargeValidationFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 16 * 1024 * 1024);
}

fn isVendorSectionIn(value: []const u8, set: []const []const u8) bool {
    for (set) |v| {
        if (std.mem.eql(u8, value, v)) return true;
    }
    return false;
}

test "wp01 vendor matrix has no unmapped or parsed_but_ignored entries" {
    // WP-01 gate: every vendor key must be classified as exact, approximate,
    // or unsupported. No unmapped or parsed_but_ignored statuses are allowed.
    const raw = try readLargeValidationFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const VendorMatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    var forbidden_count: usize = 0;
    for (parsed.value) |entry| {
        const is_forbidden = std.mem.eql(u8, entry.status, "unmapped") or
            std.mem.eql(u8, entry.status, "parsed_but_ignored");
        if (is_forbidden) {
            std.debug.print(
                "forbidden status '{s}' for {s}.{s}.{s}\n",
                .{ entry.status, entry.section, entry.subsection, entry.key },
            );
            forbidden_count += 1;
        }
    }
    if (forbidden_count > 0) {
        std.debug.print("found {d} forbidden entries\n", .{forbidden_count});
        return error.TestUnexpectedResult;
    }
}

test "wp01 vendor matrix exact and approximate entries have zig_yaml_path" {
    // Every vendor key with exact or approximate status must map to a canonical
    // YAML path so a typed config object can consume it.
    const raw = try readLargeValidationFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const VendorMatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    var missing_count: usize = 0;
    for (parsed.value) |entry| {
        const is_mapped = std.mem.eql(u8, entry.status, "exact") or
            std.mem.eql(u8, entry.status, "approximate");
        if (is_mapped and entry.zig_yaml_path == null) {
            std.debug.print(
                "exact/approximate entry missing zig_yaml_path: {s}.{s}.{s}\n",
                .{ entry.section, entry.subsection, entry.key },
            );
            missing_count += 1;
        }
    }
    if (missing_count > 0) {
        std.debug.print("found {d} entries missing zig_yaml_path\n", .{missing_count});
        return error.TestUnexpectedResult;
    }
}

test "wp01 vendor matrix covers all 18 required vendor sections" {
    const raw = try readLargeValidationFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const VendorMatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    for (&required_vendor_sections) |section| {
        var found = false;
        for (parsed.value) |entry| {
            if (std.mem.eql(u8, entry.section, section)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("required section '{s}' missing from vendor matrix\n", .{section});
            return error.TestUnexpectedResult;
        }
    }
}

test "wp01 case catalog covers golden config families referenced by WP-01" {
    // WP-01 requires one golden config-per-family test: O2A, O2A XsecLUT,
    // NO2 DOMINO, O3 profile, SWIR greenhouse-gas, and cloud/aerosol mixed.
    // Verify the case catalog has entries for these families.
    const raw = try readLargeValidationFile("tests/validation/assets/vendor_case_catalog.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        VendorCaseCatalog,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    // O2A (line_absorbing family, nir region, O2 species)
    var has_o2a = false;
    // O2A XsecLUT (lut family)
    var has_o2a_xseclut = false;
    // NO2 DOMINO (domino_no2 retrieval method)
    var has_no2_domino = false;
    // O3 profile (o3 species, cross_section family)
    var has_o3_profile = false;
    // SWIR greenhouse-gas (swir region or multi_band with CO2/CH4/H2O)
    var has_swir_ghg = false;
    // Cloud/aerosol mixed (cloud_fraction or similar key_features)
    var has_cloud_aerosol_mixed = false;

    for (parsed.value.cases) |case| {
        // O2A: line-absorbing O2 in NIR
        if (std.mem.eql(u8, case.family, "line_absorbing") and
            std.mem.eql(u8, case.spectral_region, "nir"))
        {
            for (case.primary_species) |species| {
                if (std.mem.eql(u8, species, "O2")) {
                    has_o2a = true;
                    break;
                }
            }
        }
        // O2A XsecLUT
        if (std.mem.eql(u8, case.family, "lut")) {
            has_o2a_xseclut = true;
        }
        // NO2 DOMINO
        if (std.mem.eql(u8, case.retrieval_method, "domino_no2")) {
            has_no2_domino = true;
        }
        // O3 profile
        for (case.primary_species) |species| {
            if (std.mem.eql(u8, species, "O3")) {
                has_o3_profile = true;
                break;
            }
        }
        // SWIR greenhouse-gas
        if (std.mem.eql(u8, case.spectral_region, "swir") or
            std.mem.eql(u8, case.spectral_region, "multi_band"))
        {
            for (case.primary_species) |species| {
                if (std.mem.eql(u8, species, "CO2") or
                    std.mem.eql(u8, species, "CH4") or
                    std.mem.eql(u8, species, "H2O") or
                    std.mem.eql(u8, species, "CO"))
                {
                    has_swir_ghg = true;
                    break;
                }
            }
        }
        // Cloud/aerosol mixed
        for (case.key_features) |feature| {
            if (std.mem.eql(u8, feature, "cloud_fraction_fit") or
                std.mem.eql(u8, feature, "cloud_pressure_fit") or
                std.mem.eql(u8, feature, "aerosol_layer_height"))
            {
                has_cloud_aerosol_mixed = true;
                break;
            }
        }
    }

    try std.testing.expect(has_o2a);
    try std.testing.expect(has_o2a_xseclut);
    try std.testing.expect(has_no2_domino);
    try std.testing.expect(has_o3_profile);
    try std.testing.expect(has_swir_ghg);
    try std.testing.expect(has_cloud_aerosol_mixed);
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
