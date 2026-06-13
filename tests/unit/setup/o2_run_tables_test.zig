const std = @import("std");
const internal = @import("internal");

test "O2RunTables match O2 A baseline table evidence" {
    var tables = try internal.setup.o2_run_tables.buildO2RunTables(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2024), @sizeOf(internal.setup.o2_run_tables.O2RunTables));
    try std.testing.expectEqual(@as(usize, 88), @sizeOf(internal.setup.atmosphere_layers.LayerQuadrature));

    try std.testing.expectEqual(@as(usize, 45), tables.layers.layer_pressures_hpa.len);
    try std.testing.expectEqual(@as(usize, 226), tables.layers.support_pressures_hpa.len);
    try std.testing.expectEqual(@as(usize, 45), tables.layers.layer_temperatures_k.len);
    try std.testing.expectEqual(@as(usize, 226), tables.layers.support_temperatures_k.len);

    // Canonical expected values owned by this repository.
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

    // Canonical expected values owned by this repository.
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
    try std.testing.expectEqual(@as(usize, 70), tables.lines.strong_lines.len);
    try std.testing.expectEqual(@as(usize, 70), tables.lines.relaxation_matrix.line_count);

    // Canonical expected values owned by this repository.
    // first diagnostic line anchor from the internal dump.

    const diagnostic_line = findLineByWavenumber(tables.lines.rows, 13165.249392) orelse return error.MissingLine;
    try std.testing.expectApproxEqAbs(759.5754324317322, diagnostic_line.center_wavelength_nm, 1.0e-12);

    // Source: data/reference_data/cross_sections/o2a_lisa_sdf.dat and o2a_lisa_rmf.dat first rows,
    try std.testing.expectApproxEqAbs(12965.107900, tables.lines.strong_lines[0].center_wavenumber_cm1, 0.0);
    try std.testing.expectApproxEqAbs(0.02764486, tables.lines.relaxation_matrix.weightAt(0, 0), 0.0);

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

test "LayerQuadrature rows match per-call quadrature builders" {
    const allocator = std.testing.allocator;
    const gauss_legendre = internal.common.math.gauss_legendre;

    const case = internal.input.defaults.referenceCase();
    var tables = try internal.setup.o2_run_tables.buildO2RunTables(allocator, case);
    defer tables.deinit(allocator);

    const support_order = @max(case.atmosphere.sublayer_divisions, @as(usize, 1));
    var expected_support_nodes = [_]f64{0.0} ** gauss_legendre.max_fixed_rule_order;
    var expected_support_weights = [_]f64{0.0} ** gauss_legendre.max_fixed_rule_order;
    try gauss_legendre.fillNodesAndWeights(
        @intCast(support_order),
        expected_support_nodes[0..support_order],
        expected_support_weights[0..support_order],
    );

    try std.testing.expectEqual(support_order, tables.quadrature.support_order);
    try expectEqualF64Slices(expected_support_nodes[0..support_order], tables.quadrature.support_nodes);
    try expectEqualF64Slices(expected_support_weights[0..support_order], tables.quadrature.support_weights);

    for (case.atmosphere.intervals) |interval| {
        const order = interval.altitude_divisions;
        if (order == 0) continue;

        var old_nodes = [_]f64{0.0} ** gauss_legendre.max_disamar_division_points;
        var scaled_nodes = [_]f64{0.0} ** gauss_legendre.max_disamar_division_points;
        try gauss_legendre.fillDisamarDivPointsIntervalNodes(
            @intCast(order),
            2.3,
            17.9,
            old_nodes[0..order],
        );
        try gauss_legendre.scaleIntervalNodes(
            try tables.quadrature.intervalNodes(order),
            2.3,
            17.9,
            scaled_nodes[0..order],
        );
        try expectEqualF64Slices(old_nodes[0..order], scaled_nodes[0..order]);
    }
}

