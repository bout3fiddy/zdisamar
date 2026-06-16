const std = @import("std");
const internal = @import("internal");
const o2a_scene = @import("../support/o2a_scene.zig");

test "scene fixture consumes every setup control" {
    const scene = o2a_scene.reference();
    try internal.input.validate.sceneControls(scene);

    try std.testing.expectEqual(@as(usize, 701), scene.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(usize, 3), scene.atmosphere.intervals.len);
    try std.testing.expectEqual(@as(usize, 2), scene.atmosphere.fit_interval_index_1based);
    try std.testing.expectEqual(@as(usize, 3), scene.line_gas.isotopes_sim.len);
    try std.testing.expect(scene.geometry.pseudo_spherical);
    try std.testing.expectEqual(@as(f64, 0.2), scene.surface_albedo);
}

test "invalid controls are rejected instead of carried inertly" {
    var scene = o2a_scene.reference();
    scene.observation.high_resolution_step_nm = 0.0;
    try std.testing.expectError(error.InvalidControl, internal.input.validate.sceneControls(scene));

    scene = o2a_scene.reference();
    scene.cia.enabled = false;
    try std.testing.expectError(error.InvalidControl, internal.input.validate.sceneControls(scene));

    scene = o2a_scene.reference();
    scene.surface_albedo = std.math.nan(f64);
    try std.testing.expectError(error.InvalidControl, internal.input.validate.sceneControls(scene));

    scene = o2a_scene.reference();
    scene.aerosol.asymmetry_factor = 2.0;
    try std.testing.expectError(error.InvalidControl, internal.input.validate.sceneControls(scene));

    scene = o2a_scene.reference();
    scene.aerosol.interval_index_1based = 1;
    try std.testing.expectError(error.InvalidRequest, internal.input.validate.sceneControls(scene));

    scene = o2a_scene.reference();
    var intervals = [_]internal.input.scene_input.VerticalInterval{
        scene.atmosphere.intervals[0],
        scene.atmosphere.intervals[1],
        scene.atmosphere.intervals[2],
    };
    intervals[1].top_pressure_hpa = 501.0;
    scene.atmosphere.intervals = intervals[0..];
    try std.testing.expectError(error.InvalidControl, internal.input.validate.sceneControls(scene));

    scene = o2a_scene.reference();
    const invalid_isotopes = [_]u8{ 1, 0 };
    scene.line_gas.isotopes_sim = invalid_isotopes[0..];
    try std.testing.expectError(error.InvalidControl, internal.input.validate.sceneControls(scene));

    scene = o2a_scene.reference();
    scene.rtm.fourier_term_limit = 0;
    try std.testing.expectError(error.InvalidControl, internal.input.validate.sceneControls(scene));

    try std.testing.expectError(
        error.MissingField,
        internal.input.json.parseSceneJson(std.testing.allocator, "{}"),
    );
}

test "Python native scene JSON round-trips into typed controls" {
    const allocator = std.testing.allocator;

    const rendered = try o2a_scene.nativeJson(allocator);
    defer allocator.free(rendered);

    var parsed = try internal.input.json.parseSceneJson(allocator, rendered);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 701), parsed.scene.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(f64, 0.2), parsed.scene.surface_albedo);
    try std.testing.expectEqualStrings("o2a_disamar_reference_python", parsed.scene.id);
    try std.testing.expectEqualStrings(
        "data/reference_data/solar/o2a_solar_reference_753_778.csv",
        parsed.scene.observation.solar_reference.path,
    );
    try std.testing.expectEqual(
        internal.rtm.controls.PerformanceThresholds.o2a_default,
        parsed.scene.rtm.performance_thresholds,
    );
}

test "Python NaN altitude placeholders are normalized before typed parsing" {
    const allocator = std.testing.allocator;

    const rendered = try o2a_scene.nativeJson(allocator);
    defer allocator.free(rendered);
    const with_nan = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"index_1based\":1,",
        "\"index_1based\":1,\"top_altitude_km\":NaN,",
    );
    defer allocator.free(with_nan);

    var parsed = try internal.input.json.parseSceneJson(allocator, with_nan);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.scene.atmosphere.intervals.len);
    try std.testing.expectEqual(@as(f64, 0.3), parsed.scene.atmosphere.intervals[0].top_pressure_hpa);
}

test "Python native JSON rejects unknown controls while accepting null altitude placeholders" {
    const allocator = std.testing.allocator;

    const rendered = try o2a_scene.nativeJson(allocator);
    defer allocator.free(rendered);

    const unknown_threshold = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"performance_thresholds\":{",
        "\"performance_thresholds\":{\"typo\":1,",
    );
    defer allocator.free(unknown_threshold);

    try std.testing.expectError(
        error.UnknownField,
        internal.input.json.parseSceneJson(allocator, unknown_threshold),
    );

    const finite_altitude = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"index_1based\":1,",
        "\"index_1based\":1,\"top_altitude_km\":1.0,",
    );
    defer allocator.free(finite_altitude);

    try std.testing.expectError(
        error.UnsupportedJsonInput,
        internal.input.json.parseSceneJson(allocator, finite_altitude),
    );

    const pressure_variance = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"index_1based\":1,",
        "\"index_1based\":1,\"top_pressure_variance_hpa2\":1.0,",
    );
    defer allocator.free(pressure_variance);

    try std.testing.expectError(
        error.UnsupportedJsonInput,
        internal.input.json.parseSceneJson(allocator, pressure_variance),
    );
}

