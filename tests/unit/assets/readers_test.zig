const std = @import("std");
const internal = @import("internal");

test "asset readers load reference profile, line list, CIA, and solar rows" {
    const allocator = std.testing.allocator;
    const case = internal.input.defaults.referenceCase();

    const profile = try internal.assets.readers.readAtmosphereProfile(allocator, case.atmosphere.profile.path);
    defer allocator.free(profile);
    try std.testing.expectEqual(@as(usize, 47), profile.len);
    try std.testing.expectApproxEqAbs(1013.0, profile[1].pressure_hpa, 0.0);

    const lines = try internal.assets.readers.readO2LineList(allocator, case.line_gas.line_list.path);
    defer allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 1314), lines.len);
    try std.testing.expectEqual(@as(u16, 7), lines[0].gas_index);
    try std.testing.expectEqual(@as(u8, 1), lines[0].isotope_number);

    var cia = try internal.assets.readers.readCiaTable(allocator, case.cia.table.path);
    defer cia.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 18938), cia.rows.len);
    try std.testing.expectApproxEqAbs(1.0e-46, cia.scale_factor_cm5_per_molecule2, 0.0);
    try std.testing.expectApproxEqAbs(260.0, cia.rows[0].wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(2400.0, cia.rows[cia.rows.len - 1].wavelength_nm, 0.0);

    const solar = try internal.assets.readers.readSolarReference(allocator, case.observation.solar_reference.path);
    defer allocator.free(solar);
    try std.testing.expectEqual(@as(usize, 2501), solar.len);
    try std.testing.expectApproxEqAbs(753.0, solar[0].wavelength_nm, 0.0);
}
