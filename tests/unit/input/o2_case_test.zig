const std = @import("std");
const internal = @import("internal");

test "default O2 case consumes every WP2 setup control" {
    const case = internal.input.defaults.referenceCase();
    try internal.input.validate.referenceCase(case);

    try std.testing.expectEqual(@as(usize, 701), case.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(usize, 3), case.atmosphere.intervals.len);
    try std.testing.expectEqual(@as(usize, 2), case.atmosphere.fit_interval_index_1based);
    try std.testing.expectEqual(@as(usize, 3), case.line_gas.isotopes_sim.len);
    try std.testing.expect(case.geometry.pseudo_spherical);
}

test "invalid controls are rejected instead of carried inertly" {
    var case = internal.input.defaults.referenceCase();
    case.observation.high_resolution_step_nm = 0.0;
    try std.testing.expectError(error.InvalidControl, internal.input.validate.referenceCase(case));

    case = internal.input.defaults.referenceCase();
    case.cia.enabled = false;
    try std.testing.expectError(error.InvalidControl, internal.input.validate.referenceCase(case));

    try std.testing.expectError(error.UnsupportedJsonInput, internal.input.json.parseReferenceCaseJson("{}"));
}
