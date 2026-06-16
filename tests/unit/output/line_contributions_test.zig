const std = @import("std");
const internal = @import("internal");
const o2a_scene = @import("../support/o2a_scene.zig");

const line_contributions = internal.output.line_contributions;

const allocator = std.testing.allocator;

// RowEvidence ------------------------------------------------------------------------------------------------|
// Test-local O2 line-contribution evidence from baseline artifact:                                       |
// Canonical expected values owned by this repository.                                                         |
// public-python-baseline.json .diagnostics.line_contributions.rows.                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 176 B (0.172 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] row_index: usize                                                                                 |
// [  8..175] row      : LineContributionRow                                                                   |
const RowEvidence = struct {
    row_index: usize,
    row: line_contributions.LineContributionRow,
};
// ------------------------------------------------------------------------------------------------------------|

const expected_rows = [_]RowEvidence{
    .{
        .row_index = 0,
        .row = .{
            .wavelength_nm = 758.0,
            .profile_node_index = 0,
            .altitude_km = -0.30687417130268846,
            .row_kind = .weak_line,
            .status = .weak_included,
            .line_index = 326,
            .strong_line_index = 4294967295,
            .matched_strong_line_index = 4294967295,
            .gas_index = 7,
            .isotope_number = 1,
            .isotopologue_code = 66,
            .center_wavelength_nm = 759.5754324317322,
            .center_wavenumber_cm1 = 13165.249392,
            .shifted_center_wavenumber_cm1 = 13165.2397546943,
            .line_strength_cm2_per_molecule = 1.098e-25,
            .air_half_width_cm1 = 0.0312,
            .pressure_shift_cm1 = -0.0093,
            .lower_state_energy_cm1 = 1245.9725,
            .temperature_k = 294.2,
            .pressure_hpa = 1050.0,
            .weak_line_sigma_cm2_per_molecule = 1.470550359845784e-30,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 1.470550359845784e-30,
            .abs_total_sigma_cm2_per_molecule = 1.470550359845784e-30,
        },
    },
    .{
        .row_index = 1,
        .row = .{
            .wavelength_nm = 758.0,
            .profile_node_index = 0,
            .altitude_km = -0.30687417130268846,
            .row_kind = .weak_line,
            .status = .weak_included,
            .line_index = 327,
            .strong_line_index = 4294967295,
            .matched_strong_line_index = 4294967295,
            .gas_index = 7,
            .isotope_number = 3,
            .isotopologue_code = 67,
            .center_wavelength_nm = 759.5802034166419,
            .center_wavenumber_cm1 = 13165.1667,
            .shifted_center_wavenumber_cm1 = 13165.1570626943,
            .line_strength_cm2_per_molecule = 5.256e-29,
            .air_half_width_cm1 = 0.0312,
            .pressure_shift_cm1 = -0.0093,
            .lower_state_energy_cm1 = 1210.0667,
            .temperature_k = 294.2,
            .pressure_hpa = 1050.0,
            .weak_line_sigma_cm2_per_molecule = 7.0050107314408325e-34,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 7.0050107314408325e-34,
            .abs_total_sigma_cm2_per_molecule = 7.0050107314408325e-34,
        },
    },
    .{
        .row_index = 500,
        .row = .{
            .wavelength_nm = 758.0,
            .profile_node_index = 1,
            .altitude_km = 0.0020875793966169676,
            .row_kind = .weak_line,
            .status = .weak_included,
            .line_index = 394,
            .strong_line_index = 4294967295,
            .matched_strong_line_index = 4294967295,
            .gas_index = 7,
            .isotope_number = 1,
            .isotopologue_code = 66,
            .center_wavelength_nm = 759.7951775403164,
            .center_wavenumber_cm1 = 13161.441788,
            .shifted_center_wavenumber_cm1 = 13161.431790467308,
            .line_strength_cm2_per_molecule = 3.378e-27,
            .air_half_width_cm1 = 0.0255,
            .pressure_shift_cm1 = -0.01,
            .lower_state_energy_cm1 = 2010.5953,
            .temperature_k = 294.2,
            .pressure_hpa = 1013.0,
            .weak_line_sigma_cm2_per_molecule = 2.688168394826091e-32,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 2.688168394826091e-32,
            .abs_total_sigma_cm2_per_molecule = 2.688168394826091e-32,
        },
    },
    .{
        .row_index = 10000,
        .row = .{
            .wavelength_nm = 758.0,
            .profile_node_index = 23,
            .altitude_km = 21.987872492065627,
            .row_kind = .weak_line,
            .status = .weak_included,
            .line_index = 390,
            .strong_line_index = 4294967295,
            .matched_strong_line_index = 4294967295,
            .gas_index = 7,
            .isotope_number = 2,
            .isotopologue_code = 68,
            .center_wavelength_nm = 759.782962192108,
            .center_wavenumber_cm1 = 13161.65339,
            .shifted_center_wavenumber_cm1 = 13161.653006155933,
            .line_strength_cm2_per_molecule = 3.991e-27,
            .air_half_width_cm1 = 0.0408,
            .pressure_shift_cm1 = -0.0089,
            .lower_state_energy_cm1 = 569.2054,
            .temperature_k = 221.6,
            .pressure_hpa = 43.7,
            .weak_line_sigma_cm2_per_molecule = 1.4843335201653664e-33,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 1.4843335201653664e-33,
            .abs_total_sigma_cm2_per_molecule = 1.4843335201653664e-33,
        },
    },
    .{
        .row_index = 50000,
        .row = .{
            .wavelength_nm = 765.0,
            .profile_node_index = 15,
            .altitude_km = 13.95938647915891,
            .row_kind = .strong_line,
            .status = .strong_sidecar,
            .line_index = 4294967295,
            .strong_line_index = 54,
            .matched_strong_line_index = 54,
            .gas_index = 7,
            .isotope_number = 1,
            .isotopologue_code = 66,
            .center_wavelength_nm = 759.8585667043321,
            .center_wavenumber_cm1 = 13160.34383,
            .shifted_center_wavenumber_cm1 = 13160.342471006661,
            .line_strength_cm2_per_molecule = std.math.nan(f64),
            .air_half_width_cm1 = 0.039425769443963796,
            .pressure_shift_cm1 = -0.009,
            .lower_state_energy_cm1 = 664.2595,
            .temperature_k = 215.7,
            .pressure_hpa = 153.0,
            .weak_line_sigma_cm2_per_molecule = 0.0,
            .strong_line_sigma_cm2_per_molecule = 1.5731618461428351e-31,
            .line_mixing_sigma_cm2_per_molecule = 1.6810984283119425e-30,
            .total_sigma_cm2_per_molecule = 1.838414612926226e-30,
            .abs_total_sigma_cm2_per_molecule = 1.838414612926226e-30,
        },
    },
};

