const common = @import("../../kernels/transport/common.zig");
const dispatcher = @import("../../kernels/transport/dispatcher.zig");

pub const Provider = struct {
    id: []const u8,
    prepareRoute: *const fn (request: common.DispatchRequest) common.PrepareError!common.Route,
    executePrepared: *const fn (route: common.Route, input: common.ForwardInput) common.ExecuteError!common.ForwardResult,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.dispatcher")) {
        return .{
            .id = provider_id,
            .prepareRoute = dispatcher.prepare,
            .executePrepared = dispatcher.executePrepared,
        };
    }
    return null;
}

const std = @import("std");
