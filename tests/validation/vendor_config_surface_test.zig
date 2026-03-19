const std = @import("std");

// ── JSON structs matching vendor_config_surface_matrix.json ──────────────────

const MatrixEntry = struct {
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

// ── JSON structs matching vendor_case_catalog.json ───────────────────────────

const CaseEntry = struct {
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

const CaseCatalog = struct {
    schema_version: u32,
    description: []const u8,
    cases: []const CaseEntry,
};

// ── Valid value sets ─────────────────────────────────────────────────────────

const valid_statuses = [_][]const u8{
    "exact",
    "approximate",
    "unsupported",
};

const valid_data_types = [_][]const u8{
    "int",
    "real",
    "bool_int",
    "string",
    "real_array",
    "int_array",
    "real_pairs",
    "real_triples",
};

const valid_sim_retr = [_][]const u8{
    "sim",
    "retr",
    "both",
    "na",
};

const valid_sections = [_][]const u8{
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

const valid_families = [_][]const u8{
    "line_absorbing",
    "cross_section",
    "mixed",
    "operational",
    "lut",
};

const valid_retrieval_methods = [_][]const u8{
    "oe",
    "dismas",
    "doas",
    "classic_doas",
    "domino_no2",
    "simulation_only",
};

const valid_spectral_regions = [_][]const u8{
    "uv",
    "vis",
    "nir",
    "swir",
    "multi_band",
};

fn isOneOf(value: []const u8, valid: []const []const u8) bool {
    for (valid) |v| {
        if (std.mem.eql(u8, value, v)) return true;
    }
    return false;
}

fn readAssetFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 16 * 1024 * 1024);
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "vendor config surface matrix is loadable and structurally valid" {
    const raw = try readAssetFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const MatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    // Must have substantial coverage — the vendor config has hundreds of keys.
    try std.testing.expect(parsed.value.len >= 200);
}

test "every vendor matrix entry has a valid status classification" {
    const raw = try readAssetFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const MatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    for (parsed.value) |entry| {
        if (!isOneOf(entry.status, &valid_statuses)) {
            std.debug.print(
                "invalid status '{s}' for {s}.{s}.{s}\n",
                .{ entry.status, entry.section, entry.subsection, entry.key },
            );
            return error.TestUnexpectedResult;
        }
    }
}

test "every vendor matrix entry has a valid section name" {
    const raw = try readAssetFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const MatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    for (parsed.value) |entry| {
        if (!isOneOf(entry.section, &valid_sections)) {
            std.debug.print("invalid section '{s}'\n", .{entry.section});
            return error.TestUnexpectedResult;
        }
    }
}

test "every vendor matrix entry has valid data type and sim_retr" {
    const raw = try readAssetFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const MatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    for (parsed.value) |entry| {
        if (!isOneOf(entry.data_type, &valid_data_types)) {
            std.debug.print(
                "invalid data_type '{s}' for {s}.{s}.{s}\n",
                .{ entry.data_type, entry.section, entry.subsection, entry.key },
            );
            return error.TestUnexpectedResult;
        }
        if (!isOneOf(entry.sim_retr, &valid_sim_retr)) {
            std.debug.print(
                "invalid sim_retr '{s}' for {s}.{s}.{s}\n",
                .{ entry.sim_retr, entry.section, entry.subsection, entry.key },
            );
            return error.TestUnexpectedResult;
        }
    }
}

test "exact and approximate entries have a zig_yaml_path" {
    const raw = try readAssetFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const MatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    for (parsed.value) |entry| {
        if (std.mem.eql(u8, entry.status, "exact") or
            std.mem.eql(u8, entry.status, "approximate"))
        {
            if (entry.zig_yaml_path == null) {
                std.debug.print(
                    "exact/approximate entry missing zig_yaml_path: {s}.{s}.{s}\n",
                    .{ entry.section, entry.subsection, entry.key },
                );
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "all vendor sections are represented in the matrix" {
    const raw = try readAssetFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const MatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    for (&valid_sections) |section| {
        var found = false;
        for (parsed.value) |entry| {
            if (std.mem.eql(u8, entry.section, section)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("section '{s}' missing from vendor config matrix\n", .{section});
            return error.TestUnexpectedResult;
        }
    }
}

test "no parsed_but_ignored entries remain (parity gate)" {
    const raw = try readAssetFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const MatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    var ignored_count: usize = 0;
    for (parsed.value) |entry| {
        if (std.mem.eql(u8, entry.status, "parsed_but_ignored")) {
            ignored_count += 1;
        }
    }

    // WP-01 gate: parsed_but_ignored is forbidden.
    // Every vendor key must be classified as exact, approximate, or unsupported.
    if (ignored_count > 0) {
        std.debug.print(
            "parsed_but_ignored count ({d}) must be zero\n",
            .{ignored_count},
        );
        return error.TestUnexpectedResult;
    }
}

test "vendor case catalog is loadable and structurally valid" {
    const raw = try readAssetFile("tests/validation/assets/vendor_case_catalog.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        CaseCatalog,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.schema_version);
    try std.testing.expect(parsed.value.cases.len >= 20);
}

test "every case catalog entry has valid family and retrieval method" {
    const raw = try readAssetFile("tests/validation/assets/vendor_case_catalog.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        CaseCatalog,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    for (parsed.value.cases) |case| {
        if (!isOneOf(case.family, &valid_families)) {
            std.debug.print("invalid family '{s}' for {s}\n", .{ case.family, case.config_file });
            return error.TestUnexpectedResult;
        }
        if (!isOneOf(case.retrieval_method, &valid_retrieval_methods)) {
            std.debug.print("invalid retrieval_method '{s}' for {s}\n", .{ case.retrieval_method, case.config_file });
            return error.TestUnexpectedResult;
        }
        if (!isOneOf(case.spectral_region, &valid_spectral_regions)) {
            std.debug.print("invalid spectral_region '{s}' for {s}\n", .{ case.spectral_region, case.config_file });
            return error.TestUnexpectedResult;
        }
        try std.testing.expect(case.primary_species.len > 0);
        try std.testing.expect(case.validation_wp.len > 0);
        try std.testing.expect(case.priority >= 1 and case.priority <= 3);
    }
}

test "case catalog covers all required validation families" {
    const raw = try readAssetFile("tests/validation/assets/vendor_case_catalog.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        CaseCatalog,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    // Must cover all five families.
    for (&valid_families) |family| {
        var found = false;
        for (parsed.value.cases) |case| {
            if (std.mem.eql(u8, case.family, family)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("family '{s}' missing from case catalog\n", .{family});
            return error.TestUnexpectedResult;
        }
    }
}

test "case catalog has at least one priority-1 case per retrieval method" {
    const raw = try readAssetFile("tests/validation/assets/vendor_case_catalog.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        CaseCatalog,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const required_methods = [_][]const u8{
        "oe",
        "simulation_only",
        "domino_no2",
    };

    for (&required_methods) |method| {
        var found = false;
        for (parsed.value.cases) |case| {
            if (std.mem.eql(u8, case.retrieval_method, method) and case.priority == 1) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("no priority-1 case for retrieval method '{s}'\n", .{method});
            return error.TestUnexpectedResult;
        }
    }
}
