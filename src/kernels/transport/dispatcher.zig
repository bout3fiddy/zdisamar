const std = @import("std");
const adding = @import("adding.zig");
const common = @import("common.zig");
const labos = @import("labos.zig");

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
