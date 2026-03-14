const std = @import("std");
const adding = @import("adding.zig");
const common = @import("common.zig");
const labos = @import("labos.zig");

pub fn prepare(request: common.DispatchRequest) common.Error!common.Route {
    return common.prepareRoute(request);
}

pub fn executePrepared(route: common.Route, input: common.ForwardInput) common.Error!common.ForwardResult {
    return switch (route.family) {
        .adding => adding.execute(route, input),
        .labos => labos.execute(route, input),
    };
}

pub fn execute(request: common.DispatchRequest, input: common.ForwardInput) common.Error!common.ForwardResult {
    const route = try prepare(request);
    return executePrepared(route, input);
}

test "dispatcher picks adding lane for nadir without analytical plugin" {
    const route = try prepare(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(common.TransportFamily.adding, route.family);

    const result = try executePrepared(route, .{
        .spectral_weight = 1.5,
        .air_mass_factor = 0.75,
    });
    try std.testing.expectEqual(common.TransportFamily.adding, result.family);
    try std.testing.expect(result.jacobian_column != null);
}

test "dispatcher picks labos lane for limb and analytical plugin mode" {
    const route = try prepare(.{
        .regime = .limb,
        .execution_mode = .polarized,
        .derivative_mode = .analytical_plugin,
    });
    try std.testing.expectEqual(common.TransportFamily.labos, route.family);

    const result = try executePrepared(route, .{});
    try std.testing.expectEqual(common.TransportFamily.labos, result.family);
    try std.testing.expect(result.jacobian_column != null);
}
