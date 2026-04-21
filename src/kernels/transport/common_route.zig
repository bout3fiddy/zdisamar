//! Purpose:
//!   Resolve transport routes and derive interface helpers from the shared
//!   transport contract.

const std = @import("std");
const common = @import("common_types.zig");
const phase_functions = @import("../optics/prepare/phase_functions.zig");

pub fn prepareRoute(request: common.DispatchRequest) common.PrepareError!common.Route {
    if (request.derivative_mode == .analytical_plugin) {
        return common.Error.UnsupportedDerivativeMode;
    }
    try request.rtm_controls.validate(request.execution_mode);
    const family = selectFamily(request);
    if (family == .adding and request.execution_mode != .scalar) {
        return common.Error.UnsupportedExecutionMode;
    }
    return .{
        .family = family,
        .regime = request.regime,
        .execution_mode = request.execution_mode,
        .derivative_mode = request.derivative_mode,
        .rtm_controls = request.rtm_controls,
    };
}

fn selectFamily(request: common.DispatchRequest) common.TransportFamily {
    if (request.rtm_controls.use_adding) return .adding;
    if (request.regime != .nadir) return .labos;
    return .labos;
}

pub fn sourceInterfaceFromLayers(layers: []const common.LayerInput, ilevel: usize) common.SourceInterfaceInput {
    if (layers.len == 0) return .{};
    const above_index = @min(ilevel, layers.len - 1);
    const below_index = if (ilevel > 0) ilevel - 1 else above_index;
    const source_weight = if (ilevel < layers.len)
        @max(layers[ilevel].scattering_optical_depth, 0.0)
    else
        0.5 * @max(layers[above_index].scattering_optical_depth, 0.0);

    return .{
        .source_weight = source_weight,
        .particle_ksca_above = @max(layers[above_index].scattering_optical_depth, 0.0),
        .particle_ksca_below = if (ilevel > 0)
            @max(layers[below_index].scattering_optical_depth, 0.0)
        else
            0.0,
        .ksca_above = @max(layers[above_index].scattering_optical_depth, 0.0),
        .ksca_below = if (ilevel > 0)
            @max(layers[below_index].scattering_optical_depth, 0.0)
        else
            0.0,
        .phase_coefficients_above = layers[above_index].phase_coefficients,
        .phase_coefficients_below = if (ilevel > 0)
            layers[below_index].phase_coefficients
        else
            phase_functions.zeroPhaseCoefficients(),
    };
}

pub fn fillSourceInterfacesFromLayers(
    layers: []const common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
) void {
    if (layers.len == 0 or source_interfaces.len != layers.len + 1) return;
    for (source_interfaces, 0..) |*source_interface, ilevel| {
        source_interface.* = sourceInterfaceFromLayers(layers, ilevel);
    }
}

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
    try std.testing.expectError(common.Error.UnsupportedRtmControls, prepareRoute(.{
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
