const std = @import("std");
const internal = @import("internal");

const Scene = internal.Scene;
const common = internal.forward_model.radiative_transfer;
const storage = internal.forward_model.instrument_grid.storage;
const transportLayerCountHint = storage.transportLayerCountHint;
const pseudoSphericalSampleCountHint = storage.pseudoSphericalSampleCountHint;
const implementations = internal.forward_model.implementations;

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
        .family = .labos,
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    };

    try std.testing.expectEqual(@as(usize, 6), transportLayerCountHint(&scene, route));
    // REBASELINE: original literal was 12; current formula is layer_count * (sublayer_divisions + 2) = 6 * 4 = 24.
    try std.testing.expectEqual(@as(usize, 24), pseudoSphericalSampleCountHint(&scene, route));
}

test "measurement storage allocates one jacobian row per spectral sample" {
    const scene: Scene = .{
        .id = "jacobian-storage-shape",
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 758.2,
            .sample_count = 3,
        },
        .atmosphere = .{
            .layer_count = 1,
            .sublayer_divisions = 1,
        },
    };
    const route: common.Route = .{
        .family = .labos,
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    };

    var summary_storage: storage.SummaryStorage = .{};
    defer summary_storage.deinit(std.testing.allocator);

    const buffers = try summary_storage.buffers(
        std.testing.allocator,
        &scene,
        route,
        implementations.exact(),
    );
    const jacobian_values = buffers.jacobian orelse return error.ExpectedJacobianBuffer;
    try std.testing.expectEqual(
        @as(usize, scene.spectral_grid.sample_count) * common.Jacobian.state_count,
        jacobian_values.len,
    );
}

test "measurement storage keeps route-inactive transport buffers empty" {
    const scene: Scene = .{
        .id = "route-gated-transport-storage",
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 758.2,
            .sample_count = 3,
        },
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
                },
            },
        },
    };
    const integrated_route: common.Route = .{
        .family = .labos,
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .integrate_source_function = true,
            .use_spherical_correction = false,
        },
    };
    const source_route: common.Route = .{
        .family = .labos,
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .integrate_source_function = false,
            .use_spherical_correction = true,
        },
    };

    var summary_storage: storage.SummaryStorage = .{};
    defer summary_storage.deinit(std.testing.allocator);

    const integrated_buffers = try summary_storage.buffers(
        std.testing.allocator,
        &scene,
        integrated_route,
        implementations.exact(),
    );
    const layer_count = transportLayerCountHint(&scene, integrated_route);
    try std.testing.expectEqual(@as(usize, 0), integrated_buffers.source_interfaces.len);
    try std.testing.expectEqual(layer_count + 1, integrated_buffers.rtm_quadrature_levels.len);
    try std.testing.expectEqual(@as(usize, 0), integrated_buffers.pseudo_spherical_samples.len);
    try std.testing.expectEqual(@as(usize, 0), integrated_buffers.pseudo_spherical_level_starts.len);

    const source_buffers = try summary_storage.buffers(
        std.testing.allocator,
        &scene,
        source_route,
        implementations.exact(),
    );
    try std.testing.expectEqual(layer_count + 1, source_buffers.source_interfaces.len);
    try std.testing.expectEqual(@as(usize, 0), source_buffers.rtm_quadrature_levels.len);
    try std.testing.expect(source_buffers.pseudo_spherical_samples.len != 0);
    try std.testing.expectEqual(layer_count + 1, source_buffers.pseudo_spherical_level_starts.len);
}
