const common = @import("../radiative_transfer/root.zig");
const dispatcher = @import("../radiative_transfer/dispatcher.zig");
const labos = @import("../radiative_transfer/labos/root.zig");
const std = @import("std");

// layout(64-bit):
//   size: 64 B, align: 8 B
//   field storage: 64 B across 7 fields; largest: id=16 B, prepareRoute=8 B, executePrepared=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: id, prepareRoute, executePrepared, executePreparedWithLabosWorkspace, classificationForRoute, +2 more carry references/descriptors; referenced storage is not included in size
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 64 B (0.062 KiB); total also includes referenced storage above
pub const Implementation = struct {
    id: []const u8,
    prepareRoute: *const fn (request: common.DispatchRequest) common.PrepareError!common.Route,
    executePrepared: *const fn (allocator: std.mem.Allocator, route: common.Route, input: common.ForwardInput) common.ExecuteError!common.ForwardResult,
    executePreparedWithLabosWorkspace: ?*const fn (allocator: std.mem.Allocator, route: common.Route, input: common.ForwardInput, workspace: ?*labos.Workspace) common.ExecuteError!common.ForwardResult = null,
    classificationForRoute: *const fn (route: common.Route) common.ImplementationClass,
    provenanceLabelForRoute: *const fn (route: common.Route) []const u8,
    derivativeSemanticsForRoute: *const fn (route: common.Route) common.DerivativeSemantics,
};

pub fn resolve(provider_id: []const u8) ?Implementation {
    if (std.mem.eql(u8, provider_id, "builtin.dispatcher")) {
        return .{
            .id = provider_id,
            .prepareRoute = dispatcher.prepare,
            .executePrepared = dispatcher.executePrepared,
            .executePreparedWithLabosWorkspace = dispatcher.executePreparedWithLabosWorkspace,
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
