const std = @import("std");
const internal = @import("internal");

const dispatcher = internal.kernels.transport.dispatcher;
const common = internal.kernels.transport.common;
const phase_functions = internal.kernels.optics.prepare.phase_functions;

test "dispatcher picks adding lane when use_adding is set" {
    const route = try dispatcher.prepare(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
        .rtm_controls = .{ .use_adding = true },
    });
    try std.testing.expectEqual(common.TransportFamily.adding, route.family);

    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.38,
        .scattering_optical_depth = 0.31,
        .single_scatter_albedo = 0.82,
        .solar_mu = 0.71,
        .view_mu = 0.66,
        .phase_coefficients = phase_functions.phaseCoefficientsFromLegacy(.{ 1.0, 0.15, 0.03, 0.0 }),
    }};
    const result = try dispatcher.executePrepared(std.testing.allocator, route, .{
        .spectral_weight = 1.5,
        .air_mass_factor = 0.75,
        .mu0 = 0.71,
        .muv = 0.66,
        .optical_depth = 0.38,
        .single_scatter_albedo = 0.82,
        .layers = &layers,
    });
    try std.testing.expectEqual(common.TransportFamily.adding, result.family);
    try std.testing.expect(result.jacobian_column != null);
}

test "dispatcher picks labos lane for limb semi-analytical mode" {
    const route = try dispatcher.prepare(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(common.TransportFamily.labos, route.family);

    const result = try dispatcher.executePrepared(std.testing.allocator, route, .{});
    try std.testing.expectEqual(common.TransportFamily.labos, result.family);
    try std.testing.expect(result.jacobian_column != null);
}
