const std = @import("std");
const support = @import("support/parity_assets_support.zig");

test "parity matrix defines executable upstream contract and retrieval-check cases" {
    const raw = try support.readValidationFile("validation/compatibility/parity_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        support.ParityMatrix,
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
    const raw = try support.readValidationFile("validation/perf/perf_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        support.PerfMatrix,
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
    const raw = try support.readValidationFile("validation/plugin_tests/plugin_validation_matrix.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        support.PluginValidationMatrix,
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
        const raw = try support.readValidationFile(manifest_path);
        defer std.testing.allocator.free(raw);

        const parsed = try std.json.parseFromSlice(
            support.BundleManifest,
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
            try support.assertAssetDigest(asset.path, asset.sha256);
        }
    }
}

test "vendor import registry maps local bundles to upstream references" {
    const raw = try support.readValidationFile("validation/compatibility/vendor_import_registry.json");
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        support.VendorImportRegistry,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expect(parsed.value.upstream_root.len > 0);
    try std.testing.expect(parsed.value.imports.len > 0);

    const has_upstream_root = support.pathExists(parsed.value.upstream_root);
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
                if (support.pathExists(joined)) {
                    saw_upstream_candidate = true;
                    break;
                }
            }
            try std.testing.expect(saw_upstream_candidate);
        }
    }
}
