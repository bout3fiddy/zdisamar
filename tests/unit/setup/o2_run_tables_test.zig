const std = @import("std");
const internal = @import("internal");

test "O2RunTables match WP1 baseline table evidence" {
    var tables = try internal.setup.o2_run_tables.buildReferenceO2RunTables(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1848), @sizeOf(internal.setup.o2_run_tables.O2RunTables));

    try std.testing.expectEqual(@as(usize, 45), tables.layers.layer_pressures_hpa.len);
    try std.testing.expectEqual(@as(usize, 226), tables.layers.support_pressures_hpa.len);
    try std.testing.expectEqual(@as(usize, 45), tables.layers.layer_temperatures_k.len);
    try std.testing.expectEqual(@as(usize, 226), tables.layers.support_temperatures_k.len);

    // Source: evidence/baseline-main-56605387/public-python-baseline.json
    // diagnostics.atmospheric_budget.rows for the 758 nm probe.
    for (support_thermodynamic_evidence) |expected| {
        try std.testing.expectApproxEqAbs(
            expected.pressure_hpa,
            tables.layers.support_pressures_hpa[expected.index],
            1.0e-5,
        );
        try std.testing.expectApproxEqAbs(
            expected.temperature_k,
            tables.layers.support_temperatures_k[expected.index],
            1.0e-5,
        );
    }

    // Source: evidence/baseline-main-56605387/public-python-baseline.json
    // diagnostics.atmospheric_budget.rows[layer_support_start] for the 758 nm probe.
    for (layer_thermodynamic_evidence) |expected| {
        try std.testing.expectEqual(expected.support_index, tables.layers.layer_support_starts[expected.index]);
        try std.testing.expectApproxEqAbs(
            expected.pressure_hpa,
            tables.layers.layer_pressures_hpa[expected.index],
            1.0e-5,
        );
        try std.testing.expectApproxEqAbs(
            expected.temperature_k,
            tables.layers.layer_temperatures_k[expected.index],
            1.0e-5,
        );
    }

    try std.testing.expectEqual(@as(usize, 1314), tables.lines.rows.len);

    // Source: evidence/baseline-main-56605387/internal-dump-baseline.json
    // first diagnostic line anchor from the old internal dump.

    const diagnostic_line = findLineByWavenumber(tables.lines.rows, 13165.249392) orelse return error.MissingLine;
    try std.testing.expectApproxEqAbs(759.5754324317322, diagnostic_line.center_wavelength_nm, 1.0e-12);

    try std.testing.expectEqual(@as(usize, 18938), tables.cia.rows.len);
    try std.testing.expectApproxEqAbs(260.0, tables.cia.rows[0].wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(2400.0, tables.cia.rows[tables.cia.rows.len - 1].wavelength_nm, 0.0);

    try std.testing.expectApproxEqAbs(0.3, tables.aerosol.optical_depth, 0.0);
    try std.testing.expectApproxEqAbs(1.0, tables.aerosol.single_scatter_albedo, 0.0);
    try std.testing.expectEqual(@as(usize, 39), tables.phase.aerosol_phase_max_index);
    try std.testing.expectApproxEqAbs(1.0, tables.phase.aerosol_phase_coefficients[0], 0.0);
    try std.testing.expectApproxEqAbs(2.1, tables.phase.aerosol_phase_coefficients[1], 1.0e-14);
    try std.testing.expectEqual(@as(usize, 2501), tables.solar.rows.len);
}

fn findLineByWavenumber(
    rows: []const internal.assets.readers.O2LineAssetRow,
    center_wavenumber_cm1: f64,
) ?internal.assets.readers.O2LineAssetRow {
    // findLineByWavenumber -----------------------------------------------------------------------------------|
    // Locate one parsed HITRAN line used as test-side evidence.                                               |
    // --------------------------------------------------------------------------------------------------------|
    for (rows) |row| {
        if (@abs(row.center_wavenumber_cm1 - center_wavenumber_cm1) <= 1.0e-12) return row;
    }
    return null;
}

// ThermodynamicEvidence --------------------------------------------------------------------------------------|
// One support-row pressure/temperature evidence anchor.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] index         : usize                                                                              |
// [ 8..15] pressure_hpa  : f64                                                                                |
// [16..23] temperature_k : f64                                                                                |
const ThermodynamicEvidence = struct {
    index: usize,
    pressure_hpa: f64,
    temperature_k: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// LayerThermodynamicEvidence ---------------------------------------------------------------------------------|
// One layer representative pressure/temperature evidence anchor.                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] index         : usize                                                                              |
// [ 8..11] support_index : u32                                                                                |
// [12..15] padding                                                                                            |
// [16..23] pressure_hpa  : f64                                                                                |
// [24..31] temperature_k : f64                                                                                |
const LayerThermodynamicEvidence = struct {
    index: usize,
    support_index: u32,
    pressure_hpa: f64,
    temperature_k: f64,
};
// ------------------------------------------------------------------------------------------------------------|

const support_thermodynamic_evidence = [_]ThermodynamicEvidence{
    .{ .index = 0, .pressure_hpa = 1013.2499974119982, .temperature_k = 294.20205620757804 },
    .{ .index = 1, .pressure_hpa = 1012.3624132494756, .temperature_k = 294.19449473014873 },
    .{ .index = 2, .pressure_hpa = 1009.0377743170635, .temperature_k = 294.15977339734002 },
    .{ .index = 4, .pressure_hpa = 1001.4140088615687, .temperature_k = 294.04332751182829 },
    .{ .index = 5, .pressure_hpa = 1000.536057060438, .temperature_k = 294.02674411171006 },
    .{ .index = 50, .pressure_hpa = 519.31407199154603, .temperature_k = 264.19792446353955 },
    .{ .index = 100, .pressure_hpa = 369.79912937455515, .temperature_k = 247.91730019745779 },
    .{ .index = 150, .pressure_hpa = 11.339039526615537, .temperature_k = 235.95805593787273 },
    .{ .index = 200, .pressure_hpa = 0.47314239728087698, .temperature_k = 267.94279546234492 },
    .{ .index = 225, .pressure_hpa = 0.30000000025096191, .temperature_k = 259.24053370214642 },
};

const layer_thermodynamic_evidence = [_]LayerThermodynamicEvidence{
    .{ .index = 0, .support_index = 0, .pressure_hpa = 1013.2499974119982, .temperature_k = 294.20205620757804 },
    .{ .index = 1, .support_index = 5, .pressure_hpa = 1000.536057060438, .temperature_k = 294.02674411171006 },
    .{ .index = 7, .support_index = 35, .pressure_hpa = 558.45819912127274, .temperature_k = 267.57720774615046 },
    .{ .index = 16, .support_index = 80, .pressure_hpa = 500.0000040701978, .temperature_k = 262.43908974790105 },
    .{ .index = 29, .support_index = 145, .pressure_hpa = 17.351474312024568, .temperature_k = 229.64699759159203 },
    .{ .index = 44, .support_index = 220, .pressure_hpa = 0.30370805081450852, .temperature_k = 259.50289748782882 },
};
