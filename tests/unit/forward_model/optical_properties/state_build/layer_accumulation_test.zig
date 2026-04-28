const std = @import("std");
const internal = @import("internal");

const preparation = internal.forward_model.optical_properties;
const preparation_internal = preparation.internal;
const ReferenceData = internal.reference_data;
const ClimatologyProfile = internal.reference.climatology.ClimatologyProfile;

const boltzmann_hpa_cm3_per_k = preparation_internal.boltzmann_hpa_cm3_per_k;
const pressureFromParitySupportBounds = preparation_internal.pressureFromParitySupportBounds;
const paritySupportThermodynamicsFromProfile = preparation_internal.paritySupportThermodynamicsFromProfile;

test "parity support-row pressure honors realized support bounds" {
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.3),
        pressureFromParitySupportBounds(20.0, 20.0, 0.3, 0.3, 20.0),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 316.22776601683796),
        pressureFromParitySupportBounds(0.0, 10.0, 1000.0, 100.0, 5.0),
        1.0e-9,
    );
}

test "parity support-row thermodynamics follow the profile spline contract" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ReferenceData.ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 295.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 1.0,
                .pressure_hpa = 860.0,
                .temperature_k = 271.0,
                .air_number_density_cm3 = 2.0e19,
            },
            .{
                .altitude_km = 2.0,
                .pressure_hpa = 690.0,
                .temperature_k = 248.0,
                .air_number_density_cm3 = 1.6e19,
            },
            .{
                .altitude_km = 3.0,
                .pressure_hpa = 540.0,
                .temperature_k = 242.0,
                .air_number_density_cm3 = 1.2e19,
            },
        })),
    };

    const altitude_km = 1.4;
    const state = paritySupportThermodynamicsFromProfile(&profile, altitude_km);
    const legacy_pressure = pressureFromParitySupportBounds(1.0, 2.0, 860.0, 690.0, altitude_km);

    try std.testing.expectApproxEqAbs(
        profile.interpolatePressureLogSpline(altitude_km),
        state.pressure_hpa,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        profile.interpolateTemperatureSpline(altitude_km),
        state.temperature_k,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        state.pressure_hpa / state.temperature_k / boltzmann_hpa_cm3_per_k,
        state.density_cm3,
        1.0e-6,
    );
    try std.testing.expect(@abs(state.pressure_hpa - legacy_pressure) > 1.0e-3);
}
