const std = @import("std");
const internal = @import("internal");

const cia_diagnostics = internal.output.cia_diagnostics;

const allocator = std.testing.allocator;

// RowEvidence ------------------------------------------------------------------------------------------------|
// Test-local public O2-O2 CIA evidence from O2 A baseline artifact:                                           |
// Canonical expected values owned by this repository.                                                         |
// public-python-baseline.json .diagnostics.collision_induced_absorption.rows.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 120 B (0.117 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] row_index: usize                                                                                 |
// [  8..119] row      : CiaRow                                                                                |
const RowEvidence = struct {
    row_index: usize,
    row: cia_diagnostics.CiaRow,
};
// ------------------------------------------------------------------------------------------------------------|

const expected_cia_rows = [_]RowEvidence{
    .{
        .row_index = 0,
        .row = .{
            .wavelength_nm = 758.0,
            .layer_index = 0,
            .sublayer_index = 0,
            .global_sublayer_index = 0,
            .interval_index_1based = 1,
            .altitude_km = -3.636916272619225e-05,
            .pressure_hpa = 1013.2499974119982,
            .temperature_k = 294.20205620757804,
            .oxygen_number_density_cm3 = 5.224995167106018e18,
            .path_length_cm = 0.0,
            .cia_cross_section_cm5_per_molecule2 = 0.0,
            .cia_optical_depth = 0.0,
            .total_absorption_optical_depth = 0.0,
            .total_optical_depth = 0.0,
            .cia_share_of_total_absorption = 0.0,
            .cia_share_of_total_optical_depth = 0.0,
        },
    },
    .{
        .row_index = 1,
        .row = .{
            .wavelength_nm = 758.0,
            .layer_index = 0,
            .sublayer_index = 0,
            .global_sublayer_index = 1,
            .interval_index_1based = 1,
            .altitude_km = 0.007506658210811699,
            .pressure_hpa = 1012.3624132494756,
            .temperature_k = 294.19449473014873,
            .oxygen_number_density_cm3 = 5.220552365887917e18,
            .path_length_cm = 1889.5354494827166,
            .cia_cross_section_cm5_per_molecule2 = 2.4616634207532467e-46,
            .cia_optical_depth = 1.26770040534369e-05,
            .total_absorption_optical_depth = 2.7504873904415636e-05,
            .total_optical_depth = 8.526373793855298e-05,
            .cia_share_of_total_absorption = 0.46090027889208873,
            .cia_share_of_total_optical_depth = 0.14867990027100192,
        },
    },
    .{
        .row_index = 227,
        .row = .{
            .wavelength_nm = 760.0,
            .layer_index = 0,
            .sublayer_index = 0,
            .global_sublayer_index = 1,
            .interval_index_1based = 1,
            .altitude_km = 0.007506658210811699,
            .pressure_hpa = 1012.3624132494756,
            .temperature_k = 294.19449473014873,
            .oxygen_number_density_cm3 = 5.220552365887917e18,
            .path_length_cm = 1889.5354494827166,
            .cia_cross_section_cm5_per_molecule2 = 4.501936434839764e-46,
            .cia_optical_depth = 2.318394381280432e-05,
            .total_absorption_optical_depth = 0.0038742877697214785,
            .total_optical_depth = 0.00393143472191721,
            .cia_share_of_total_absorption = 0.005984053119128785,
            .cia_share_of_total_optical_depth = 0.005897069505836383,
        },
    },
    .{
        .row_index = 905,
        .row = .{
            .wavelength_nm = 776.0,
            .layer_index = 0,
            .sublayer_index = 0,
            .global_sublayer_index = 1,
            .interval_index_1based = 1,
            .altitude_km = 0.007506658210811699,
            .pressure_hpa = 1012.3624132494756,
            .temperature_k = 294.19449473014873,
            .oxygen_number_density_cm3 = 5.220552365887917e18,
            .path_length_cm = 1889.5354494827166,
            .cia_cross_section_cm5_per_molecule2 = 1.082325063786383e-47,
            .cia_optical_depth = 5.57372673497254e-07,
            .total_absorption_optical_depth = 1.092679720354939e-06,
            .total_optical_depth = 5.3625399544667935e-05,
            .cia_share_of_total_absorption = 0.5100970239625209,
            .cia_share_of_total_optical_depth = 0.010393818567878148,
        },
    },
    .{
        .row_index = 1129,
        .row = .{
            .wavelength_nm = 776.0,
            .layer_index = 0,
            .sublayer_index = 0,
            .global_sublayer_index = 225,
            .interval_index_1based = 3,
            .altitude_km = 59.30427248486187,
            .pressure_hpa = 0.3000000002509619,
            .temperature_k = 259.2405337021464,
            .oxygen_number_density_cm3 = 1755631375691464.0,
            .path_length_cm = 0.0,
            .cia_cross_section_cm5_per_molecule2 = 0.0,
            .cia_optical_depth = 0.0,
            .total_absorption_optical_depth = 0.0,
            .total_optical_depth = 0.0,
            .cia_share_of_total_absorption = 0.0,
            .cia_share_of_total_optical_depth = 0.0,
        },
    },
};

