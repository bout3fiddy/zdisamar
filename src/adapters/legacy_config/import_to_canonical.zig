const std = @import("std");
const zdisamar = @import("zdisamar");
const Importer = @import("config_in_importer.zig");
const SchemaMapper = @import("schema_mapper.zig");

const PreparedRun = SchemaMapper.PreparedRun;
const Allocator = std.mem.Allocator;

pub const ImportWarning = struct {
    message: []const u8,
};

pub const ImportedDocument = struct {
    yaml: []u8,
    warnings: []const ImportWarning,

    pub fn deinit(self: *ImportedDocument, allocator: Allocator) void {
        for (self.warnings) |warning| allocator.free(warning.message);
        if (self.warnings.len != 0) allocator.free(self.warnings);
        allocator.free(self.yaml);
        self.* = undefined;
    }
};

pub fn importFile(allocator: Allocator, path: []const u8) !ImportedDocument {
    const source_path = try std.fs.cwd().realpathAlloc(allocator, path);
    defer allocator.free(source_path);

    const contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(contents);

    return importSource(allocator, source_path, contents);
}

pub fn importSource(allocator: Allocator, source_path: []const u8, contents: []const u8) !ImportedDocument {
    var prepared = try Importer.parse(allocator, contents);
    defer prepared.deinit(allocator);
    return renderPrepared(allocator, source_path, prepared);
}

