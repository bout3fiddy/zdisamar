const std = @import("std");
const internal = @import("internal");

test "ProfileLineValues keep one value per exact radiance wavelength" {
    var values = try internal.cache.profile_line_memory.buildReferenceProfileLineValues(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer values.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 701), values.values.len);
    try std.testing.expectEqual(@as(usize, 3874), values.recorded_forward_miss_count);
    try std.testing.expect(values.reuse_stamp.value != 0);
    try std.testing.expectApproxEqAbs(755.0, values.values[0].wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(776.0, values.values[values.values.len - 1].wavelength_nm, 0.0);
}

test "ProfileLineValues reproduce WP1 probe optical-depth values" {
    var values = try internal.cache.profile_line_memory.buildReferenceProfileLineValues(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer values.deinit(std.testing.allocator);

    try expectProbe(values, 758.0, 0.00350565072324649, 0.33305592074048884);
    try expectProbe(values, 760.0, 0.8352435635463854, 1.1671196972657576);
    try expectProbe(values, 765.0, 0.14846720294997337, 0.48065469408656813);
    try expectProbe(values, 767.0, 0.01613470147641476, 0.3447530683438321);
    try expectProbe(values, 776.0, 0.0001201820341403, 0.32427558378395965);
}

fn expectProbe(
    values: internal.cache.profile_line_memory.ProfileLineValues,
    wavelength_nm: f64,
    gas_absorption: f64,
    total_optical_depth: f64,
) !void {
    // expectProbe --------------------------------------------------------------------------------------------|
    // Assert one recorded diagnostic profile-line probe against its WP1 evidence values.                      |
    // --------------------------------------------------------------------------------------------------------|
    const probe = values.findProbe(wavelength_nm) orelse return error.MissingProbe;
    try std.testing.expectApproxEqAbs(gas_absorption, probe.gas_absorption_optical_depth, 1.0e-15);
    try std.testing.expectApproxEqAbs(total_optical_depth, probe.total_optical_depth, 1.0e-15);
}
