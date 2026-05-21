const std = @import("std");
const internal = @import("internal");

const dispatcher = internal.forward_model.radiative_transfer.dispatcher;
const common = internal.forward_model.radiative_transfer;
test "dispatcher picks labos lane for the O2A scalar forward mode" {
    const route = try dispatcher.prepare(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    try std.testing.expectEqual(common.TransportFamily.labos, route.family);

    const result = try dispatcher.executePrepared(std.testing.allocator, route, .{});
    try std.testing.expectEqual(common.TransportFamily.labos, result.family);
    try std.testing.expect(result.jacobian == null);
}
