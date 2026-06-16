const std = @import("std");
const internal = @import("internal");

const retrieval = internal.retrieval.root;

test "retrieval state specs reject duplicate states and non-finite pressure thickness" {
    const duplicate_states = [_]retrieval.StateSpec{
        .{
            .state = .aerosol_optical_depth,
            .initial = 0.3,
            .prior = 0.2,
            .variance = 4.0,
            .lower_bound = 0.0,
            .upper_bound = 1.0,
        },
        .{
            .state = .aerosol_optical_depth,
            .initial = 0.4,
            .prior = 0.2,
            .variance = 4.0,
            .lower_bound = 0.0,
            .upper_bound = 1.0,
        },
    };
    try std.testing.expectError(error.InvalidStateSpec, retrieval.validateStateSpecs(&duplicate_states));
    try std.testing.expectError(
        error.InvalidStateCount,
        retrieval.validateStateSpecs(duplicate_states[0..1]),
    );

    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    const second = [_]f64{ 0.0, 0.0 };
    const pressure_state = [_]retrieval.StateSpec{
        .{
            .state = .aerosol_optical_depth,
            .initial = 0.3,
            .prior = 0.2,
            .variance = 4.0,
            .lower_bound = 0.0,
            .upper_bound = 1.0,
        },
        .{
            .state = .aerosol_layer_mid_pressure_hpa,
            .initial = 850.0,
            .prior = 850.0,
            .variance = 100.0,
            .lower_bound = 600.0,
            .upper_bound = 1000.0,
            .thickness_hpa = std.math.nan(f64),
            .interval_index_1based = 1,
            .pressure_altitude_profile = .{
                .altitude_km = altitude_km[0..],
                .pressure_hpa = pressure_hpa[0..],
                .second = second[0..],
            },
        },
    };
    try std.testing.expectError(error.InvalidStateSpec, retrieval.validateStateSpecs(&pressure_state));
}
