const std = @import("std");
const support = @import("support/parity_assets_support.zig");

test "golden provenance fixture defines default release evidence keys" {
    const raw = try support.readValidationFile("validation/golden/result_provenance_golden.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        support.ProvenanceGolden,
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
    const raw = try support.readValidationFile("validation/golden/oe_reference_anchor.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        support.OeReferenceAnchor,
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
    const raw = try support.readValidationFile("validation/golden/doas_domino_reference_anchor.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        support.DoasDominoReferenceAnchor,
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

test "release readiness matrix ties commands packages and evidence together" {
    const raw = try support.readValidationFile("validation/release/release_readiness.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        support.ReleaseReadiness,
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
