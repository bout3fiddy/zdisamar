pub const Rule = struct {
    count: u32,
    nodes: [10]f64,
    weights: [10]f64,
};

pub fn rule(order: u32) error{UnsupportedOrder}!Rule {
    return switch (order) {
        1 => .{
            .count = 1,
            .nodes = .{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        2 => .{
            .count = 2,
            .nodes = .{ -0.5773502691896257, 0.5773502691896257, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        3 => .{
            .count = 3,
            .nodes = .{ -0.7745966692414834, 0.0, 0.7745966692414834, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 0.5555555555555556, 0.8888888888888888, 0.5555555555555556, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        4 => .{
            .count = 4,
            .nodes = .{ -0.8611363115940526, -0.3399810435848563, 0.3399810435848563, 0.8611363115940526, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 0.3478548451374538, 0.6521451548625461, 0.6521451548625461, 0.3478548451374538, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        8 => .{
            .count = 8,
            .nodes = .{
                -0.9602898564975363,
                -0.7966664774136267,
                -0.5255324099163290,
                -0.1834346424956498,
                0.1834346424956498,
                0.5255324099163290,
                0.7966664774136267,
                0.9602898564975363,
                0.0,
                0.0,
            },
            .weights = .{
                0.1012285362903763,
                0.2223810344533745,
                0.3137066458778873,
                0.3626837833783620,
                0.3626837833783620,
                0.3137066458778873,
                0.2223810344533745,
                0.1012285362903763,
                0.0,
                0.0,
            },
        },
        10 => .{
            .count = 10,
            .nodes = .{
                -0.9739065285171717,
                -0.8650633666889845,
                -0.6794095682990244,
                -0.4333953941292472,
                -0.1488743389816312,
                0.1488743389816312,
                0.4333953941292472,
                0.6794095682990244,
                0.8650633666889845,
                0.9739065285171717,
            },
            .weights = .{
                0.0666713443086881,
                0.1494513491505806,
                0.2190863625159820,
                0.2692667193099964,
                0.2955242247147529,
                0.2955242247147529,
                0.2692667193099964,
                0.2190863625159820,
                0.1494513491505806,
                0.0666713443086881,
            },
        },
        else => error.UnsupportedOrder,
    };
}

test "gauss-legendre rules expose stable nodes and weights" {
    const one_point = try rule(1);
    try std.testing.expectEqual(@as(u32, 1), one_point.count);
    try std.testing.expectApproxEqRel(@as(f64, 0.0), one_point.nodes[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 2.0), one_point.weights[0], 1e-12);

    const three_point = try rule(3);
    try std.testing.expectEqual(@as(u32, 3), three_point.count);
    try std.testing.expectApproxEqRel(@as(f64, 0.0), three_point.nodes[1], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.8888888888888888), three_point.weights[1], 1e-12);

    const ten_point = try rule(10);
    try std.testing.expectEqual(@as(u32, 10), ten_point.count);
    try std.testing.expectApproxEqRel(@as(f64, -0.9739065285171717), ten_point.nodes[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.2955242247147529), ten_point.weights[4], 1e-12);
}

const std = @import("std");