fn renderPrepared(allocator: Allocator, source_path: []const u8, prepared: PreparedRun) !ImportedDocument {
    var warnings = std.ArrayList(ImportWarning).empty;
    errdefer freeWarnings(allocator, warnings.items);

    try appendWarning(
        allocator,
        &warnings,
        "legacy import preserves only the flat Config.in adapter subset implemented in zdisamar; unmapped historical sections still need manual review",
    );

    if (prepared.plan_template.providers.retrieval_algorithm) |provider| {
        if (provider.len != 0) {
            try appendWarning(
                allocator,
                &warnings,
                "legacy retrieval provider is preserved as a plan hint only because the flat adapter subset has no inverse-problem structure to import",
            );
        }
    }
    if (prepared.scene.atmosphere.has_clouds) {
        try appendWarning(
            allocator,
            &warnings,
            "legacy has_clouds was approximated with a placeholder cloud block and zero optical thickness because the flat adapter subset does not carry cloud microphysics",
        );
    }
    if (prepared.scene.atmosphere.has_aerosols) {
        try appendWarning(
            allocator,
            &warnings,
            "legacy has_aerosols was approximated with a placeholder aerosol block and zero optical depth because the flat adapter subset does not carry aerosol microphysics",
        );
    }
    if (prepared.scene.spectral_grid.sample_count <= 1 and prepared.scene.spectral_grid.start_nm != prepared.scene.spectral_grid.end_nm) {
        try appendWarning(
            allocator,
            &warnings,
            "legacy single-sample band inference could not preserve a non-zero span exactly; review the imported band step",
        );
    }

    var yaml = std.ArrayList(u8).empty;
    errdefer yaml.deinit(allocator);
    const writer = yaml.writer(allocator);

    try writer.print(
        "# Imported from legacy Config.in subset.\n# Source: {s}\n",
        .{source_path},
    );
    try writer.writeAll("schema_version: 1\n\nmetadata:\n");
    try appendStringField(writer, 1, "id", effectiveMetadataId(prepared));
    try appendStringField(writer, 1, "workspace", prepared.workspace_label);
    try appendStringField(writer, 1, "description", "Imported from the flat legacy Config.in adapter subset");

    try writer.writeAll("\ntemplates:\n");
    try appendQuotedKey(writer, 1, "legacy_import");
    try writer.writeAll(":\n");
    try writer.writeAll("    plan:\n");
    try appendStringField(writer, 3, "model_family", prepared.plan_template.model_family);
    try writer.writeAll("      transport:\n");
    try appendStringField(writer, 4, "solver", canonicalTransportSolver(prepared.plan_template.providers.transport_solver));
    if (transportProviderHint(prepared.plan_template.providers.transport_solver)) |provider| {
        try appendStringField(writer, 4, "provider", provider);
    }
    try writer.writeAll("      execution:\n");
    try appendStringField(writer, 4, "solver_mode", @tagName(prepared.plan_template.solver_mode));
    try appendStringField(writer, 4, "derivative_mode", @tagName(prepared.plan_template.scene_blueprint.derivative_mode));
    if (prepared.plan_template.providers.retrieval_algorithm) |provider| {
        if (provider.len != 0) {
            try writer.writeAll("      providers:\n");
            try appendStringField(writer, 4, "retrieval_algorithm", provider);
        }
    }

    try writer.writeAll("    scene:\n");
    try writer.writeAll("      geometry:\n");
    try appendStringField(writer, 4, "model", @tagName(prepared.scene.geometry.model));
    try appendFloatField(writer, 4, "solar_zenith_deg", prepared.scene.geometry.solar_zenith_deg);
    try appendFloatField(writer, 4, "viewing_zenith_deg", prepared.scene.geometry.viewing_zenith_deg);
    try appendFloatField(writer, 4, "relative_azimuth_deg", prepared.scene.geometry.relative_azimuth_deg);
    try writer.writeAll("      atmosphere:\n");
    try writer.writeAll("        layering:\n");
    try appendU32Field(writer, 5, "layer_count", prepared.scene.atmosphere.layer_count);
    try writer.writeAll("      bands:\n");
    try appendQuotedKey(writer, 4, "legacy_band");
    try writer.writeAll(":\n");
    try appendFloatField(writer, 5, "start_nm", prepared.scene.spectral_grid.start_nm);
    try appendFloatField(writer, 5, "end_nm", prepared.scene.spectral_grid.end_nm);
    try appendFloatField(writer, 5, "step_nm", spectralStep(prepared));
    try writer.writeAll("      absorbers: {}\n");
    try writer.writeAll("      surface:\n");
    try appendStringField(writer, 4, "model", prepared.scene.surface.kind.label());
    try appendFloatField(writer, 4, "albedo", prepared.scene.surface.albedo);
    try writer.writeAll("      measurement_model:\n");
    try appendStringField(writer, 4, "regime", @tagName(prepared.scene.observation_model.regime));
    try writer.writeAll("        instrument:\n");
    try appendStringField(writer, 5, "name", prepared.scene.observation_model.instrument);
    try writer.writeAll("        sampling:\n");
    try appendStringField(writer, 5, "mode", prepared.scene.observation_model.sampling.label());
    try writer.writeAll("        noise:\n");
    try appendStringField(writer, 5, "model", prepared.scene.observation_model.noise_model.label());

    if (prepared.scene.atmosphere.has_clouds) {
        try writer.writeAll("      clouds:\n");
        try appendQuotedKey(writer, 4, "legacy_cloud");
        try writer.writeAll(":\n");
        try appendStringField(writer, 5, "model", "legacy_binary_cloud");
        try appendFloatField(writer, 5, "optical_thickness", 0.0);
    }
    if (prepared.scene.atmosphere.has_aerosols) {
        try writer.writeAll("      aerosols:\n");
        try appendQuotedKey(writer, 4, "legacy_aerosol");
        try writer.writeAll(":\n");
        try appendStringField(writer, 5, "model", "legacy_binary_aerosol");
        try appendFloatField(writer, 5, "optical_depth_550_nm", 0.0);
    }

    try writer.writeAll("\nexperiment:\n  simulation:\n    from: legacy_import\n    scene:\n");
    try appendStringField(writer, 3, "id", prepared.scene.id);
    if (prepared.requested_products.items.len == 0) {
        try writer.writeAll("    products: {}\n");
    } else {
        try writer.writeAll("    products:\n");
        try appendProducts(allocator, writer, prepared, &warnings);
    }
    try writer.writeAll("    diagnostics:\n");
    try appendBoolField(writer, 3, "provenance", prepared.diagnostics.provenance);
    try appendBoolField(writer, 3, "jacobians", prepared.diagnostics.jacobians);

    try writer.writeAll("\noutputs: []\n\nvalidation:\n");
    try appendBoolField(writer, 1, "strict_unknown_fields", true);
    try appendBoolField(writer, 1, "require_resolved_stage_references", true);

    return .{
        .yaml = try yaml.toOwnedSlice(allocator),
        .warnings = try warnings.toOwnedSlice(allocator),
    };
}

