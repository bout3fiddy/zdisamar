const std = @import("std");
const common = @import("root.zig");
const labos = @import("labos/root.zig");

pub fn prepare(request: common.DispatchRequest) common.PrepareError!common.Route {
    return common.prepareRoute(request);
}

pub fn executePrepared(
    allocator: std.mem.Allocator,
    route: common.Route,
    input: common.ForwardInput,
) common.ExecuteError!common.ForwardResult {
    return executePreparedWithLabosWorkspace(allocator, route, input, null);
}

pub fn executePreparedWithLabosWorkspace(
    allocator: std.mem.Allocator,
    route: common.Route,
    input: common.ForwardInput,
    workspace: ?*labos.Workspace,
) common.ExecuteError!common.ForwardResult {
    if (route.regime != .nadir) return common.Error.UnsupportedObservationRegime;
    if (route.execution_mode != .scalar) return common.Error.UnsupportedExecutionMode;
    if (route.derivative_mode == .numerical) return common.Error.UnsupportedDerivativeMode;
    return labos.executeWithWorkspace(allocator, route, input, workspace);
}

pub fn execute(
    allocator: std.mem.Allocator,
    request: common.DispatchRequest,
    input: common.ForwardInput,
) common.ExecuteError!common.ForwardResult {
    const route = try prepare(request);
    return executePrepared(allocator, route, input);
}
