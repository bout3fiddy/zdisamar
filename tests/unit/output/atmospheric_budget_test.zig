const std = @import("std");
const internal = @import("internal");
const o2a_scene = @import("../support/o2a_scene.zig");

const atmospheric_budget = internal.output.atmospheric_budget;

const allocator = std.testing.allocator;

// RowEvidence ------------------------------------------------------------------------------------------------|
// Test-local public atmospheric-budget evidence from O2 A baseline artifact:                                  |
// Canonical expected values owned by this repository.                                                         |
// public-python-baseline.json .diagnostics.atmospheric_budget.rows.                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 216 B (0.211 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] row_index: usize                                                                                 |
// [  8..215] row      : AtmosphericBudgetRow                                                                  |
const RowEvidence = struct {
    row_index: usize,
    row: atmospheric_budget.AtmosphericBudgetRow,
};
// ------------------------------------------------------------------------------------------------------------|

const expected_budget_rows = [_]RowEvidence{
    .{
        .row_index = 0,
        .row = .{
            .wavelength_nm = 758.0,
            .layer_index = 0,
            .sublayer_index = 0,
            .global_sublayer_index = 0,
            .interval_index_1based = 1,
            .support_row_kind = 1,
            .altitude_km = -3.636916272619225e-05,
            .top_altitude_km = -3.636916272619225e-05,
            .bottom_altitude_km = -3.636916272619225e-05,
            .pressure_hpa = 1013.2499974119982,
            .top_pressure_hpa = 1013.25,
            .bottom_pressure_hpa = 1013.25,
            .temperature_k = 294.20205620757804,
            .number_density_cm3 = 2.49450738427672e19,
            .oxygen_number_density_cm3 = 5.224995167106018e18,
            .absorber_number_density_cm3 = 5.224995167106018e18,
            .path_length_cm = 0.0,
            .aerosol_fraction = 0.0,
            .gas_absorption_optical_depth = 0.0,
            .gas_scattering_optical_depth = 0.0,
            .cia_optical_depth = 0.0,
            .aerosol_optical_depth = 0.0,
            .aerosol_scattering_optical_depth = 0.0,
            .aerosol_absorption_optical_depth = 0.0,
            .total_absorption_optical_depth = 0.0,
            .total_scattering_optical_depth = 0.0,
            .total_optical_depth = 0.0,
            .single_scatter_albedo = 0.0,
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
            .support_row_kind = 2,
            .altitude_km = 0.007506658210811699,
            .top_altitude_km = 0.10860293690967149,
            .bottom_altitude_km = -3.636916272619225e-05,
            .pressure_hpa = 1012.3624132494756,
            .top_pressure_hpa = 1000.536057060438,
            .bottom_pressure_hpa = 1013.25,
            .temperature_k = 294.19449473014873,
            .number_density_cm3 = 2.4923863104592368e19,
            .oxygen_number_density_cm3 = 5.220552365887917e18,
            .absorber_number_density_cm3 = 5.220552365887917e18,
            .path_length_cm = 1889.5354494827166,
            .aerosol_fraction = 0.0,
            .gas_absorption_optical_depth = 1.4827869850978738e-05,
            .gas_scattering_optical_depth = 5.7758864034137354e-05,
            .cia_optical_depth = 1.26770040534369e-05,
            .aerosol_optical_depth = 0.0,
            .aerosol_scattering_optical_depth = 0.0,
            .aerosol_absorption_optical_depth = 0.0,
            .total_absorption_optical_depth = 2.7504873904415636e-05,
            .total_scattering_optical_depth = 5.7758864034137354e-05,
            .total_optical_depth = 8.526373793855298e-05,
            .single_scatter_albedo = 0.6774141672719349,
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
            .support_row_kind = 2,
            .altitude_km = 0.007506658210811699,
            .top_altitude_km = 0.10860293690967149,
            .bottom_altitude_km = -3.636916272619225e-05,
            .pressure_hpa = 1012.3624132494756,
            .top_pressure_hpa = 1000.536057060438,
            .bottom_pressure_hpa = 1013.25,
            .temperature_k = 294.19449473014873,
            .number_density_cm3 = 2.4923863104592368e19,
            .oxygen_number_density_cm3 = 5.220552365887917e18,
            .absorber_number_density_cm3 = 5.220552365887917e18,
            .path_length_cm = 1889.5354494827166,
            .aerosol_fraction = 0.0,
            .gas_absorption_optical_depth = 0.003851103825908674,
            .gas_scattering_optical_depth = 5.714695219573125e-05,
            .cia_optical_depth = 2.318394381280432e-05,
            .aerosol_optical_depth = 0.0,
            .aerosol_scattering_optical_depth = 0.0,
            .aerosol_absorption_optical_depth = 0.0,
            .total_absorption_optical_depth = 0.0038742877697214785,
            .total_scattering_optical_depth = 5.714695219573125e-05,
            .total_optical_depth = 0.00393143472191721,
            .single_scatter_albedo = 0.014535902599919775,
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
            .support_row_kind = 2,
            .altitude_km = 0.007506658210811699,
            .top_altitude_km = 0.10860293690967149,
            .bottom_altitude_km = -3.636916272619225e-05,
            .pressure_hpa = 1012.3624132494756,
            .top_pressure_hpa = 1000.536057060438,
            .bottom_pressure_hpa = 1013.25,
            .temperature_k = 294.19449473014873,
            .number_density_cm3 = 2.4923863104592368e19,
            .oxygen_number_density_cm3 = 5.220552365887917e18,
            .absorber_number_density_cm3 = 5.220552365887917e18,
            .path_length_cm = 1889.5354494827166,
            .aerosol_fraction = 0.0,
            .gas_absorption_optical_depth = 5.35307046857685e-07,
            .gas_scattering_optical_depth = 5.2532719824312994e-05,
            .cia_optical_depth = 5.57372673497254e-07,
            .aerosol_optical_depth = 0.0,
            .aerosol_scattering_optical_depth = 0.0,
            .aerosol_absorption_optical_depth = 0.0,
            .total_absorption_optical_depth = 1.092679720354939e-06,
            .total_scattering_optical_depth = 5.2532719824312994e-05,
            .total_optical_depth = 5.3625399544667935e-05,
            .single_scatter_albedo = 0.979623840015499,
        },
    },
    .{
        .row_index = 1129,
        .row = .{
            .wavelength_nm = 776.0,
            .layer_index = 44,
            .sublayer_index = 4,
            .global_sublayer_index = 225,
            .interval_index_1based = 3,
            .support_row_kind = 1,
            .altitude_km = 59.30427248486187,
            .top_altitude_km = 59.30427248486187,
            .bottom_altitude_km = 59.30427248486187,
            .pressure_hpa = 0.3000000002509619,
            .top_pressure_hpa = 0.3,
            .bottom_pressure_hpa = 0.3,
            .temperature_k = 259.2405337021464,
            .number_density_cm3 = 8381702356972519.0,
            .oxygen_number_density_cm3 = 1755631375691464.0,
            .absorber_number_density_cm3 = 1755631375691464.0,
            .path_length_cm = 0.0,
            .aerosol_fraction = 0.0,
            .gas_absorption_optical_depth = 0.0,
            .gas_scattering_optical_depth = 0.0,
            .cia_optical_depth = 0.0,
            .aerosol_optical_depth = 0.0,
            .aerosol_scattering_optical_depth = 0.0,
            .aerosol_absorption_optical_depth = 0.0,
            .total_absorption_optical_depth = 0.0,
            .total_scattering_optical_depth = 0.0,
            .total_optical_depth = 0.0,
            .single_scatter_albedo = 0.0,
        },
    },
};

