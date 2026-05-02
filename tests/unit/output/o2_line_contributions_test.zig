const std = @import("std");
const internal = @import("internal");

const ReferenceData = internal.reference_data;
const PreparedOpticalState = internal.forward_model.optical_properties.PreparedOpticalState;
const o2_line_contributions = internal.output.o2_line_contributions;

fn lineList(lines: []ReferenceData.SpectroscopyLine) ReferenceData.SpectroscopyLineList {
    return .{
        .lines = lines,
        .lines_sorted_ascending = true,
    };
}

fn preparedState(list: ReferenceData.SpectroscopyLineList) PreparedOpticalState {
    return std.mem.zeroInit(PreparedOpticalState, .{
        .layers = &.{},
        .continuum_points = &.{},
        .spectroscopy_lines = list,
        .effective_temperature_k = 296.0,
        .effective_pressure_hpa = 1013.25,
    });
}

fn baseO2Line() ReferenceData.SpectroscopyLine {
    return .{
        .gas_index = 7,
        .isotope_number = 1,
        .center_wavelength_nm = 760.0,
        .center_wavenumber_cm1 = 1.0e7 / 760.0,
        .line_strength_cm2_per_molecule = 1.0e-22,
        .air_half_width_nm = 0.01,
        .air_half_width_cm1 = 0.15,
        .temperature_exponent = 0.7,
        .lower_state_energy_cm1 = 100.0,
        .pressure_shift_nm = 0.0,
        .pressure_shift_cm1 = 0.0,
        .line_mixing_coefficient = 0.0,
    };
}

test "O2 line contribution rows expose weak line cross-section components" {
    const allocator = std.testing.allocator;
    var lines = [_]ReferenceData.SpectroscopyLine{baseO2Line()};
    const prepared = preparedState(lineList(lines[0..]));
    const wavelengths_nm = [_]f64{760.0};

    var table = try o2_line_contributions.build(
        allocator,
        &prepared,
        wavelengths_nm[0..],
        8,
    );
    defer table.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), table.rows.len);
    try std.testing.expectEqual(@as(usize, 1), table.total_row_count);
    try std.testing.expect(!table.truncated);
    try std.testing.expectEqual(std.math.maxInt(u32), table.rows[0].profile_node_index);
    try std.testing.expect(std.math.isNan(table.rows[0].altitude_km));
    try std.testing.expectEqual(o2_line_contributions.O2LineRowKind.weak_line, table.rows[0].row_kind);
    try std.testing.expectEqual(o2_line_contributions.O2LineStatus.weak_included, table.rows[0].status);
    try std.testing.expectEqual(@as(u32, 0), table.rows[0].line_index);
    try std.testing.expectEqual(@as(u16, 7), table.rows[0].gas_index);
    try std.testing.expectEqual(@as(u8, 1), table.rows[0].isotope_number);
    try std.testing.expectApproxEqAbs(@as(f64, 760.0), table.rows[0].center_wavelength_nm, 1.0e-12);
    try std.testing.expect(table.rows[0].weak_line_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(table.rows[0].total_sigma_cm2_per_molecule > 0.0);
}

test "O2 line contribution rows use spectroscopy profile thermodynamic states when present" {
    const allocator = std.testing.allocator;
    var lines = [_]ReferenceData.SpectroscopyLine{baseO2Line()};
    var altitudes_km = [_]f64{ 0.0, 8.0 };
    var pressures_hpa = [_]f64{ 1013.25, 350.0 };
    var temperatures_k = [_]f64{ 288.0, 235.0 };
    const prepared = std.mem.zeroInit(PreparedOpticalState, .{
        .layers = &.{},
        .continuum_points = &.{},
        .spectroscopy_lines = lineList(lines[0..]),
        .spectroscopy_profile_altitudes_km = altitudes_km[0..],
        .spectroscopy_profile_pressures_hpa = pressures_hpa[0..],
        .spectroscopy_profile_temperatures_k = temperatures_k[0..],
        .effective_temperature_k = 0.0,
        .effective_pressure_hpa = 0.0,
    });
    const wavelengths_nm = [_]f64{760.0};

    var table = try o2_line_contributions.build(
        allocator,
        &prepared,
        wavelengths_nm[0..],
        8,
    );
    defer table.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), table.rows.len);
    try std.testing.expectEqual(@as(u32, 0), table.rows[0].profile_node_index);
    try std.testing.expectEqual(@as(u32, 1), table.rows[1].profile_node_index);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), table.rows[0].altitude_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), table.rows[1].altitude_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 288.0), table.rows[0].temperature_k, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 350.0), table.rows[1].pressure_hpa, 1.0e-12);
}

test "O2 line contribution table reports truncation without dropping total row count" {
    const allocator = std.testing.allocator;
    var lines = [_]ReferenceData.SpectroscopyLine{baseO2Line()};
    const prepared = preparedState(lineList(lines[0..]));
    const wavelengths_nm = [_]f64{ 760.0, 760.1 };

    var table = try o2_line_contributions.build(
        allocator,
        &prepared,
        wavelengths_nm[0..],
        1,
    );
    defer table.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), table.rows.len);
    try std.testing.expectEqual(@as(usize, 2), table.total_row_count);
    try std.testing.expect(table.truncated);
}

test "O2 line contribution table rejects empty requests" {
    const allocator = std.testing.allocator;
    var lines = [_]ReferenceData.SpectroscopyLine{baseO2Line()};
    const prepared = preparedState(lineList(lines[0..]));

    try std.testing.expectError(
        error.EmptyWavelengths,
        o2_line_contributions.build(allocator, &prepared, &.{}, 1),
    );
    try std.testing.expectError(
        error.InvalidRowLimit,
        o2_line_contributions.build(allocator, &prepared, &.{760.0}, 0),
    );
}
