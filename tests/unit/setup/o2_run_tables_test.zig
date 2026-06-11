const std = @import("std");
const internal = @import("internal");

test "O2RunTables match WP1 baseline table evidence" {
    var tables = try internal.setup.o2_run_tables.buildReferenceO2RunTables(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 45), tables.layers.evidence_shape.layer_count);
    try std.testing.expectEqual(@as(usize, 226), tables.layers.evidence_shape.support_rows_per_probe_wavelength);
    try std.testing.expectEqual(@as(usize, 46), tables.layers.evidence_shape.rtm_quadrature_level_count);
    try std.testing.expectEqual(@as(usize, 180), tables.layers.evidence_shape.pseudo_spherical_sample_count);
    try std.testing.expectApproxEqAbs(1013.2499974119982, tables.layers.first_budget_pressure_hpa, 1.0e-12);
    try std.testing.expectApproxEqAbs(294.20205620757804, tables.layers.first_budget_temperature_k, 1.0e-12);

    try std.testing.expectEqual(@as(usize, 1314), tables.lines.rows.len);
    try std.testing.expectEqual(@as(usize, 101144), tables.lines.diagnostic_contribution_row_count);
    try std.testing.expectApproxEqAbs(759.5754324317322, tables.lines.first_center_wavelength_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(13165.249392, tables.lines.first_center_wavenumber_cm1, 1.0e-12);

    try std.testing.expectEqual(@as(usize, 16451), tables.cia.rows.len);
    try std.testing.expectEqual(@as(usize, 1130), tables.cia.diagnostic_row_count);
    try std.testing.expectApproxEqAbs(0.00314377591581326, tables.cia.first_probe_cia_optical_depth, 1.0e-18);

    try std.testing.expectApproxEqAbs(0.3, tables.aerosol.optical_depth, 0.0);
    try std.testing.expectApproxEqAbs(1.0, tables.aerosol.single_scatter_albedo, 0.0);
    try std.testing.expectEqual(@as(usize, 3), tables.phase.coefficient_count);
    try std.testing.expectEqual(@as(usize, 2501), tables.solar.rows.len);
}
