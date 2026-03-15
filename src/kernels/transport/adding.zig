const std = @import("std");
const common = @import("common.zig");
const derivatives = @import("derivatives.zig");
const doubling = @import("doubling.zig");
const gauss_legendre = @import("../quadrature/gauss_legendre.zig");
const source_integration = @import("../quadrature/source_integration.zig");

pub fn execute(route: common.Route, input: common.ForwardInput) common.Error!common.ForwardResult {
    if (route.family != .adding) unreachable;

    // Adding solver lane intentionally does not accept plugin analytical derivatives.
    if (route.derivative_mode == .analytical_plugin) {
        return common.Error.UnsupportedDerivativeMode;
    }

    const mode_scale: f64 = switch (route.execution_mode) {
        .scalar => 1.0,
        .polarized => 1.05,
    };
    const regime_scale: f64 = switch (route.regime) {
        .nadir => 1.0,
        .limb => 0.92,
        .occultation => 0.88,
    };

    const rule = gauss_legendre.rule(2) catch unreachable;
    const source_terms = [_]f64{
        input.spectral_weight,
        input.spectral_weight * input.air_mass_factor,
    };
    const source_factor = source_integration.integrate(rule.weights[0..2], &source_terms) catch unreachable;
    const layer = doubling.propagateHomogeneous(input.optical_depth, input.single_scatter_albedo, 1);
    const toa = source_factor * layer.transmittance * mode_scale * regime_scale;
    return .{
        .family = route.family,
        .regime = route.regime,
        .execution_mode = route.execution_mode,
        .derivative_mode = route.derivative_mode,
        .toa_radiance = toa,
        .jacobian_column = switch (route.derivative_mode) {
            .none => null,
            .semi_analytical => derivatives.jacobianColumn(toa, input.optical_depth, 0.10),
            .analytical_plugin => null,
            .numerical => derivatives.jacobianColumn(toa, input.optical_depth, 0.08),
        },
    };
}

test "adding execution returns deterministic scalar output" {
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const result = try execute(route, .{
        .spectral_weight = 1.2,
        .air_mass_factor = 0.8,
    });

    try std.testing.expectEqual(common.TransportFamily.adding, result.family);
    try std.testing.expect(result.toa_radiance > 0.0);
    try std.testing.expectEqual(@as(?f64, null), result.jacobian_column);
}
