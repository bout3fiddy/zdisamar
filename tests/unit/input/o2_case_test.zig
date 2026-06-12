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

test "unsupported JSON route controls fail at the input boundary" {
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

    try std.testing.expectError(
        error.UnsupportedJsonInput,
        internal.input.json.parseO2CaseJson(allocator, fast_threshold),
    );
}
