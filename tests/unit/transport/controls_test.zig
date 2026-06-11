const std = @import("std");

const internal = @import("internal");

const controls = internal.transport.controls;
const jacobian_states = internal.transport.jacobian_states;

// ControlLayoutEvidence --------------------------------------------------------------------------------------|
// Compile-time layout pins for transport control rows copied from the old RTM control contract.               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] threshold_size    : usize                                                                          |
// [ 8..15] controls_size     : usize                                                                          |
// [16..23] solve_config_size : usize                                                                          |
const ControlLayoutEvidence = struct {
    threshold_size: usize,
    controls_size: usize,
    solve_config_size: usize,
};
// ------------------------------------------------------------------------------------------------------------|

const old_route_layout = ControlLayoutEvidence{
    .threshold_size = 64,
    .controls_size = 72,
    .solve_config_size = 80,
};

test "transport controls keep old route defaults and layout" {
    const thresholds = controls.PerformanceThresholds{};
    const default_controls = controls.TransportControls.default_vendor;

    try std.testing.expectEqual(old_route_layout.threshold_size, @sizeOf(controls.PerformanceThresholds));
    try std.testing.expectEqual(old_route_layout.controls_size, @sizeOf(controls.TransportControls));
    try std.testing.expectEqual(old_route_layout.solve_config_size, @sizeOf(controls.SolveConfig));

    try std.testing.expectEqual(@as(u16, 0), thresholds.num_orders_max);
    try std.testing.expectEqual(@as(u16, 2), thresholds.fourier_floor_scalar);
    try std.testing.expect(thresholds.fourier_order_cap == null);
    try std.testing.expect(thresholds.aerosol_tangent_order_cap == null);
    try std.testing.expectEqual(@as(f64, 3.0e-14), thresholds.fourier_tail_reflectance_epsilon);
    try std.testing.expectEqual(@as(f64, 1.0e-6), thresholds.threshold_conv_first);
    try std.testing.expectEqual(@as(f64, 1.0e-4), thresholds.threshold_conv_mult);
    try std.testing.expectEqual(@as(f64, 0.1), thresholds.threshold_doubl);
    try std.testing.expectEqual(@as(f64, 1.0e-12), thresholds.threshold_mul);
    try std.testing.expectEqual(@as(f64, 1.0e-8), thresholds.phase_function_truncation_threshold);

    try std.testing.expectEqual(controls.ScatteringMode.multiple, default_controls.scattering);
    try std.testing.expectEqual(@as(u16, 16), default_controls.n_streams);
    try std.testing.expectEqual(@as(u16, 8), default_controls.nGauss());
    try std.testing.expectEqual(@as(u32, 10), default_controls.supermatrixSize());
    try std.testing.expect(!default_controls.use_spherical_correction);
    try std.testing.expect(default_controls.integrate_source_function);
    try std.testing.expect(default_controls.renorm_phase_function);
}

test "transport controls validate old LABOS stream counts" {
    for ([_]u16{ 4, 6, 8, 16, 20 }) |n_streams| {
        try (controls.TransportControls{ .n_streams = n_streams }).validate();
    }

    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        (controls.TransportControls{ .n_streams = 3 }).validate(),
    );
    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        (controls.TransportControls{ .n_streams = 12 }).validate(),
    );
    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        (controls.TransportControls{ .n_streams = 18 }).validate(),
    );
}

test "performance thresholds reject nonpositive and nonfinite gates" {
    try (controls.PerformanceThresholds{}).validate();

    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        (controls.PerformanceThresholds{ .threshold_mul = 0.0 }).validate(),
    );
    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        (controls.PerformanceThresholds{ .threshold_doubl = -1.0 }).validate(),
    );
    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        (controls.PerformanceThresholds{ .threshold_conv_first = std.math.nan(f64) }).validate(),
    );
    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        (controls.PerformanceThresholds{ .fourier_tail_reflectance_epsilon = std.math.inf(f64) }).validate(),
    );
}

test "performance thresholds keep old order and Fourier cap helpers" {
    const uncapped = controls.PerformanceThresholds{};
    const capped = controls.PerformanceThresholds{
        .num_orders_max = 7,
        .fourier_order_cap = 3,
        .aerosol_tangent_order_cap = 2,
    };

    try std.testing.expectEqual(@as(u16, 15), uncapped.resolvedNumOrdersMax(-4.0));
    try std.testing.expectEqual(@as(u16, 17), uncapped.resolvedNumOrdersMax(2.25));
    try std.testing.expectEqual(@as(u16, 7), capped.resolvedNumOrdersMax(100.0));

    try std.testing.expectEqual(@as(usize, 9), uncapped.cappedFourierMax(9));
    try std.testing.expectEqual(@as(usize, 3), capped.cappedFourierMax(9));
    try std.testing.expectEqual(@as(usize, 2), capped.cappedFourierMax(2));

    try std.testing.expect(capped.shouldEvaluateAerosolTangent(2));
    try std.testing.expect(!capped.shouldEvaluateAerosolTangent(3));
    try std.testing.expect(uncapped.shouldEvaluateAerosolTangent(100));
}

test "prepare solve config validates controls and sanitizes Jacobian state mask" {
    const prepared = try controls.prepareSolveConfig(.{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = 0xff,
        .controls = .{ .n_streams = 16 },
    });

    try std.testing.expectEqual(controls.DerivativeMode.semi_analytical, prepared.derivative_mode);
    try std.testing.expectEqual(jacobian_states.all_states_mask, prepared.derivative_state_mask);
    try std.testing.expectEqual(@as(u16, 16), prepared.controls.n_streams);

    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        controls.prepareSolveConfig(.{ .controls = .{ .n_streams = 12 } }),
    );
}
