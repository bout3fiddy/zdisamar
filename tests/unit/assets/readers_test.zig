const std = @import("std");
const internal = @import("internal");
const o2a_scene = @import("../support/o2a_scene.zig");

const readers = internal.assets.readers;

test "asset readers load reference profile, line list, CIA, and solar rows" {
    const allocator = std.testing.allocator;
    const scene = o2a_scene.reference();

    const profile = try readers.readAtmosphereProfile(allocator, scene.atmosphere.profile.path);
    defer allocator.free(profile);
    try std.testing.expectEqual(@as(usize, 47), profile.len);
    try std.testing.expectApproxEqAbs(1013.0, profile[1].pressure_hpa, 0.0);

    const lines = try readers.readLineList(allocator, scene.line_gas.line_list.path);
    defer allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 1314), lines.len);
    try std.testing.expectEqual(@as(u16, 7), lines[0].gas_index);
    try std.testing.expectEqual(@as(u8, 1), lines[0].isotope_number);

    const strong_lines = try readers.readStrongLines(allocator, scene.line_gas.strong_lines.path);
    defer allocator.free(strong_lines);
    try std.testing.expectEqual(@as(usize, 70), strong_lines.len);

    // Source: data/reference_data/cross_sections/o2a_lisa_sdf.dat first row, parsed with
    try std.testing.expectApproxEqAbs(12965.107900, strong_lines[0].center_wavenumber_cm1, 0.0);
    try std.testing.expectApproxEqAbs(771.3009469053474, strong_lines[0].center_wavelength_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.0000510, strong_lines[0].population_t0, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.02828068983548333, strong_lines[0].air_half_width_cm1, 1.0e-15);
    try std.testing.expectEqual(@as(i32, -35), strong_lines[0].rotational_index_m1);

    var relaxation_matrix = try readers.readRelaxationMatrix(
        allocator,
        scene.line_gas.line_mixing.path,
    );
    defer relaxation_matrix.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 70), relaxation_matrix.line_count);

    // Source: data/reference_data/cross_sections/o2a_lisa_rmf.dat first row.
    try std.testing.expectApproxEqAbs(0.02764486, relaxation_matrix.weightAt(0, 0), 0.0);
    try std.testing.expectApproxEqAbs(0.629999646133, relaxation_matrix.temperatureExponentAt(0, 0), 0.0);

    var cia = try readers.readCiaTable(allocator, scene.cia.table.path);
    defer cia.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 18938), cia.rows.len);
    try std.testing.expectApproxEqAbs(1.0e-46, cia.scale_factor_cm5_per_molecule2, 0.0);
    try std.testing.expectApproxEqAbs(260.0, cia.rows[0].wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(2400.0, cia.rows[cia.rows.len - 1].wavelength_nm, 0.0);

    const solar = try readers.readSolarReference(allocator, scene.observation.solar_reference.path);
    defer allocator.free(solar);
    try std.testing.expectEqual(@as(usize, 2501), solar.len);
    try std.testing.expectApproxEqAbs(753.0, solar[0].wavelength_nm, 0.0);
}

test "asset readers reject malformed temporary fixtures with typed errors" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const empty_profile = try writeTempAsset(allocator, &tmp, "empty-profile.csv",
        \\altitude_km,pressure_hpa,temperature_k,air_number_density_cm3
        \\
    );
    defer allocator.free(empty_profile);
    try std.testing.expectError(error.EmptyAsset, readers.readAtmosphereProfile(allocator, empty_profile));

    const invalid_profile = try writeTempAsset(allocator, &tmp, "invalid-profile.csv",
        \\altitude_km,pressure_hpa,temperature_k,air_number_density_cm3
        \\0.0,bad,288.0,1.0e19
        \\
    );
    defer allocator.free(invalid_profile);
    try std.testing.expectError(error.InvalidNumber, readers.readAtmosphereProfile(allocator, invalid_profile));

    const short_line = try writeTempAsset(allocator, &tmp, "short-hitran.par", "short\n");
    defer allocator.free(short_line);
    try std.testing.expectError(error.InvalidAssetFormat, readers.readLineList(allocator, short_line));

    const short_strong_line = try writeTempAsset(allocator, &tmp, "short-strong.dat", "12965.1\n");
    defer allocator.free(short_strong_line);
    try std.testing.expectError(error.InvalidAssetFormat, readers.readStrongLines(allocator, short_strong_line));

    const short_relaxation = try writeTempAsset(allocator, &tmp, "short-rmf.dat", "0.1 0.2\n");
    defer allocator.free(short_relaxation);
    try std.testing.expectError(error.InvalidAssetFormat, readers.readRelaxationMatrix(allocator, short_relaxation));

    const cia_count_mismatch = try writeTempAsset(allocator, &tmp, "bad-cia.dat",
        \\1.0e-46
        \\0
        \\2
        \\260.0 1.0 2.0 3.0
        \\
    );
    defer allocator.free(cia_count_mismatch);
    try std.testing.expectError(error.InvalidAssetFormat, readers.readCiaTable(allocator, cia_count_mismatch));

    const empty_solar = try writeTempAsset(allocator, &tmp, "empty-solar.csv",
        \\wavelength_nm,irradiance
        \\
    );
    defer allocator.free(empty_solar);
    try std.testing.expectError(error.EmptyAsset, readers.readSolarReference(allocator, empty_solar));
}

test "solar asset reader cleans up across allocation failures" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const solar = try writeTempAsset(allocator, &tmp, "tiny-solar.csv",
        \\wavelength_nm,irradiance
        \\753.0,1.2
        \\754.0,1.3
        \\
    );
    defer allocator.free(solar);

    try std.testing.checkAllAllocationFailures(allocator, readTinySolarReference, .{solar});
}

fn writeTempAsset(
    allocator: std.mem.Allocator,
    tmp: *std.testing.TmpDir,
    sub_path: []const u8,
    data: []const u8,
) ![]u8 {
    try tmp.dir.writeFile(.{ .sub_path = sub_path, .data = data });
    return tmp.dir.realpathAlloc(allocator, sub_path);
}

fn readTinySolarReference(allocator: std.mem.Allocator, path: []const u8) !void {
    const solar = try readers.readSolarReference(allocator, path);
    defer allocator.free(solar);

    try std.testing.expectEqual(@as(usize, 2), solar.len);
    try std.testing.expectApproxEqAbs(753.0, solar[0].wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(1.3, solar[1].irradiance, 0.0);
}
