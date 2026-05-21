const std = @import("std");
const internal = @import("internal");

const atmospheric_budget = internal.output.atmospheric_budget;
const Scene = internal.Scene;
const PreparedLayer = internal.forward_model.optical_properties.PreparedLayer;
const PreparedOpticalState = internal.forward_model.optical_properties.PreparedOpticalState;

test "atmospheric budget rows expose layer absorption and scattering components" {
    const allocator = std.testing.allocator;

    var layers = [_]PreparedLayer{.{
        .layer_index = 2,
        .altitude_km = 4.0,
        .pressure_hpa = 640.0,
        .temperature_k = 250.0,
        .number_density_cm3 = 1.5e19,
        .continuum_cross_section_cm2_per_molecule = 0.0,
        .line_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_cross_section_cm2_per_molecule = 0.0,
        .cia_optical_depth = 0.02,
        .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
        .gas_optical_depth = 0.21,
        .gas_scattering_optical_depth = 0.01,
        .aerosol_optical_depth = 0.10,
        .layer_single_scatter_albedo = 0.0,
        .depolarization_factor = 0.0,
        .optical_depth = 0.33,
        .top_altitude_km = 5.0,
        .bottom_altitude_km = 3.0,
        .top_pressure_hpa = 500.0,
        .bottom_pressure_hpa = 780.0,
        .interval_index_1based = 2,
    }};
    var prepared = std.mem.zeroInit(PreparedOpticalState, .{
        .layers = layers[0..],
        .continuum_points = &.{},
        .aerosol_single_scatter_albedo = 0.8,
        .aerosol_reference_wavelength_nm = 760.0,
    });
    const scene: Scene = .{};
    const wavelengths_nm = [_]f64{ 760.0, 761.0 };

    const rows = try atmospheric_budget.build(
        allocator,
        &scene,
        &prepared,
        wavelengths_nm[0..],
    );
    defer allocator.free(rows);

    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(@as(u32, 2), rows[0].layer_index);
    try std.testing.expectEqual(@as(u32, 2), rows[0].interval_index_1based);
    try std.testing.expectEqual(atmospheric_budget.SupportRowKind.physical, rows[0].support_row_kind);
    try std.testing.expectApproxEqAbs(@as(f64, 0.20), rows[0].gas_absorption_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), rows[0].gas_scattering_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.08), rows[0].aerosol_scattering_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.02), rows[0].aerosol_absorption_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.24), rows[0].total_absorption_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.09), rows[0].total_scattering_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.33), rows[0].total_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.09 / 0.33), rows[0].single_scatter_albedo, 1.0e-12);
}
