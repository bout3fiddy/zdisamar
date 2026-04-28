const std = @import("std");
const internal = @import("internal");

const common = internal.kernels.transport.common;
const phase_functions = internal.kernels.optics.prepare.phase_functions;
const prepareRoute = common.prepareRoute;
const fillSourceInterfacesFromLayers = common.fillSourceInterfacesFromLayers;

test "prepare route resolves families and keeps derivative mode explicit" {
    const adding_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
        .rtm_controls = .{ .use_adding = true },
    });
    try std.testing.expectEqual(common.TransportFamily.adding, adding_route.family);
    try std.testing.expectEqual(common.DerivativeMode.semi_analytical, adding_route.derivative_mode);
    try std.testing.expectEqual(common.DerivativeSemantics.analytical, adding_route.derivativeSemantics());
    try std.testing.expectEqual(common.ImplementationClass.baseline, adding_route.family.classification());
    try std.testing.expectEqualStrings("baseline_adding", adding_route.family.provenanceLabel());

    const adding_no_scattering_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .scattering = .none,
        },
    });
    try std.testing.expectEqual(common.TransportFamily.adding, adding_no_scattering_route.family);
    try std.testing.expectEqual(common.ScatteringMode.none, adding_no_scattering_route.rtm_controls.scattering);

    const nadir_default_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(common.TransportFamily.labos, nadir_default_route.family);

    const labos_route = try prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(common.TransportFamily.labos, labos_route.family);
    try std.testing.expectEqual(common.DerivativeMode.semi_analytical, labos_route.derivative_mode);
    try std.testing.expectEqual(common.DerivativeSemantics.analytical, labos_route.derivativeSemantics());
    try std.testing.expectEqualStrings("baseline_labos", labos_route.family.provenanceLabel());

    const twenty_stream_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{ .n_streams = 20 },
    });
    try std.testing.expectEqual(@as(u16, 20), twenty_stream_route.rtm_controls.n_streams);

    try std.testing.expectError(common.Error.UnsupportedExecutionMode, prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .polarized,
        .derivative_mode = .none,
        .rtm_controls = .{ .use_adding = true },
    }));
    try std.testing.expectError(common.Error.UnsupportedRadiativeTransferControls, prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .scattering = .single,
        },
    }));
    try std.testing.expectError(common.Error.UnsupportedDerivativeMode, prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .analytical_plugin,
    }));
}

test "source interface builder preserves the top boundary weight and halves the bottom boundary weight" {
    const layers = [_]common.LayerInput{
        .{
            .scattering_optical_depth = 0.20,
            .phase_coefficients = phase_functions.phaseCoefficientsFromLegacy(.{ 1.0, 0.10, 0.0, 0.0 }),
        },
        .{
            .scattering_optical_depth = 0.40,
            .phase_coefficients = phase_functions.phaseCoefficientsFromLegacy(.{ 1.0, 0.30, 0.0, 0.0 }),
        },
    };
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    fillSourceInterfacesFromLayers(&layers, &source_interfaces);

    try std.testing.expectApproxEqAbs(@as(f64, 0.20), source_interfaces[0].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), source_interfaces[1].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.20), source_interfaces[2].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[0].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[1].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[2].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.10), source_interfaces[0].phase_coefficients_above[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.30), source_interfaces[1].phase_coefficients_above[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.30), source_interfaces[2].phase_coefficients_above[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[0].phase_coefficients_below[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.10), source_interfaces[1].phase_coefficients_below[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.30), source_interfaces[2].phase_coefficients_below[1], 1.0e-12);
}
