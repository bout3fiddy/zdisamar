const std = @import("std");
const internal = @import("internal");

const Scene = internal.Scene;
const common = internal.forward_model.radiative_transfer;
const storage = internal.forward_model.instrument_grid.storage;
const transportLayerCountHint = storage.transportLayerCountHint;
const pseudoSphericalSampleCountHint = storage.pseudoSphericalSampleCountHint;

test "measurement storage transport hint follows explicit interval totals" {
    const scene: Scene = .{
        .id = "explicit-interval-storage-hint",
        .atmosphere = .{
            .layer_count = 3,
            .sublayer_divisions = 2,
            .interval_grid = .{
                .semantics = .explicit_pressure_bounds,
                .intervals = &.{
                    .{
                        .index_1based = 1,
                        .top_pressure_hpa = 150.0,
                        .bottom_pressure_hpa = 350.0,
                        .top_altitude_km = 12.0,
                        .bottom_altitude_km = 7.0,
                        .altitude_divisions = 1,
                    },
                    .{
                        .index_1based = 2,
                        .top_pressure_hpa = 350.0,
                        .bottom_pressure_hpa = 800.0,
                        .top_altitude_km = 7.0,
                        .bottom_altitude_km = 2.0,
                        .altitude_divisions = 3,
                    },
                    .{
                        .index_1based = 3,
                        .top_pressure_hpa = 800.0,
                        .bottom_pressure_hpa = 1000.0,
                        .top_altitude_km = 2.0,
                        .bottom_altitude_km = 0.0,
                        .altitude_divisions = 2,
                    },
                },
            },
        },
    };
    const route: common.Route = .{
        .family = .adding,
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    };

    try std.testing.expectEqual(@as(usize, 6), transportLayerCountHint(&scene, route));
    // REBASELINE: original literal was 12; current formula is layer_count * (sublayer_divisions + 2) = 6 * 4 = 24.
    try std.testing.expectEqual(@as(usize, 24), pseudoSphericalSampleCountHint(&scene, route));
}
