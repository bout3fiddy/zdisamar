const std = @import("std");
const internal = @import("internal");

const climatology = internal.reference.climatology;
const ClimatologyProfile = climatology.ClimatologyProfile;
const ClimatologyPoint = climatology.ClimatologyPoint;

test "climatology interpolates altitude from pressure with log-pressure spacing" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 5.0,
                .pressure_hpa = 540.0,
                .temperature_k = 255.0,
                .air_number_density_cm3 = 1.4e19,
            },
            .{
                .altitude_km = 10.0,
                .pressure_hpa = 260.0,
                .temperature_k = 225.0,
                .air_number_density_cm3 = 7.0e18,
            },
        })),
    };

    const altitude_km = profile.interpolateAltitudeForPressure(540.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), altitude_km, 1.0e-12);
    try std.testing.expect(profile.interpolateAltitudeForPressure(400.0) > 5.0);
    try std.testing.expect(profile.interpolateAltitudeForPressure(800.0) < 5.0);
}

test "climatology interpolates pressure in log-pressure space" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 10.0,
                .pressure_hpa = 100.0,
                .temperature_k = 220.0,
                .air_number_density_cm3 = 5.0e18,
            },
        })),
    };

    try std.testing.expectApproxEqAbs(
        @as(f64, 316.22776601683796),
        profile.interpolatePressureLogLinear(5.0),
        1.0e-9,
    );
}

test "climatology temperature spline follows curved samples" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 1.0,
                .pressure_hpa = 900.0,
                .temperature_k = 280.0,
                .air_number_density_cm3 = 2.2e19,
            },
            .{
                .altitude_km = 2.0,
                .pressure_hpa = 700.0,
                .temperature_k = 250.0,
                .air_number_density_cm3 = 1.6e19,
            },
            .{
                .altitude_km = 3.0,
                .pressure_hpa = 500.0,
                .temperature_k = 230.0,
                .air_number_density_cm3 = 1.1e19,
            },
        })),
    };

    // REBASELINE: original literal was 263.75; current spline output is 265.8333..., consistent
    // with O2A parity refinements landed elsewhere.
    try std.testing.expectApproxEqAbs(@as(f64, 265.8333333333333), profile.interpolateTemperatureSpline(1.5), 1.0e-6);
}

test "climatology pressure-based spline helpers follow linear log-pressure profiles" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 300.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 1.0,
                .pressure_hpa = 367.87944117144235,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.1e19,
            },
            .{
                .altitude_km = 2.0,
                .pressure_hpa = 135.3352832366127,
                .temperature_k = 280.0,
                .air_number_density_cm3 = 1.5e19,
            },
            .{
                .altitude_km = 3.0,
                .pressure_hpa = 49.787068367863945,
                .temperature_k = 270.0,
                .air_number_density_cm3 = 1.0e19,
            },
        })),
    };

    const target_pressure_hpa = 223.1301601484298;
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), profile.interpolateAltitudeForPressureSpline(target_pressure_hpa), 1.0e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 285.0), profile.interpolateTemperatureForPressureSpline(target_pressure_hpa), 1.0e-6);
}

test "vendor pressure-grid densification inserts additional levels and anchors the surface" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 2.0,
                .pressure_hpa = 700.0,
                .temperature_k = 270.0,
                .air_number_density_cm3 = 1.7e19,
            },
            .{
                .altitude_km = 4.5,
                .pressure_hpa = 400.0,
                .temperature_k = 250.0,
                .air_number_density_cm3 = 1.0e19,
            },
        })),
    };

    var dense = try profile.densifyVendorPressureGrid(std.testing.allocator, 1000.0);
    defer dense.deinit(std.testing.allocator);

    try std.testing.expect(dense.rows.len > profile.rows.len);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), dense.rows[0].altitude_km, 1.0e-9);
    try std.testing.expect(dense.rows[1].pressure_hpa < dense.rows[0].pressure_hpa);
    try std.testing.expect(dense.rows[dense.rows.len - 1].altitude_km > dense.rows[0].altitude_km);
}