test "O2 line contributions match public Python evidence at probe wavelengths" {
    var prepared = try internal.public.prepare(allocator, o2a_scene.reference());
    defer prepared.deinit(allocator);

    const wavelengths_nm = [_]f64{ 758.0, 760.0, 765.0, 767.0, 776.0 };
    var contributions = try internal.public.buildLineContributions(
        allocator,
        &prepared,
        wavelengths_nm[0..],
        50_001,
    );
    defer contributions.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 50_001), contributions.rows.len);
    try std.testing.expectEqual(@as(usize, 101_144), contributions.total_row_count);
    try std.testing.expect(contributions.truncated);

    for (expected_rows) |expected| {
        try expectRowEqual(expected.row, contributions.rows[expected.row_index]);
    }
}

fn expectRowEqual(
    expected: line_contributions.LineContributionRow,
    actual: line_contributions.LineContributionRow,
) !void {
    // expectRowEqual -----------------------------------------------------------------------------------------|
    // Compare one public O2 line-contribution row field-by-field so drift names the first bad column.         |
    // --------------------------------------------------------------------------------------------------------|
    try expectF64Bits(expected.wavelength_nm, actual.wavelength_nm);
    try std.testing.expectEqual(expected.profile_node_index, actual.profile_node_index);
    try expectF64Bits(expected.altitude_km, actual.altitude_km);
    try std.testing.expectEqual(expected.row_kind, actual.row_kind);
    try std.testing.expectEqual(expected.status, actual.status);
    try std.testing.expectEqual(expected.line_index, actual.line_index);
    try std.testing.expectEqual(expected.strong_line_index, actual.strong_line_index);
    try std.testing.expectEqual(expected.matched_strong_line_index, actual.matched_strong_line_index);
    try std.testing.expectEqual(expected.gas_index, actual.gas_index);
    try std.testing.expectEqual(expected.isotope_number, actual.isotope_number);
    try std.testing.expectEqual(expected.isotopologue_code, actual.isotopologue_code);
    try expectF64Bits(expected.center_wavelength_nm, actual.center_wavelength_nm);
    try expectF64Bits(expected.center_wavenumber_cm1, actual.center_wavenumber_cm1);
    try expectF64Bits(expected.shifted_center_wavenumber_cm1, actual.shifted_center_wavenumber_cm1);
    if (std.math.isNan(expected.line_strength_cm2_per_molecule)) {
        try std.testing.expect(std.math.isNan(actual.line_strength_cm2_per_molecule));
    } else {
        try expectF64Bits(expected.line_strength_cm2_per_molecule, actual.line_strength_cm2_per_molecule);
    }
    try expectF64Bits(expected.air_half_width_cm1, actual.air_half_width_cm1);
    try expectF64Bits(expected.pressure_shift_cm1, actual.pressure_shift_cm1);
    try expectF64Bits(expected.lower_state_energy_cm1, actual.lower_state_energy_cm1);
    try expectF64Bits(expected.temperature_k, actual.temperature_k);
    try expectF64Bits(expected.pressure_hpa, actual.pressure_hpa);
    try expectF64Bits(expected.weak_line_sigma_cm2_per_molecule, actual.weak_line_sigma_cm2_per_molecule);
    try expectF64Bits(expected.strong_line_sigma_cm2_per_molecule, actual.strong_line_sigma_cm2_per_molecule);
    try expectF64Bits(expected.line_mixing_sigma_cm2_per_molecule, actual.line_mixing_sigma_cm2_per_molecule);
    try expectF64Bits(expected.total_sigma_cm2_per_molecule, actual.total_sigma_cm2_per_molecule);
    try expectF64Bits(expected.abs_total_sigma_cm2_per_molecule, actual.abs_total_sigma_cm2_per_molecule);
}

fn expectF64Bits(expected: f64, actual: f64) !void {
    // expectF64Bits ------------------------------------------------------------------------------------------|
    // Enforce exact f64 bits for JSON values that round-trip without local derived-math exceptions.      |
    // --------------------------------------------------------------------------------------------------------|
    const expected_bits: u64 = @bitCast(expected);
    const actual_bits: u64 = @bitCast(actual);
    try std.testing.expectEqual(expected_bits, actual_bits);
}