test "atmospheric budget rows match O2 A public Python evidence at probe wavelengths" {
    var prepared = try internal.public.prepare(allocator, o2a_scene.reference());
    defer prepared.deinit(allocator);

    const wavelengths_nm = [_]f64{ 758.0, 760.0, 765.0, 767.0, 776.0 };
    var budget = try internal.public.buildAtmosphericBudget(allocator, &prepared, wavelengths_nm[0..]);
    defer budget.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1130), budget.rows.len);
    try std.testing.expectEqual(@as(usize, 226), budget.rows.len / wavelengths_nm.len);

    for (expected_budget_rows) |expected| {
        try expectRowEqual(expected.row, budget.rows[expected.row_index]);
    }
}

fn expectRowEqual(
    expected: atmospheric_budget.AtmosphericBudgetRow,
    actual: atmospheric_budget.AtmosphericBudgetRow,
) !void {
    // expectRowEqual -----------------------------------------------------------------------------------------|
    // Compare one public diagnostic row field-by-field so drift points at the first diverging column.         |
    // --------------------------------------------------------------------------------------------------------|
    try expectF64Bits(expected.wavelength_nm, actual.wavelength_nm);
    try std.testing.expectEqual(expected.layer_index, actual.layer_index);
    try std.testing.expectEqual(expected.sublayer_index, actual.sublayer_index);
    try std.testing.expectEqual(expected.global_sublayer_index, actual.global_sublayer_index);
    try std.testing.expectEqual(expected.interval_index_1based, actual.interval_index_1based);
    try std.testing.expectEqual(expected.support_row_kind, actual.support_row_kind);
    try expectF64Bits(expected.altitude_km, actual.altitude_km);
    try expectF64Bits(expected.top_altitude_km, actual.top_altitude_km);
    try expectF64Bits(expected.bottom_altitude_km, actual.bottom_altitude_km);
    try expectF64Bits(expected.pressure_hpa, actual.pressure_hpa);
    try expectF64Bits(expected.top_pressure_hpa, actual.top_pressure_hpa);
    try expectF64Bits(expected.bottom_pressure_hpa, actual.bottom_pressure_hpa);
    try expectF64Bits(expected.temperature_k, actual.temperature_k);
    try expectF64Bits(expected.number_density_cm3, actual.number_density_cm3);
    try expectF64Bits(expected.oxygen_number_density_cm3, actual.oxygen_number_density_cm3);
    try expectF64Bits(expected.absorber_number_density_cm3, actual.absorber_number_density_cm3);
    try expectF64Bits(expected.path_length_cm, actual.path_length_cm);
    try expectF64Bits(expected.aerosol_fraction, actual.aerosol_fraction);
    try expectOpticalDepthUlp(expected.gas_absorption_optical_depth, actual.gas_absorption_optical_depth);
    try expectOpticalDepthUlp(expected.gas_scattering_optical_depth, actual.gas_scattering_optical_depth);
    try expectOpticalDepthUlp(expected.cia_optical_depth, actual.cia_optical_depth);
    try expectOpticalDepthUlp(expected.aerosol_optical_depth, actual.aerosol_optical_depth);
    try expectOpticalDepthUlp(expected.aerosol_scattering_optical_depth, actual.aerosol_scattering_optical_depth);
    try expectOpticalDepthUlp(expected.aerosol_absorption_optical_depth, actual.aerosol_absorption_optical_depth);
    try expectOpticalDepthUlp(expected.total_absorption_optical_depth, actual.total_absorption_optical_depth);
    try expectOpticalDepthUlp(expected.total_scattering_optical_depth, actual.total_scattering_optical_depth);
    try expectOpticalDepthUlp(expected.total_optical_depth, actual.total_optical_depth);
    try expectOpticalDepthUlp(expected.single_scatter_albedo, actual.single_scatter_albedo);
}

fn expectF64Bits(expected: f64, actual: f64) !void {
    // expectF64Bits ------------------------------------------------------------------------------------------|
    // Enforce the O2 A diagnostic rule: use exact f64 bits when O2 A JSON round-trips the value.              |
    // --------------------------------------------------------------------------------------------------------|
    const expected_bits: u64 = @bitCast(expected);
    const actual_bits: u64 = @bitCast(actual);
    try std.testing.expectEqual(expected_bits, actual_bits);
}

fn expectOpticalDepthUlp(expected: f64, actual: f64) !void {
    // expectOpticalDepthUlp ----------------------------------------------------------------------------------|
    // Optical-depth products are compared as ULPs rather than prose tolerance. O2 A JSON values are the       |
    // expected source; this permits only the one-ULP product-order difference already present in the O2 A     |
    // optics rows, and still fails larger drift.                                                              |
    // --------------------------------------------------------------------------------------------------------|
    const expected_bits: u64 = @bitCast(expected);
    const actual_bits: u64 = @bitCast(actual);
    const ulp_delta = if (expected_bits > actual_bits) expected_bits - actual_bits else actual_bits - expected_bits;
    try std.testing.expect(ulp_delta <= 1);
}
