const std = @import("std");
const common = @import("common.zig");
const derivatives = @import("derivatives.zig");
const doubling = @import("doubling.zig");
const gauss_legendre = @import("../quadrature/gauss_legendre.zig");
const source_integration = @import("../quadrature/source_integration.zig");

pub fn execute(route: common.Route, input: common.ForwardInput) common.ExecuteError!common.ForwardResult {
    if (route.family != .labos) unreachable;

    const mode_scale: f64 = switch (route.execution_mode) {
        .scalar => 1.08,
        .polarized => 1.20,
    };
    const regime_scale: f64 = switch (route.regime) {
        .nadir => 1.02,
        .limb => 1.16,
        .occultation => 1.22,
    };

    const rule = gauss_legendre.rule(3) catch unreachable;
    const source_terms = [_]f64{
        input.spectral_weight * 0.8,
        input.spectral_weight,
        input.spectral_weight * input.air_mass_factor,
    };
    const source_factor = source_integration.integrate(rule.weights[0..3], &source_terms) catch unreachable;
    const layer = try doubling.propagateHomogeneous(input.optical_depth, input.single_scatter_albedo, 2);
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
            .analytical_plugin => derivatives.jacobianColumn(toa, input.optical_depth, 0.12),
            .numerical => derivatives.jacobianColumn(toa, input.optical_depth, 0.08),
        },
    };
}

test "labos execution supports plugin analytical derivative mode" {
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .polarized,
        .derivative_mode = .analytical_plugin,
    });
    const result = try execute(route, .{
        .spectral_weight = 1.0,
        .air_mass_factor = 1.0,
    });

    try std.testing.expectEqual(common.TransportFamily.labos, result.family);
    try std.testing.expect(result.jacobian_column != null);
    try std.testing.expect(result.jacobian_column.? < 0.0);
}
