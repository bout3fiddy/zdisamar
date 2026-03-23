const std = @import("std");

pub const ParityTolerances = struct {
    absolute: f64,
    relative: f64,
};

pub const RuntimeProfile = struct {
    observation_regime: []const u8,
    solver_mode: []const u8,
    derivative_mode: []const u8,
    spectral_samples: u32,
};

pub const ParityCase = struct {
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

pub const ParityMatrix = struct {
    version: u32,
    upstream: []const u8,
    parity_level: []const u8,
    cases: []const ParityCase,
};

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

pub const PluginCase = struct {
    id: []const u8,
    lane: []const u8,
    capability_slot: []const u8,
    status: []const u8,
};

pub const PluginValidationMatrix = struct {
    version: u32,
    cases: []const PluginCase,
};

pub const ReleasePackage = struct {
    name: []const u8,
    version: []const u8,
};

pub const ReleaseReadiness = struct {
    version: u32,
    required_commands: []const []const u8,
    required_packages: []const ReleasePackage,
    required_plugin_versions: []const []const u8,
    required_artifacts: []const []const u8,
};

pub const ProvenanceGolden = struct {
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

pub const OeReferenceAnchor = struct {
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

pub const DoasDominoReferenceAnchor = struct {
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

pub const BundleAsset = struct {
    id: []const u8,
    path: []const u8,
    format: []const u8,
    sha256: []const u8,
    columns: []const []const u8,
};

pub const BundleUpstream = struct {
    vendor_root: []const u8,
    source_paths: []const []const u8,
    reference_snapshot: []const u8,
};

pub const BundleManifest = struct {
    version: u32,
    bundle_id: []const u8,
    owner_package: []const u8,
    description: []const u8,
    upstream: BundleUpstream,
    assets: []const BundleAsset,
};

pub const VendorImport = struct {
    bundle_manifest: []const u8,
    local_asset: []const u8,
    upstream_candidates: []const []const u8,
};

pub const VendorImportRegistry = struct {
    version: u32,
    upstream_root: []const u8,
    imports: []const VendorImport,
};

pub const VendorMatrixEntry = struct {
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

pub const VendorCaseEntry = struct {
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

pub const VendorCaseCatalog = struct {
    schema_version: u32,
    description: []const u8,
    cases: []const VendorCaseEntry,
};

pub const required_vendor_sections = [_][]const u8{
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

pub fn readValidationFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 1024 * 1024);
}

pub fn readLargeValidationFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 16 * 1024 * 1024);
}

pub fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn assertAssetDigest(path: []const u8, expected_sha: []const u8) !void {
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

pub fn isVendorSectionIn(value: []const u8, set: []const []const u8) bool {
    for (set) |v| {
        if (std.mem.eql(u8, value, v)) return true;
    }
    return false;
}
