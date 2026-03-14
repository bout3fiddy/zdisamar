const std = @import("std");
const SceneModel = @import("../../model/Scene.zig");

pub const TransportFamily = enum {
    adding,
    labos,
};

pub const Regime = SceneModel.ObservationRegime;

pub const ExecutionMode = enum {
    scalar,
    polarized,
};

pub const DerivativeMode = SceneModel.DerivativeMode;

pub const DispatchRequest = struct {
    regime: Regime = .nadir,
    execution_mode: ExecutionMode = .scalar,
    derivative_mode: DerivativeMode = .none,
};

pub const Route = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
};

pub const ForwardInput = struct {
    wavelength_nm: f64 = 440.0,
    spectral_weight: f64 = 1.0,
    air_mass_factor: f64 = 1.0,
};

pub const ForwardResult = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
    toa_radiance: f64,
    jacobian_column: ?f64,
};

pub const Error = error{
    UnsupportedDerivativeMode,
};

pub fn prepareRoute(request: DispatchRequest) Error!Route {
    const family = selectFamily(request);

    if (family == .adding and request.derivative_mode == .analytical_plugin) {
        return Error.UnsupportedDerivativeMode;
    }

    return .{
        .family = family,
        .regime = request.regime,
        .execution_mode = request.execution_mode,
        .derivative_mode = request.derivative_mode,
    };
}

pub fn estimateJacobian(mode: DerivativeMode, signal: f64) ?f64 {
    return switch (mode) {
        .none => null,
        .semi_analytical => 0.10 * signal,
        .analytical_plugin => 0.12 * signal,
        .numerical => 0.08 * signal,
    };
}

fn selectFamily(request: DispatchRequest) TransportFamily {
    return switch (request.regime) {
        .nadir => switch (request.derivative_mode) {
            .analytical_plugin => .labos,
            else => .adding,
        },
        .limb, .occultation => .labos,
    };
}

test "prepare route resolves families and keeps derivative mode explicit" {
    const adding_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(TransportFamily.adding, adding_route.family);
    try std.testing.expectEqual(DerivativeMode.semi_analytical, adding_route.derivative_mode);

    const labos_route = try prepareRoute(.{
        .regime = .limb,
        .execution_mode = .polarized,
        .derivative_mode = .analytical_plugin,
    });
    try std.testing.expectEqual(TransportFamily.labos, labos_route.family);
    try std.testing.expectEqual(DerivativeMode.analytical_plugin, labos_route.derivative_mode);
}
