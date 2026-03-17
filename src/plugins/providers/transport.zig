const common = @import("../../kernels/transport/common.zig");
const dispatcher = @import("../../kernels/transport/dispatcher.zig");

pub const Provider = struct {
    id: []const u8,
    prepareRoute: *const fn (request: common.DispatchRequest) common.PrepareError!common.Route,
    executePrepared: *const fn (route: common.Route, input: common.ForwardInput) common.ExecuteError!common.ForwardResult,
    classificationForRoute: *const fn (route: common.Route) common.ImplementationClass,
    provenanceLabelForRoute: *const fn (route: common.Route) []const u8,
    derivativeSemanticsForRoute: *const fn (route: common.Route) common.DerivativeSemantics,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.dispatcher")) {
        return .{
            .id = provider_id,
            .prepareRoute = dispatcher.prepare,
            .executePrepared = dispatcher.executePrepared,
            .classificationForRoute = classificationForRoute,
            .provenanceLabelForRoute = provenanceLabelForRoute,
            .derivativeSemanticsForRoute = derivativeSemanticsForRoute,
        };
    }
    return null;
}

const std = @import("std");

fn classificationForRoute(route: common.Route) common.ImplementationClass {
    return route.family.classification();
}

fn provenanceLabelForRoute(route: common.Route) []const u8 {
    return route.family.provenanceLabel();
}

fn derivativeSemanticsForRoute(route: common.Route) common.DerivativeSemantics {
    return route.derivativeSemantics();
}

test "transport provider exposes route fidelity and provenance helpers" {
    const provider = resolve("builtin.dispatcher") orelse unreachable;
    const route = try provider.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    try std.testing.expectEqual(common.ImplementationClass.surrogate, provider.classificationForRoute(route));
    try std.testing.expectEqualStrings("surrogate_adding", provider.provenanceLabelForRoute(route));
    try std.testing.expectEqual(common.DerivativeSemantics.none, provider.derivativeSemanticsForRoute(route));
}
