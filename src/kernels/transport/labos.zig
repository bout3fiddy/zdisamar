const std = @import("std");
const common = @import("common.zig");

pub fn execute(route: common.Route, input: common.ForwardInput) common.Error!common.ForwardResult {
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
    try std.testing.expectApproxEqRel(@as(f64, 0.16704), result.jacobian_column.?, 1e-12);
}
