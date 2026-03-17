const std = @import("std");
const SceneModel = @import("../../model/Scene.zig");
const phase_coefficient_count = @import("../optics/prepare/phase_functions.zig").phase_coefficient_count;

pub const TransportFamily = enum {
    adding,
    labos,

    pub fn classification(self: TransportFamily) ImplementationClass {
        return switch (self) {
            .adding => .surrogate,
            .labos => .surrogate,
        };
    }

    pub fn provenanceLabel(self: TransportFamily) []const u8 {
        return switch (self) {
            .adding => "surrogate_adding",
            .labos => "surrogate_labos",
        };
    }
};

pub const ImplementationClass = enum {
    baseline,
    surrogate,
};

pub const DerivativeSemantics = enum {
    none,
    proxy,
    analytical,
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

    pub fn derivativeSemantics(self: Route) DerivativeSemantics {
        if (self.derivative_mode == .none) return .none;
        return switch (self.family.classification()) {
            .surrogate => .proxy,
            .baseline => .analytical,
        };
    }
};

pub const LayerInput = struct {
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_scattering_optical_depth: f64 = 0.0,
    optical_depth: f64 = 0.0,
    scattering_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
    solar_mu: f64 = 1.0,
    view_mu: f64 = 1.0,
    phase_coefficients: [phase_coefficient_count]f64 = .{ 1.0, 0.0, 0.0, 0.0 },
};

pub const ForwardInput = struct {
    wavelength_nm: f64 = 440.0,
    spectral_weight: f64 = 1.0,
    air_mass_factor: f64 = 1.0,
    mu0: f64 = 1.0,
    muv: f64 = 1.0,
    surface_albedo: f64 = 0.05,
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_scattering_optical_depth: f64 = 0.0,
    optical_depth: f64 = 0.5,
    single_scatter_albedo: f64 = 0.95,
    layers: []const LayerInput = &.{},
};

pub const ForwardResult = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
    toa_reflectance_factor: f64,
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
    if (request.derivative_mode == .analytical_plugin) {
        return Error.UnsupportedDerivativeMode;
    }
    const family = selectFamily(request);
    if (family == .adding and request.execution_mode != .scalar) {
        return Error.UnsupportedExecutionMode;
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
        .nadir => .adding,
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
    try std.testing.expectEqual(DerivativeSemantics.proxy, adding_route.derivativeSemantics());
    try std.testing.expectEqual(ImplementationClass.surrogate, adding_route.family.classification());
    try std.testing.expectEqualStrings("surrogate_adding", adding_route.family.provenanceLabel());

    const labos_route = try prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(TransportFamily.labos, labos_route.family);
    try std.testing.expectEqual(DerivativeMode.semi_analytical, labos_route.derivative_mode);
    try std.testing.expectEqual(DerivativeSemantics.proxy, labos_route.derivativeSemantics());
    try std.testing.expectEqualStrings("surrogate_labos", labos_route.family.provenanceLabel());

    try std.testing.expectError(Error.UnsupportedExecutionMode, prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .polarized,
        .derivative_mode = .none,
    }));
    try std.testing.expectError(Error.UnsupportedDerivativeMode, prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .analytical_plugin,
    }));
}
