const common = @import("../../kernels/transport/common.zig");
const dispatcher = @import("../../kernels/transport/dispatcher.zig");
const std = @import("std");

pub const Provider = struct {
    id: []const u8,
    prepareRoute: *const fn (request: common.DispatchRequest) common.PrepareError!common.Route,
    executePrepared: *const fn (allocator: std.mem.Allocator, route: common.Route, input: common.ForwardInput) common.ExecuteError!common.ForwardResult,
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

fn classificationForRoute(route: common.Route) common.ImplementationClass {
    return route.family.classification();
}

fn provenanceLabelForRoute(route: common.Route) []const u8 {
    return route.family.provenanceLabel();
}

fn derivativeSemanticsForRoute(route: common.Route) common.DerivativeSemantics {
    return route.derivativeSemantics();
}
