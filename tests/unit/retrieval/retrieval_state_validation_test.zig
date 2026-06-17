const std = @import("std");
const internal = @import("internal");

const retrieval = internal.retrieval.root;

test "fixed retrieval state rejects invalid scalar and pressure placement" {
    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    const second = [_]f64{ 0.0, 0.0 };
    const pressure_altitude_profile = retrieval.PressureAltitudeProfile{
        .altitude_km = altitude_km[0..],
        .pressure_hpa = pressure_hpa[0..],
        .second = second[0..],
    };

    const invalid_aod: retrieval.RetrievalState = .{
        .aerosol_optical_depth = .{
            .initial = 0.3,
            .prior = 0.2,
            .variance = -4.0,
            .lower_bound = 0.0,
            .upper_bound = 1.0,
        },
        .aerosol_layer_mid_pressure = .{
            .scalar = .{
                .initial = 850.0,
                .prior = 850.0,
                .variance = 100.0,
                .lower_bound = 600.0,
                .upper_bound = 1000.0,
            },
            .placement = .{
                .thickness_hpa = 10.0,
                .interval_index_1based = 1,
                .pressure_altitude_profile = &pressure_altitude_profile,
            },
        },
    };
    try std.testing.expectError(error.InvalidRetrievalState, retrieval.validateRetrievalState(invalid_aod));

    const invalid_pressure: retrieval.RetrievalState = .{
        .aerosol_optical_depth = .{
            .initial = 0.3,
            .prior = 0.2,
            .variance = 4.0,
            .lower_bound = 0.0,
            .upper_bound = 1.0,
        },
        .aerosol_layer_mid_pressure = .{
            .scalar = .{
                .initial = 850.0,
                .prior = 850.0,
                .variance = 100.0,
                .lower_bound = 600.0,
                .upper_bound = 1000.0,
            },
            .placement = .{
                .thickness_hpa = std.math.nan(f64),
                .interval_index_1based = 1,
                .pressure_altitude_profile = &pressure_altitude_profile,
            },
        },
    };
    try std.testing.expectError(error.InvalidRetrievalState, retrieval.validateRetrievalState(invalid_pressure));
}
