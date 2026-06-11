const std = @import("std");

const internal = @import("internal");

const phase_table = internal.setup.phase_table;

test "PhaseTable keeps old fixed coefficient layout" {
    try std.testing.expectEqual(@as(usize, 1224), @sizeOf(phase_table.PhaseTable));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_table.PhaseTable));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(phase_table.PhaseTable, "aerosol_phase_coefficients"));
    try std.testing.expectEqual(@as(usize, 1208), @offsetOf(phase_table.PhaseTable, "aerosol_phase_max_index"));
    try std.testing.expectEqual(@as(usize, 1216), @offsetOf(phase_table.PhaseTable, "aerosol_asymmetry_factor"));
}

test "HG phase coefficients match old scalar formula" {
    const coefficients = phase_table.hgPhaseCoefficientsWithThreshold(0.7, 1.0e-8);
    const expected = scalarHgCoefficients(0.7, 1.0e-8);

    try std.testing.expectEqual(@as(usize, 39), phase_table.maxPhaseCoefficientIndex(&coefficients));
    for (0..phase_table.coefficient_count) |index| {
        try std.testing.expectApproxEqAbs(expected[index], coefficients[index], 1.0e-14);
    }
}

test "PhaseTable build retains reference aerosol phase support" {
    const table = phase_table.build(internal.input.defaults.referenceCase());

    try std.testing.expectApproxEqAbs(0.7, table.aerosol_asymmetry_factor, 0.0);
    try std.testing.expectEqual(@as(usize, 39), table.aerosol_phase_max_index);
    try std.testing.expectApproxEqAbs(1.0, table.aerosol_phase_coefficients[0], 0.0);
    try std.testing.expectApproxEqAbs(2.1, table.aerosol_phase_coefficients[1], 1.0e-14);
    try std.testing.expectApproxEqAbs(2.4499999999999997, table.aerosol_phase_coefficients[2], 1.0e-14);
    try std.testing.expectApproxEqAbs(2.4009999999999994, table.aerosol_phase_coefficients[3], 1.0e-14);
    try std.testing.expect(table.aerosol_phase_coefficients[40] == 0.0);
}

test "zero and isotropic aerosol phase rows keep only l0 active" {
    const zero = phase_table.zeroPhaseCoefficients();
    try std.testing.expectEqual(@as(usize, 0), phase_table.maxPhaseCoefficientIndex(&zero));
    try std.testing.expectApproxEqAbs(1.0, zero[0], 0.0);

    const isotropic = phase_table.hgPhaseCoefficients(0.0);
    try std.testing.expectEqual(@as(usize, 0), phase_table.maxPhaseCoefficientIndex(&isotropic));
    try std.testing.expectApproxEqAbs(1.0, isotropic[0], 0.0);
    for (1..phase_table.coefficient_count) |index| {
        try std.testing.expectApproxEqAbs(0.0, isotropic[index], 0.0);
    }
}

fn scalarHgCoefficients(asymmetry_factor: f64, truncation_threshold: f64) [phase_table.coefficient_count]f64 {
    // scalarHgCoefficients -----------------------------------------------------------------------------------|
    // Test-local reference for old `phase_functions.zig` `hgPhaseCoefficientsWithThreshold`.                  |
    // --------------------------------------------------------------------------------------------------------|
    var coefficients = [_]f64{0.0} ** phase_table.coefficient_count;
    coefficients[0] = 1.0;

    const truncation_g = @abs(asymmetry_factor);
    if (truncation_g <= 0.0) return coefficients;

    const threshold = @max(truncation_threshold, 0.0);
    var normalized_tail: f64 = 1.0;
    for (1..phase_table.coefficient_count) |index| {
        const order: f64 = @floatFromInt(index);
        normalized_tail *= truncation_g * (2.0 * order - 1.0) / (2.0 * order + 1.0);
        if (normalized_tail < threshold) break;
        coefficients[index] =
            (2.0 * order + 1.0) *
            std.math.pow(f64, asymmetry_factor, order);
    }

    return coefficients;
}
