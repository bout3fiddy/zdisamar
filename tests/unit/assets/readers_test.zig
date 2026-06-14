const std = @import("std");
const internal = @import("internal");
const o2a_scene = @import("../support/o2a_scene.zig");

test "asset readers load reference profile, line list, CIA, and solar rows" {
    const allocator = std.testing.allocator;
    const scene = o2a_scene.reference();

    const profile = try internal.assets.readers.readAtmosphereProfile(allocator, scene.atmosphere.profile.path);
    defer allocator.free(profile);
    try std.testing.expectEqual(@as(usize, 47), profile.len);
    try std.testing.expectApproxEqAbs(1013.0, profile[1].pressure_hpa, 0.0);

    const lines = try internal.assets.readers.readLineList(allocator, scene.line_gas.line_list.path);
    defer allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 1314), lines.len);
    try std.testing.expectEqual(@as(u16, 7), lines[0].gas_index);
    try std.testing.expectEqual(@as(u8, 1), lines[0].isotope_number);

    const strong_lines = try internal.assets.readers.readStrongLines(allocator, scene.line_gas.strong_lines.path);
    defer allocator.free(strong_lines);
    try std.testing.expectEqual(@as(usize, 70), strong_lines.len);

    // Source: data/reference_data/cross_sections/o2a_lisa_sdf.dat first row, parsed with
    try std.testing.expectApproxEqAbs(12965.107900, strong_lines[0].center_wavenumber_cm1, 0.0);
    try std.testing.expectApproxEqAbs(771.3009469053474, strong_lines[0].center_wavelength_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.0000510, strong_lines[0].population_t0, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.02828068983548333, strong_lines[0].air_half_width_cm1, 1.0e-15);
    try std.testing.expectEqual(@as(i32, -35), strong_lines[0].rotational_index_m1);

    var relaxation_matrix = try internal.assets.readers.readRelaxationMatrix(
        allocator,
        scene.line_gas.line_mixing.path,
    );
    defer relaxation_matrix.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 70), relaxation_matrix.line_count);

    // Source: data/reference_data/cross_sections/o2a_lisa_rmf.dat first row.
    try std.testing.expectApproxEqAbs(0.02764486, relaxation_matrix.weightAt(0, 0), 0.0);
    try std.testing.expectApproxEqAbs(0.629999646133, relaxation_matrix.temperatureExponentAt(0, 0), 0.0);

    var cia = try internal.assets.readers.readCiaTable(allocator, scene.cia.table.path);
    defer cia.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 18938), cia.rows.len);
    try std.testing.expectApproxEqAbs(1.0e-46, cia.scale_factor_cm5_per_molecule2, 0.0);
    try std.testing.expectApproxEqAbs(260.0, cia.rows[0].wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(2400.0, cia.rows[cia.rows.len - 1].wavelength_nm, 0.0);

    const solar = try internal.assets.readers.readSolarReference(allocator, scene.observation.solar_reference.path);
    defer allocator.free(solar);
    try std.testing.expectEqual(@as(usize, 2501), solar.len);
    try std.testing.expectApproxEqAbs(753.0, solar[0].wavelength_nm, 0.0);
}
