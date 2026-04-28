const std = @import("std");
const internal = @import("internal");

const errors = internal.common.errors;
const lut_controls = internal.common.lut_controls;
const Controls = lut_controls.Controls;
const CompatibilityKey = lut_controls.CompatibilityKey;

test "lut controls reject incomplete non-direct xsec settings" {
    try std.testing.expectError(errors.Error.InvalidRequest, (Controls{
        .xsec = .{ .mode = .generate },
    }).validate());
    try std.testing.expectError(errors.Error.InvalidRequest, (Controls{
        .xsec = .{ .mode = .consume },
    }).validate());
}

test "lut compatibility keys compare all scientific inputs explicitly" {
    const lhs: CompatibilityKey = .{
        .controls = .{
            .reflectance = .{ .reflectance_mode = .generate, .surface_albedo = 0.1 },
            .xsec = .{
                .mode = .consume,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 10,
                .pressure_grid_count = 20,
                .temperature_coefficient_count = 5,
                .pressure_coefficient_count = 10,
            },
        },
        .spectral_start_nm = 758.0,
        .spectral_end_nm = 770.0,
        .solar_zenith_deg = 60.0,
        .viewing_zenith_deg = 30.0,
        .relative_azimuth_deg = 120.0,
        .surface_albedo = 0.1,
        .instrument_line_fwhm_nm = 0.38,
        .high_resolution_step_nm = 0.01,
        .high_resolution_half_span_nm = 1.14,
        .lut_sampling_half_span_nm = 1.14,
    };
    var rhs = lhs;

    try lhs.validate();
    try rhs.validate();
    try std.testing.expect(lhs.matches(rhs));

    rhs.lut_sampling_half_span_nm = 1.5;
    try std.testing.expect(!lhs.matches(rhs));
}

test "lut compatibility keys tolerate numerically equivalent float inputs" {
    const lhs: CompatibilityKey = .{
        .controls = .{
            .reflectance = .{ .reflectance_mode = .generate, .surface_albedo = 0.1 },
            .xsec = .{
                .mode = .consume,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 10,
                .pressure_grid_count = 20,
                .temperature_coefficient_count = 5,
                .pressure_coefficient_count = 10,
            },
        },
        .spectral_start_nm = 758.0,
        .spectral_end_nm = 770.0,
        .nominal_sample_count = 0,
        .solar_zenith_deg = 60.0,
        .viewing_zenith_deg = 30.0,
        .relative_azimuth_deg = 120.0,
        .surface_albedo = 0.1,
        .instrument_line_fwhm_nm = 0.38,
        .high_resolution_step_nm = 0.01,
        .high_resolution_half_span_nm = 1.14,
        .lut_sampling_half_span_nm = 1.14,
    };
    var rhs = lhs;

    rhs.controls.reflectance.surface_albedo += 5.0e-13;
    rhs.controls.xsec.max_temperature_k += 1.0e-10;
    rhs.spectral_start_nm += 5.0e-13;
    rhs.relative_azimuth_deg += 5.0e-13;
    rhs.high_resolution_half_span_nm += 5.0e-13;

    try lhs.validate();
    try rhs.validate();
    try std.testing.expect(lhs.matches(rhs));

    rhs.instrument_line_fwhm_nm += 1.0e-6;
    try std.testing.expect(!lhs.matches(rhs));
}