test "Python native JSON rejects unsupported route-control mutations" {
    const allocator = std.testing.allocator;

    const rendered = try o2a_scene.nativeJson(allocator);
    defer allocator.free(rendered);

    const cases = [_]struct {
        needle: []const u8,
        replacement: []const u8,
        expected_error: anyerror,
    }{
        .{
            .needle = "\"derivative_mode\":\"none\"",
            .replacement = "\"derivative_mode\":\"semi_analytical\"",
            .expected_error = error.UnsupportedJsonInput,
        },
        .{
            .needle = "\"sampling\":\"native\"",
            .replacement = "\"sampling\":\"convolved\"",
            .expected_error = error.UnsupportedJsonInput,
        },
        .{
            .needle = "\"n_streams\":20",
            .replacement = "\"n_streams\":8",
            .expected_error = error.UnsupportedJsonInput,
        },
        .{
            .needle = "\"high_resolution_step_nm\":0.01",
            .replacement = "\"high_resolution_step_nm\":0.0",
            .expected_error = error.InvalidControl,
        },
    };

    for (cases) |case| {
        const mutated = try std.mem.replaceOwned(
            u8,
            allocator,
            rendered,
            case.needle,
            case.replacement,
        );
        defer allocator.free(mutated);

        try std.testing.expectError(
            case.expected_error,
            internal.input.json.parseSceneJson(allocator, mutated),
        );
    }
}

test "Python native JSON byte fuzz corpus rejects malformed near-valid payloads" {
    const allocator = std.testing.allocator;

    const rendered = try o2a_scene.nativeJson(allocator);
    defer allocator.free(rendered);

    const corpus = [_][]const u8{
        "{",
        "[{}]",
        "{\"metadata\":{\"id\":\"x\"},\"plan\":{\"derivative_mode\":NaN}}",
        "{\"metadata\":{\"id\":\"x\"},\"rtm_controls\":{\"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\":true}}",
        "{\"metadata\":{\"id\":\"x\\uD800\"},\"plan\":{\"derivative_mode\":\"none\"}}",
        "\xff\xfe{\"scene_id\":\"x\"}",
    };
    for (corpus) |payload| {
        try expectParseRejected(allocator, payload);
    }

    const structural_bytes = [_]u8{ '{', '}', '[', ']', ':', ',', '"' };
    for (structural_bytes) |needle| {
        const index = std.mem.indexOfScalar(u8, rendered, needle) orelse continue;
        const mutated = try allocator.dupe(u8, rendered);
        defer allocator.free(mutated);
        mutated[index] = 0xff;

        try expectParseRejected(allocator, mutated);
    }
}

test "Python native fast RTM thresholds are consumed by solve config" {
    const allocator = std.testing.allocator;

    const rendered = try o2a_scene.nativeJson(allocator);
    defer allocator.free(rendered);
    const fast_threshold = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"fourier_order_cap\":null",
        "\"fourier_order_cap\":5",
    );
    defer allocator.free(fast_threshold);

    var parsed = try internal.input.json.parseSceneJson(allocator, fast_threshold);
    defer parsed.deinit();

    try std.testing.expectEqual(
        @as(?u16, 5),
        parsed.scene.rtm.performance_thresholds.fourier_order_cap,
    );
    try std.testing.expectEqual(
        @as(?u16, 5),
        internal.public.solveConfig(parsed.scene).controls.performance_thresholds.fourier_order_cap,
    );
}

test "RTM Fourier term limit is consumed by solve config" {
    var scene = o2a_scene.reference();
    scene.rtm.fourier_term_limit = 3;

    try internal.input.validate.sceneControls(scene);
    try std.testing.expectEqual(
        @as(?u16, 2),
        internal.public.solveConfig(scene).controls.performance_thresholds.fourier_order_cap,
    );

    scene.rtm.performance_thresholds.fourier_order_cap = 1;
    try std.testing.expectEqual(
        @as(?u16, 1),
        internal.public.solveConfig(scene).controls.performance_thresholds.fourier_order_cap,
    );
}

