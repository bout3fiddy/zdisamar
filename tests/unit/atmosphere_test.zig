const std = @import("std");
const internal = @import("internal");
const AtmosphereModel = internal.atmosphere;

const Atmosphere = AtmosphereModel.Atmosphere;
const VerticalInterval = AtmosphereModel.VerticalInterval;
const Subcolumn = AtmosphereModel.Subcolumn;
const FractionControl = AtmosphereModel.FractionControl;

test "atmosphere validates profile source and positive surface pressure" {
    try (Atmosphere{
        .layer_count = 48,
        .profile_source = .{ .asset = .{ .name = "us_standard_profile" } },
        .surface_pressure_hpa = 1013.0,
    }).validate();

    try std.testing.expectError(
        error.InvalidRequest,
        (Atmosphere{ .surface_pressure_hpa = -1.0 }).validate(),
    );
    try std.testing.expectError(
        error.InvalidRequest,
        (Atmosphere{
            .has_aerosols = true,
            .layer_count = 0,
        }).validate(),
    );
    try (Atmosphere{
        .layer_count = 48,
        .sublayer_divisions = 12,
    }).validate();
}

test "atmosphere accepts explicit pressure-bounded intervals and fit interval state" {
    try (Atmosphere{
        .layer_count = 2,
        .interval_grid = .{
            .semantics = .explicit_pressure_bounds,
            .fit_interval_index_1based = 2,
            .intervals = &.{
                VerticalInterval{
                    .index_1based = 1,
                    .top_pressure_hpa = 120.0,
                    .bottom_pressure_hpa = 450.0,
                    .top_altitude_km = 12.0,
                    .bottom_altitude_km = 6.5,
                    .altitude_divisions = 2,
                },
                VerticalInterval{
                    .index_1based = 2,
                    .top_pressure_hpa = 450.0,
                    .bottom_pressure_hpa = 1013.0,
                    .top_altitude_km = 6.5,
                    .bottom_altitude_km = 0.0,
                    .altitude_divisions = 4,
                },
            },
        },
    }).validate();
}

test "atmosphere rejects malformed interval and subcolumn metadata" {
    try std.testing.expectError(
        error.InvalidRequest,
        (Atmosphere{
            .interval_grid = .{
                .semantics = .explicit_pressure_bounds,
                .fit_interval_index_1based = 2,
                .intervals = &.{
                    VerticalInterval{
                        .index_1based = 1,
                        .top_pressure_hpa = 700.0,
                        .bottom_pressure_hpa = 500.0,
                        .altitude_divisions = 2,
                    },
                },
            },
        }).validate(),
    );
    try std.testing.expectError(
        error.InvalidRequest,
        (Atmosphere{
            .layer_count = 1,
            .interval_grid = .{
                .semantics = .explicit_pressure_bounds,
                .intervals = &.{
                    VerticalInterval{
                        .index_1based = 1,
                        .top_pressure_hpa = 400.0,
                        .bottom_pressure_hpa = 900.0,
                        .top_altitude_km = 7.0,
                        .altitude_divisions = 2,
                    },
                },
            },
        }).validate(),
    );
    try std.testing.expectError(
        error.InvalidRequest,
        (Atmosphere{
            .layer_count = 2,
            .interval_grid = .{
                .semantics = .explicit_pressure_bounds,
                .intervals = &.{
                    VerticalInterval{
                        .index_1based = 1,
                        .top_pressure_hpa = 150.0,
                        .bottom_pressure_hpa = 500.0,
                        .top_altitude_km = 12.0,
                        .bottom_altitude_km = 8.0,
                        .altitude_divisions = 2,
                    },
                    VerticalInterval{
                        .index_1based = 2,
                        .top_pressure_hpa = 500.0,
                        .bottom_pressure_hpa = 1013.0,
                        .top_altitude_km = 9.0,
                        .bottom_altitude_km = 0.0,
                        .altitude_divisions = 2,
                    },
                },
            },
        }).validate(),
    );
    try std.testing.expectError(
        error.InvalidRequest,
        (Atmosphere{
            .layer_count = 2,
            .interval_grid = .{
                .semantics = .explicit_pressure_bounds,
                .intervals = &.{
                    VerticalInterval{
                        .index_1based = 1,
                        .top_pressure_hpa = 150.0,
                        .bottom_pressure_hpa = 500.0,
                        .top_altitude_km = 12.0,
                        .bottom_altitude_km = 8.0,
                        .altitude_divisions = 2,
                    },
                    VerticalInterval{
                        .index_1based = 2,
                        .top_pressure_hpa = 550.0,
                        .bottom_pressure_hpa = 1013.0,
                        .top_altitude_km = 8.0,
                        .bottom_altitude_km = 0.0,
                        .altitude_divisions = 2,
                    },
                },
            },
        }).validate(),
    );
    try std.testing.expectError(
        error.InvalidRequest,
        (Atmosphere{
            .layer_count = 1,
            .subcolumns = .{
                .enabled = true,
                .subcolumns = &.{
                    Subcolumn{
                        .index_1based = 1,
                        .label = .boundary_layer,
                        .bottom_altitude_km = 2.0,
                        .top_altitude_km = 1.0,
                    },
                },
            },
        }).validate(),
    );
}

fn cloneFractionControlWithAllocator(allocator: std.mem.Allocator) !void {
    const control: FractionControl = .{
        .enabled = true,
        .target = .aerosol,
        .kind = .wavel_dependent,
        .threshold_cloud_fraction = 0.25,
        .threshold_variance = 0.1,
        .wavelengths_nm = &.{ 760.0, 761.0 },
        .values = &.{ 0.20, 0.60 },
        .apriori_values = &.{ 0.25, 0.55 },
        .variance_values = &.{ 0.01, 0.04 },
    };

    var cloned = try control.clone(allocator);
    defer cloned.deinitOwned(allocator);

    try std.testing.expect(cloned.owns_arrays);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), cloned.valueAtWavelength(760.5), 1.0e-12);
}

test "fraction control clone cleans up across allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneFractionControlWithAllocator,
        .{},
    );
}

test "fraction control rejects non-monotonic wavelength grids" {
    try std.testing.expectError(
        error.InvalidRequest,
        (FractionControl{
            .enabled = true,
            .target = .aerosol,
            .kind = .wavel_dependent,
            .wavelengths_nm = &.{ 761.0, 760.0 },
            .values = &.{ 0.25, 0.75 },
        }).validate(),
    );
}