test "O2-O2 CIA diagnostics match O2 A public Python evidence at probe wavelengths" {
    var prepared = try internal.public.prepare(allocator, internal.input.defaults.referenceScene());
    defer prepared.deinit(allocator);

    const wavelengths_nm = [_]f64{ 758.0, 760.0, 765.0, 767.0, 776.0 };
    var diagnostics = try internal.public.buildCiaDiagnostics(
        allocator,
        &prepared,
        wavelengths_nm[0..],
    );
    defer diagnostics.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1130), diagnostics.rows.len);
    try std.testing.expectEqual(@as(usize, 226), diagnostics.rows.len / wavelengths_nm.len);

    for (expected_cia_rows) |expected| {
        try expectRowEqual(expected.row, diagnostics.rows[expected.row_index]);
    }
}

fn expectRowEqual(expected: cia_diagnostics.CiaRow, actual: cia_diagnostics.CiaRow) !void {
    // expectRowEqual -----------------------------------------------------------------------------------------|
    // Compare one CIA diagnostic row field-by-field so drift points at the first diverging column.            |
    // --------------------------------------------------------------------------------------------------------|
    try expectF64Bits(expected.wavelength_nm, actual.wavelength_nm);
    try std.testing.expectEqual(expected.layer_index, actual.layer_index);
    try std.testing.expectEqual(expected.sublayer_index, actual.sublayer_index);
    try std.testing.expectEqual(expected.global_sublayer_index, actual.global_sublayer_index);
    try std.testing.expectEqual(expected.interval_index_1based, actual.interval_index_1based);
    try expectF64Bits(expected.altitude_km, actual.altitude_km);
    try expectF64Bits(expected.pressure_hpa, actual.pressure_hpa);
    try expectF64Bits(expected.temperature_k, actual.temperature_k);
    try expectF64Bits(expected.oxygen_number_density_cm3, actual.oxygen_number_density_cm3);
    try expectF64Bits(expected.path_length_cm, actual.path_length_cm);
    try expectOpticalDepthUlp(expected.cia_cross_section_cm5_per_molecule2, actual.cia_cross_section_cm5_per_molecule2);
    try expectOpticalDepthUlp(expected.cia_optical_depth, actual.cia_optical_depth);
    try expectOpticalDepthUlp(expected.total_absorption_optical_depth, actual.total_absorption_optical_depth);
    try expectOpticalDepthUlp(expected.total_optical_depth, actual.total_optical_depth);
    try expectOpticalDepthUlp(expected.cia_share_of_total_absorption, actual.cia_share_of_total_absorption);
    try expectOpticalDepthUlp(expected.cia_share_of_total_optical_depth, actual.cia_share_of_total_optical_depth);
}

fn expectF64Bits(expected: f64, actual: f64) !void {
    // expectF64Bits ------------------------------------------------------------------------------------------|
    // Enforce exact f64 bits for O2 A JSON values that round-trip without local derived math.                 |
    // --------------------------------------------------------------------------------------------------------|
    const expected_bits: u64 = @bitCast(expected);
    const actual_bits: u64 = @bitCast(actual);
    try std.testing.expectEqual(expected_bits, actual_bits);
}

fn expectOpticalDepthUlp(expected: f64, actual: f64) !void {
    // expectOpticalDepthUlp ----------------------------------------------------------------------------------|
    // CIA optical columns inherit the atmospheric-budget one-ULP product-order exception and add only the     |
    // canonical ratio projection. Larger drift still fails deterministically.                                 |
    // --------------------------------------------------------------------------------------------------------|
    const expected_bits: u64 = @bitCast(expected);
    const actual_bits: u64 = @bitCast(actual);
    const ulp_delta = if (expected_bits > actual_bits) expected_bits - actual_bits else actual_bits - expected_bits;
    try std.testing.expect(ulp_delta <= 1);
}