test "Python native measured wavelengths are consumed as sparse product axes" {
    const allocator = std.testing.allocator;

    const rendered = try o2a_scene.nativeJson(allocator);
    defer allocator.free(rendered);

    const sparse_count = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"sample_count\":701",
        "\"sample_count\":3",
    );
    defer allocator.free(sparse_count);
    const sparse_axis = try std.mem.replaceOwned(
        u8,
        allocator,
        sparse_count,
        "\"measured_wavelengths_nm\":[]",
        "\"measured_wavelengths_nm\":[755.0,765.5,776.0]",
    );
    defer allocator.free(sparse_axis);

    var parsed = try internal.input.json.parseSceneJson(allocator, sparse_axis);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.scene.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(usize, 3), parsed.scene.observation.measured_wavelengths_nm.len);
    try std.testing.expectApproxEqAbs(
        765.5,
        parsed.scene.observation.measured_wavelengths_nm[1],
        0.0,
    );

    const mismatched_axis = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"measured_wavelengths_nm\":[]",
        "\"measured_wavelengths_nm\":[760.0]",
    );
    defer allocator.free(mismatched_axis);

    try std.testing.expectError(
        error.InvalidControl,
        internal.input.json.parseSceneJson(allocator, mismatched_axis),
    );
}

test "Python native aerosol profile JSON validates explicit multi-layer rows" {
    const allocator = std.testing.allocator;

    const rendered = try o2a_scene.nativeJson(allocator);
    defer allocator.free(rendered);

    const valid_profile = try jsonWithAerosolProfile(allocator, rendered,
        \\[
        \\{"top_pressure_hpa":430.0,"bottom_pressure_hpa":510.0,"optical_depth":0.18,
        \\"single_scatter_albedo":0.96,"asymmetry_factor":0.72,"angstrom_exponent":0.4,
        \\"reference_wavelength_nm":550.0},
        \\{"top_pressure_hpa":760.0,"bottom_pressure_hpa":900.0,"optical_depth":0.24,
        \\"single_scatter_albedo":0.88,"asymmetry_factor":0.55,"angstrom_exponent":1.5,
        \\"reference_wavelength_nm":550.0}
        \\]
    );
    defer allocator.free(valid_profile);

    var parsed = try internal.input.json.parseSceneJson(allocator, valid_profile);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.scene.aerosol.profile.len);
    try std.testing.expectApproxEqAbs(0.18, parsed.scene.aerosol.profile[0].optical_depth, 0.0);
    try std.testing.expectApproxEqAbs(0.24, parsed.scene.aerosol.profile[1].optical_depth, 0.0);
}

test "Python native aerosol profile JSON rejects unsupported pressure and merge shapes" {
    const allocator = std.testing.allocator;

    const rendered = try o2a_scene.nativeJson(allocator);
    defer allocator.free(rendered);

    const off_grid_profile = try jsonWithAerosolProfile(allocator, rendered,
        \\[
        \\{"top_pressure_hpa":1000.0,"bottom_pressure_hpa":1100.0,"optical_depth":0.05},
        \\{"top_pressure_hpa":760.0,"bottom_pressure_hpa":900.0,"optical_depth":0.05}
        \\]
    );
    defer allocator.free(off_grid_profile);
    try std.testing.expectError(
        error.InvalidRequest,
        internal.input.json.parseSceneJson(allocator, off_grid_profile),
    );

    const spectral_merge_profile = try jsonWithAerosolProfile(allocator, rendered,
        \\[
        \\{"top_pressure_hpa":430.0,"bottom_pressure_hpa":460.0,"optical_depth":0.05,
        \\"angstrom_exponent":0.4},
        \\{"top_pressure_hpa":440.0,"bottom_pressure_hpa":470.0,"optical_depth":0.05,
        \\"angstrom_exponent":1.5}
        \\]
    );
    defer allocator.free(spectral_merge_profile);
    try std.testing.expectError(
        error.InvalidRequest,
        internal.input.json.parseSceneJson(allocator, spectral_merge_profile),
    );
}

fn jsonWithAerosolProfile(
    allocator: std.mem.Allocator,
    rendered: []const u8,
    profile_json: []const u8,
) ![]u8 {
    // jsonWithAerosolProfile ---------------------------------------------------------------------------------|
    // Replace the rendered empty profile array with an explicit profile without changing the Python schema.   |
    // --------------------------------------------------------------------------------------------------------|
    const replacement = try std.fmt.allocPrint(
        allocator,
        "\"profile\":{s}",
        .{profile_json},
    );
    defer allocator.free(replacement);

    return std.mem.replaceOwned(u8, allocator, rendered, "\"profile\":[]", replacement);
}

fn expectParseRejected(allocator: std.mem.Allocator, payload: []const u8) !void {
    // expectParseRejected ------------------------------------------------------------------------------------|
    // Bounded byte-corpus parser guard: malformed native JSON must reject without leaking owned parse state.  |
    // --------------------------------------------------------------------------------------------------------|
    if (internal.input.json.parseSceneJson(allocator, payload)) |parsed| {
        var owned = parsed;
        owned.deinit();
        return error.MalformedJsonAccepted;
    } else |_| {}
}
