const std = @import("std");
const SceneModel = @import("../../model/Scene.zig");

pub const TransportFamily = enum {
    adding,
    labos,

    pub fn classification(self: TransportFamily) ImplementationClass {
        _ = self;
        return .surrogate;
    }

    pub fn provenanceLabel(self: TransportFamily) []const u8 {
        return switch (self) {
            .adding => "surrogate_adding",
            .labos => "surrogate_labos",
        };
    }
};

pub const ImplementationClass = enum {
    supported,
    surrogate,
    scaffold,
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
    optical_depth: f64 = 0.5,
    single_scatter_albedo: f64 = 0.95,
};

pub const ForwardResult = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
    toa_radiance: f64,
    jacobian_column: ?f64,
};

pub const PrepareError = error{
    UnsupportedDerivativeMode,
    UnsupportedExecutionMode,
};

pub const ExecuteError = PrepareError || error{
    SingularDoublingDenominator,
};

pub const Error = ExecuteError;

pub fn prepareRoute(request: DispatchRequest) PrepareError!Route {
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
    try std.testing.expectEqual(ImplementationClass.surrogate, adding_route.family.classification());
    try std.testing.expectEqualStrings("surrogate_adding", adding_route.family.provenanceLabel());

    const labos_route = try prepareRoute(.{
        .regime = .limb,
        .execution_mode = .polarized,
        .derivative_mode = .analytical_plugin,
    });
    try std.testing.expectEqual(TransportFamily.labos, labos_route.family);
    try std.testing.expectEqual(DerivativeMode.analytical_plugin, labos_route.derivative_mode);
    try std.testing.expectEqualStrings("surrogate_labos", labos_route.family.provenanceLabel());

    const polarized_nadir_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .polarized,
        .derivative_mode = .none,
    });
    try std.testing.expectEqual(TransportFamily.adding, polarized_nadir_route.family);
    try std.testing.expectEqual(ExecutionMode.polarized, polarized_nadir_route.execution_mode);
}
