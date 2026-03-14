const std = @import("std");
const common = @import("common.zig");

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

    const toa = input.spectral_weight * input.air_mass_factor * mode_scale * regime_scale;
    return .{
        .family = route.family,
        .regime = route.regime,
        .execution_mode = route.execution_mode,
        .derivative_mode = route.derivative_mode,
        .toa_radiance = toa,
        .jacobian_column = common.estimateJacobian(route.derivative_mode, toa),
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
    try std.testing.expectApproxEqRel(@as(f64, 0.96), result.toa_radiance, 1e-12);
    try std.testing.expectEqual(@as(?f64, null), result.jacobian_column);
}