fn appendProducts(
    allocator: Allocator,
    writer: anytype,
    prepared: PreparedRun,
    warnings: *std.ArrayList(ImportWarning),
) !void {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var duplicate_warned = false;
    for (prepared.requested_products.items) |name| {
        const gop = try seen.getOrPut(name);
        if (gop.found_existing) {
            if (!duplicate_warned) {
                duplicate_warned = true;
                try appendWarning(
                    allocator,
                    warnings,
                    "duplicate legacy requested_products entries were deduplicated for canonical product registration",
                );
            }
            continue;
        }

        try appendQuotedKey(writer, 3, name);
        try writer.writeAll(":\n");
        switch (legacyProductKind(name)) {
            .measurement_space => {
                try appendStringField(writer, 4, "kind", "measurement_space");
                try appendStringField(writer, 4, "observable", name);
            },
            .result => {
                if (!isGenericResultName(name)) {
                    const message = try std.fmt.allocPrint(
                        allocator,
                        "legacy requested product \"{s}\" has no typed canonical product mapping and was imported as kind=result for traceability only",
                        .{name},
                    );
                    defer allocator.free(message);
                    try appendWarning(allocator, warnings, message);
                }
                try appendStringField(writer, 4, "kind", "result");
            },
        }
    }
}

fn appendWarning(allocator: Allocator, warnings: *std.ArrayList(ImportWarning), message: []const u8) !void {
    try warnings.append(allocator, .{
        .message = try allocator.dupe(u8, message),
    });
}

fn freeWarnings(allocator: Allocator, warnings: []const ImportWarning) void {
    for (warnings) |warning| allocator.free(warning.message);
}

fn appendQuotedKey(writer: anytype, indent: usize, key: []const u8) !void {
    try writeIndent(writer, indent);
    try writer.print("{s}", .{key});
}

fn appendStringField(writer: anytype, indent: usize, key: []const u8, value: []const u8) !void {
    try writeIndent(writer, indent);
    try writer.print("{s}: ", .{key});
    try appendQuotedScalar(writer, value);
    try writer.writeByte('\n');
}

fn appendBoolField(writer: anytype, indent: usize, key: []const u8, value: bool) !void {
    try writeIndent(writer, indent);
    try writer.print("{s}: {s}\n", .{ key, if (value) "true" else "false" });
}

fn appendU32Field(writer: anytype, indent: usize, key: []const u8, value: u32) !void {
    try writeIndent(writer, indent);
    try writer.print("{s}: {d}\n", .{ key, value });
}

fn appendFloatField(writer: anytype, indent: usize, key: []const u8, value: f64) !void {
    try writeIndent(writer, indent);
    try writer.print("{s}: {d:.6}\n", .{ key, value });
}