test "LayerGrid rebuild from prepared profiles matches full pressure-mutated build" {
    const allocator = std.testing.allocator;
    const atmosphere_layers = internal.setup.atmosphere_layers;

    const base_case = internal.input.defaults.referenceCase();
    var base_tables = try internal.setup.o2_run_tables.buildO2RunTables(allocator, base_case);
    defer base_tables.deinit(allocator);

    var case = base_case;
    const intervals = try allocator.dupe(internal.input.o2_case.VerticalInterval, base_case.atmosphere.intervals);
    defer allocator.free(intervals);
    case.atmosphere.intervals = intervals;
    try moveAerosolLayerPressure(&case, intervals, 820.0);

    var full = try atmosphere_layers.build(allocator, case);
    defer full.deinit(allocator);
    var refreshed = try atmosphere_layers.buildFromPreparedProfiles(
        allocator,
        case,
        base_tables.layers.source_profile.rows,
        base_tables.layers.spectroscopy_profile.rows,
        base_tables.quadrature,
    );
    defer refreshed.deinit(allocator);

    try expectEqualF64Slices(full.layer_top_altitudes_km, refreshed.layer_top_altitudes_km);
    try expectEqualF64Slices(full.layer_bottom_altitudes_km, refreshed.layer_bottom_altitudes_km);
    try expectEqualF64Slices(full.layer_top_pressures_hpa, refreshed.layer_top_pressures_hpa);
    try expectEqualF64Slices(full.layer_bottom_pressures_hpa, refreshed.layer_bottom_pressures_hpa);
    try expectEqualF64Slices(full.layer_pressures_hpa, refreshed.layer_pressures_hpa);
    try expectEqualF64Slices(full.layer_temperatures_k, refreshed.layer_temperatures_k);
    try expectEqualF64Slices(full.support_mid_altitudes_km, refreshed.support_mid_altitudes_km);
    try expectEqualF64Slices(full.support_pressures_hpa, refreshed.support_pressures_hpa);
    try expectEqualF64Slices(full.support_temperatures_k, refreshed.support_temperatures_k);
    try std.testing.expectEqualSlices(
        u32,
        full.layer_interval_indices_1based,
        refreshed.layer_interval_indices_1based,
    );
    try std.testing.expectEqualSlices(
        u32,
        full.support_interval_indices_1based,
        refreshed.support_interval_indices_1based,
    );
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

fn moveAerosolLayerPressure(
    case: *internal.input.o2_case.O2Case,
    intervals: []internal.input.o2_case.VerticalInterval,
    mid_pressure_hpa: f64,
) !void {
    // moveAerosolLayerPressure -------------------------------------------------------------------------------|
    // Apply the same pressure-placement update used by retrieval state evaluation for a setup refresh test.   |
    // --------------------------------------------------------------------------------------------------------|
    const fit_interval_index = case.aerosol.interval_index_1based;
    const half_thickness = 0.5 * (case.aerosol.bottom_pressure_hpa - case.aerosol.top_pressure_hpa);
    const top_pressure_hpa = mid_pressure_hpa - half_thickness;
    const bottom_pressure_hpa = mid_pressure_hpa + half_thickness;

    case.aerosol.top_pressure_hpa = top_pressure_hpa;
    case.aerosol.bottom_pressure_hpa = bottom_pressure_hpa;

    var updated = false;
    for (intervals) |*interval| {
        const interval_index = interval.index_1based;

        if (interval_index == fit_interval_index) {
            interval.top_pressure_hpa = top_pressure_hpa;
            interval.bottom_pressure_hpa = bottom_pressure_hpa;
            updated = true;
            continue;
        }

        if (interval_index + 1 == fit_interval_index) {
            interval.bottom_pressure_hpa = top_pressure_hpa;
            continue;
        }

        if (interval_index == fit_interval_index + 1) {
            interval.top_pressure_hpa = bottom_pressure_hpa;
        }
    }

    if (!updated) return error.InvalidStateSpec;
}

fn expectEqualF64Slices(expected: []const f64, actual: []const f64) !void {
    // expectEqualF64Slices -----------------------------------------------------------------------------------|
    // Compare deterministic setup rows exactly; both paths use the same prepared profile samples.             |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_value, actual_value| {
        try std.testing.expectEqual(expected_value, actual_value);
    }
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
