const std = @import("std");
const adding = @import("adding.zig");
const common = @import("common.zig");
const labos = @import("labos.zig");
const phase_functions = @import("../optics/prepare/phase_functions.zig");

pub fn prepare(request: common.DispatchRequest) common.PrepareError!common.Route {
    return common.prepareRoute(request);
}

pub fn executePrepared(
    allocator: std.mem.Allocator,
    route: common.Route,
    input: common.ForwardInput,
) common.ExecuteError!common.ForwardResult {
    // DECISION:
    //   Dispatch by resolved family instead of re-evaluating route policy here.
    return switch (route.family) {
        .adding => adding.execute(allocator, route, input),
        .labos => labos.execute(allocator, route, input),
    };
}

pub fn execute(
    allocator: std.mem.Allocator,
    request: common.DispatchRequest,
    input: common.ForwardInput,
) common.ExecuteError!common.ForwardResult {
    const route = try prepare(request);
    return executePrepared(allocator, route, input);
}

test "dispatcher picks adding lane when use_adding is set" {
    const route = try prepare(.{
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
    const result = try executePrepared(std.testing.allocator, route, .{
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
    const route = try prepare(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(common.TransportFamily.labos, route.family);

    const result = try executePrepared(std.testing.allocator, route, .{});
    try std.testing.expectEqual(common.TransportFamily.labos, result.family);
    try std.testing.expect(result.jacobian_column != null);
}
