pub const Rule = struct {
    count: u32,
    nodes: [4]f64,
    weights: [4]f64,
};

pub fn rule(order: u32) error{UnsupportedOrder}!Rule {
    return switch (order) {
        2 => .{
            .count = 2,
            .nodes = .{ -0.5773502691896257, 0.5773502691896257, 0.0, 0.0 },
            .weights = .{ 1.0, 1.0, 0.0, 0.0 },
        },
        3 => .{
            .count = 3,
            .nodes = .{ -0.7745966692414834, 0.0, 0.7745966692414834, 0.0 },
            .weights = .{ 0.5555555555555556, 0.8888888888888888, 0.5555555555555556, 0.0 },
        },
        4 => .{
            .count = 4,
            .nodes = .{ -0.8611363115940526, -0.3399810435848563, 0.3399810435848563, 0.8611363115940526 },
            .weights = .{ 0.3478548451374538, 0.6521451548625461, 0.6521451548625461, 0.3478548451374538 },
        },
        else => error.UnsupportedOrder,
    };
}

test "gauss-legendre rules expose stable nodes and weights" {
    const three_point = try rule(3);
    try std.testing.expectEqual(@as(u32, 3), three_point.count);
    try std.testing.expectApproxEqRel(@as(f64, 0.0), three_point.nodes[1], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.8888888888888888), three_point.weights[1], 1e-12);
}

const std = @import("std");
