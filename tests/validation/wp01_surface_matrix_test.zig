const std = @import("std");
const support = @import("support/parity_assets_support.zig");

test "wp01 vendor matrix has no unmapped or parsed_but_ignored entries" {
    const raw = try support.readLargeValidationFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const support.VendorMatrixEntry,
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
    const raw = try support.readLargeValidationFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const support.VendorMatrixEntry,
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
    const raw = try support.readLargeValidationFile("tests/validation/assets/vendor_config_surface_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        []const support.VendorMatrixEntry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    for (&support.required_vendor_sections) |section| {
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
    const raw = try support.readLargeValidationFile("tests/validation/assets/vendor_case_catalog.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        support.VendorCaseCatalog,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    var has_o2a = false;
    var has_o2a_xseclut = false;
    var has_no2_domino = false;
    var has_o3_profile = false;
    var has_swir_ghg = false;
    var has_cloud_aerosol_mixed = false;

    for (parsed.value.cases) |case| {
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
        if (std.mem.eql(u8, case.family, "lut")) {
            has_o2a_xseclut = true;
        }
        if (std.mem.eql(u8, case.retrieval_method, "domino_no2")) {
            has_no2_domino = true;
        }
        for (case.primary_species) |species| {
            if (std.mem.eql(u8, species, "O3")) {
                has_o3_profile = true;
                break;
            }
        }
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