fn appendQuotedScalar(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| switch (byte) {
        '\\' => try writer.writeAll("\\\\"),
        '"' => try writer.writeAll("\\\""),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

fn writeIndent(writer: anytype, indent: usize) !void {
    for (0..indent * 2) |_| try writer.writeByte(' ');
}

fn effectiveMetadataId(prepared: PreparedRun) []const u8 {
    if (prepared.scene.id.len != 0) return prepared.scene.id;
    if (prepared.workspace_label.len != 0) return prepared.workspace_label;
    return "legacy-import";
}

fn spectralStep(prepared: PreparedRun) f64 {
    if (prepared.scene.spectral_grid.sample_count <= 1) {
        if (prepared.scene.spectral_grid.start_nm == prepared.scene.spectral_grid.end_nm) return 1.0;
        return prepared.scene.spectral_grid.end_nm - prepared.scene.spectral_grid.start_nm;
    }
    return (prepared.scene.spectral_grid.end_nm - prepared.scene.spectral_grid.start_nm) /
        @as(f64, @floatFromInt(prepared.scene.spectral_grid.sample_count - 1));
}

fn canonicalTransportSolver(raw: []const u8) []const u8 {
    if (raw.len == 0) return "dispatcher";
    if (std.mem.endsWith(u8, raw, "dispatcher")) return "dispatcher";
    return raw;
}

fn transportProviderHint(raw: []const u8) ?[]const u8 {
    if (raw.len == 0 or std.mem.endsWith(u8, raw, "dispatcher")) return null;
    return raw;
}

const ImportedProductKind = enum {
    measurement_space,
    result,
};

fn legacyProductKind(name: []const u8) ImportedProductKind {
    if (std.mem.eql(u8, name, "radiance") or
        std.mem.eql(u8, name, "reflectance") or
        std.mem.eql(u8, name, "irradiance") or
        std.mem.eql(u8, name, "transmittance"))
    {
        return .measurement_space;
    }
    return .result;
}

fn isGenericResultName(name: []const u8) bool {
    return std.mem.eql(u8, name, "result") or
        std.mem.eql(u8, name, "state_vector") or
        std.mem.eql(u8, name, "diagnostics");
}

test "legacy import renders canonical yaml that resolves and preserves typed fields" {
    const legacy_source =
        \\workspace = import-smoke
        \\model_family = disamar_standard
        \\transport = transport.dispatcher
        \\retrieval = none
        \\solver_mode = polarized
        \\scene_id = s5p-no2
        \\spectral_start_nm = 405.0
        \\spectral_end_nm = 465.0
        \\spectral_samples = 121
        \\atmosphere_layers = 48
        \\has_clouds = yes
        \\has_aerosols = no
        \\solar_zenith_deg = 32.5
        \\viewing_zenith_deg = 9.0
        \\relative_azimuth_deg = 145.0
        \\instrument = tropomi
        \\sampling = native
        \\noise_model = shot_noise
        \\derivative_mode = semi_analytical
        \\requested_products = radiance, slant_column
        \\diagnostics.provenance = true
        \\diagnostics.jacobians = true
    ;

    var imported = try importSource(std.testing.allocator, "legacy_config.in", legacy_source);
    defer imported.deinit(std.testing.allocator);

    var document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        "imported.yaml",
        ".",
        imported.yaml,
    );
    defer document.deinit();

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    try std.testing.expectEqualStrings("import-smoke", resolved.metadata.workspace);
    try std.testing.expect(resolved.simulation != null);
    try std.testing.expectEqualStrings("s5p-no2", resolved.simulation.?.scene.id);
    try std.testing.expectEqualStrings("disamar_standard", resolved.simulation.?.plan.model_family);
    try std.testing.expectEqual(@as(zdisamar.SolverMode, .polarized), resolved.simulation.?.plan.solver_mode);
    try std.testing.expectEqual(@as(zdisamar.DerivativeMode, .semi_analytical), resolved.simulation.?.plan.scene_blueprint.derivative_mode);
    try std.testing.expectEqual(@as(u32, 121), resolved.simulation.?.scene.spectral_grid.sample_count);
    try std.testing.expect(resolved.simulation.?.scene.atmosphere.has_clouds);
    try std.testing.expectEqual(@as(usize, 2), resolved.simulation.?.products.len);
    try std.testing.expectEqualStrings("radiance", resolved.simulation.?.products[0].name);
    try std.testing.expectEqualStrings("slant_column", resolved.simulation.?.products[1].name);
    try std.testing.expectEqualStrings("measurement_space", @tagName(resolved.simulation.?.products[0].kind));
    try std.testing.expectEqualStrings("result", @tagName(resolved.simulation.?.products[1].kind));
    try std.testing.expect(imported.warnings.len >= 2);
}
