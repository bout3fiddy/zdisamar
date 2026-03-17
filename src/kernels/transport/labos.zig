const std = @import("std");
const common = @import("common.zig");
const derivatives = @import("derivatives.zig");
const doubling = @import("doubling.zig");
const gauss_legendre = @import("../quadrature/gauss_legendre.zig");
const source_integration = @import("../quadrature/source_integration.zig");

pub fn execute(route: common.Route, input: common.ForwardInput) common.ExecuteError!common.ForwardResult {
    if (route.family != .labos) unreachable;
    if (route.derivative_mode == .analytical_plugin) {
        return common.Error.UnsupportedDerivativeMode;
    }

    const rule = gauss_legendre.rule(3) catch unreachable;
    const source_terms = [_]f64{
        input.single_scatter_albedo * 0.6,
        input.single_scatter_albedo,
        input.single_scatter_albedo * (1.0 - std.math.exp(-input.optical_depth)),
    };
    const source_factor = source_integration.integrate(rule.weights[0..3], &source_terms) catch unreachable;
    const backscatter_fraction = if (input.layers.len > 0)
        @import("../optics/prepare/phase_functions.zig").backscatterFraction(input.layers[0].phase_coefficients)
    else
        0.5;
    const layer = try doubling.propagateHomogeneous(
        input.optical_depth,
        input.single_scatter_albedo,
        backscatter_fraction,
        input.mu0,
        input.muv,
        2,
    );
    const direct_down = std.math.exp(-input.optical_depth / input.mu0);
    const direct_up = std.math.exp(-input.optical_depth / input.muv);
    const surface_term = input.surface_albedo * direct_down * direct_up;
    const multiple_scatter_gain = 1.0 / @max(1.0 - 0.35 * input.single_scatter_albedo * (1.0 - layer.transmittance), 0.3);
    const path_term = 0.35 * source_factor * (1.0 - layer.transmittance) * multiple_scatter_gain / @max(input.mu0 + input.muv, 0.1);
    const toa = std.math.clamp(surface_term + path_term, 0.0, 1.5);
    return .{
        .family = route.family,
        .regime = route.regime,
        .execution_mode = route.execution_mode,
        .derivative_mode = route.derivative_mode,
        .toa_reflectance_factor = toa,
        .jacobian_column = switch (route.derivative_mode) {
            .none => null,
            .semi_analytical => derivatives.proxyJacobianColumn(toa, input.optical_depth, 0.06),
            .analytical_plugin => null,
            .numerical => derivatives.proxyJacobianColumn(toa, input.optical_depth, 0.05),
        },
    };
}

test "labos execution supports semi-analytical derivatives but rejects plugin analytical mode" {
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    const result = try execute(route, .{
        .spectral_weight = 1.0,
        .air_mass_factor = 1.0,
    });

    try std.testing.expectEqual(common.TransportFamily.labos, result.family);
    try std.testing.expect(result.jacobian_column != null);
    try std.testing.expect(result.jacobian_column.? < 0.0);
    try std.testing.expectError(common.Error.UnsupportedDerivativeMode, common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .analytical_plugin,
    }));
}
