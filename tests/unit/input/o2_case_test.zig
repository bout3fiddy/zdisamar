const std = @import("std");
const internal = @import("internal");

test "default O2 case consumes every WP2 setup control" {
    const case = internal.input.defaults.referenceCase();
    try internal.input.validate.o2Case(case);

    try std.testing.expectEqual(@as(usize, 701), case.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(usize, 3), case.atmosphere.intervals.len);
    try std.testing.expectEqual(@as(usize, 2), case.atmosphere.fit_interval_index_1based);
    try std.testing.expectEqual(@as(usize, 3), case.line_gas.isotopes_sim.len);
    try std.testing.expect(case.geometry.pseudo_spherical);
    try std.testing.expectEqual(@as(f64, 0.2), case.surface_albedo);
}

test "invalid controls are rejected instead of carried inertly" {
    var case = internal.input.defaults.referenceCase();
    case.observation.high_resolution_step_nm = 0.0;
    try std.testing.expectError(error.InvalidControl, internal.input.validate.o2Case(case));

    case = internal.input.defaults.referenceCase();
    case.cia.enabled = false;
    try std.testing.expectError(error.InvalidControl, internal.input.validate.o2Case(case));

    try std.testing.expectError(
        error.MissingField,
        internal.input.json.parseO2CaseJson(std.testing.allocator, "{}"),
    );
}

test "Python native O2 case JSON round-trips into typed controls" {
    const allocator = std.testing.allocator;

    const rendered = try internal.input.json.renderDefaultO2CaseJson(allocator);
    defer allocator.free(rendered);

    var parsed = try internal.input.json.parseO2CaseJson(allocator, rendered);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 701), parsed.case.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(f64, 0.2), parsed.case.surface_albedo);
    try std.testing.expectEqualStrings("o2a_disamar_reference_python", parsed.case.id);
    try std.testing.expectEqualStrings(
        "data/reference_data/solar/o2a_solar_reference_753_778.csv",
        parsed.case.observation.solar_reference.path,
    );
    try std.testing.expectEqual(
        internal.transport.controls.PerformanceThresholds.o2a_default,
        parsed.case.rtm.performance_thresholds,
    );
}

test "Python NaN altitude placeholders are normalized before typed parsing" {
    const allocator = std.testing.allocator;

    const rendered = try internal.input.json.renderDefaultO2CaseJson(allocator);
    defer allocator.free(rendered);
    const with_nan = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"index_1based\":1,",
        "\"index_1based\":1,\"top_altitude_km\":NaN,",
    );
    defer allocator.free(with_nan);

    var parsed = try internal.input.json.parseO2CaseJson(allocator, with_nan);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.case.atmosphere.intervals.len);
    try std.testing.expectEqual(@as(f64, 0.3), parsed.case.atmosphere.intervals[0].top_pressure_hpa);
}

test "Python native fast RTM thresholds are consumed by solve config" {
    const allocator = std.testing.allocator;

    const rendered = try internal.input.json.renderDefaultO2CaseJson(allocator);
    defer allocator.free(rendered);
    const fast_threshold = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"fourier_order_cap\":null",
        "\"fourier_order_cap\":5",
    );
    defer allocator.free(fast_threshold);

    var parsed = try internal.input.json.parseO2CaseJson(allocator, fast_threshold);
    defer parsed.deinit();

    try std.testing.expectEqual(
        @as(?u16, 5),
        parsed.case.rtm.performance_thresholds.fourier_order_cap,
    );
    try std.testing.expectEqual(
        @as(?u16, 5),
        internal.public.o2aSolveConfig(parsed.case).controls.performance_thresholds.fourier_order_cap,
    );
}

test "unsupported JSON route controls fail at the input boundary" {
    const allocator = std.testing.allocator;

    const rendered = try internal.input.json.renderDefaultO2CaseJson(allocator);
    defer allocator.free(rendered);
    const measured_wavelengths = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"measured_wavelengths_nm\":[]",
        "\"measured_wavelengths_nm\":[760.0]",
    );
    defer allocator.free(measured_wavelengths);

    try std.testing.expectError(
        error.UnsupportedJsonInput,
        internal.input.json.parseO2CaseJson(allocator, measured_wavelengths),
    );
}

test "Python native aerosol profile JSON validates explicit multi-layer rows" {
    const allocator = std.testing.allocator;

    const rendered = try internal.input.json.renderDefaultO2CaseJson(allocator);
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

    var parsed = try internal.input.json.parseO2CaseJson(allocator, valid_profile);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.case.aerosol.profile.len);
    try std.testing.expectApproxEqAbs(0.18, parsed.case.aerosol.profile[0].optical_depth, 0.0);
    try std.testing.expectApproxEqAbs(0.24, parsed.case.aerosol.profile[1].optical_depth, 0.0);
}

test "Python native aerosol profile JSON rejects unsupported pressure and merge shapes" {
    const allocator = std.testing.allocator;

    const rendered = try internal.input.json.renderDefaultO2CaseJson(allocator);
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
        internal.input.json.parseO2CaseJson(allocator, off_grid_profile),
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
        internal.input.json.parseO2CaseJson(allocator, spectral_merge_profile),
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
