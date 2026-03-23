//! Purpose:
//!   Provide fixed Gauss-Legendre quadrature rules for small orders.
//!
//! Physics:
//!   Supplies precomputed nodes and weights on the canonical interval `[-1, 1]`.
//!
//! Vendor:
//!   `Gauss-Legendre quadrature`
//!
//! Design:
//!   The rule table is hard-coded so higher-level integration code can stay allocation-free and deterministic.
//!
//! Invariants:
//!   Only orders 1 through 10 are supported in this compact table.
//!
//! Validation:
//!   Tests check representative nodes and weights across the supported orders.

/// Purpose:
///   Store a fixed Gauss-Legendre quadrature rule.
pub const Rule = struct {
    count: u32,
    nodes: [10]f64,
    weights: [10]f64,
};

/// Purpose:
///   Return a Gauss-Legendre rule of the requested order.
///
/// Physics:
///   Provides fixed nodes and weights for numerical integration on `[-1, 1]`.
///
/// Vendor:
///   `Gauss-Legendre rule lookup`
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
        5 => .{
            .count = 5,
            .nodes = .{ -0.9061798459386640, -0.5384693101056831, 0.0, 0.5384693101056831, 0.9061798459386640, 0.0, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891, 0.0, 0.0, 0.0, 0.0, 0.0 },
        },
        6 => .{
            .count = 6,
            .nodes = .{ -0.9324695142031521, -0.6612093864662645, -0.2386191860831969, 0.2386191860831969, 0.6612093864662645, 0.9324695142031521, 0.0, 0.0, 0.0, 0.0 },
            .weights = .{ 0.1713244923791704, 0.3607615730481386, 0.4679139345726910, 0.4679139345726910, 0.3607615730481386, 0.1713244923791704, 0.0, 0.0, 0.0, 0.0 },
        },
        7 => .{
            .count = 7,
            .nodes = .{ -0.9491079123427585, -0.7415311855993945, -0.4058451513773972, 0.0, 0.4058451513773972, 0.7415311855993945, 0.9491079123427585, 0.0, 0.0, 0.0 },
            .weights = .{ 0.1294849661688697, 0.2797053914892766, 0.3818300505051189, 0.4179591836734694, 0.3818300505051189, 0.2797053914892766, 0.1294849661688697, 0.0, 0.0, 0.0 },
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
        9 => .{
            .count = 9,
            .nodes = .{
                -0.9681602395076261,
                -0.8360311073266358,
                -0.6133714327005904,
                -0.3242534234038089,
                0.0,
                0.3242534234038089,
                0.6133714327005904,
                0.8360311073266358,
                0.9681602395076261,
                0.0,
            },
            .weights = .{
                0.0812743883615744,
                0.1806481606948574,
                0.2606106964029354,
                0.3123470770400029,
                0.3302393550012598,
                0.3123470770400029,
                0.2606106964029354,
                0.1806481606948574,
                0.0812743883615744,
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

    const seven_point = try rule(7);
    try std.testing.expectEqual(@as(u32, 7), seven_point.count);
    try std.testing.expectApproxEqRel(@as(f64, 0.0), seven_point.nodes[3], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.4179591836734694), seven_point.weights[3], 1e-12);

    const ten_point = try rule(10);
    try std.testing.expectEqual(@as(u32, 10), ten_point.count);
    try std.testing.expectApproxEqRel(@as(f64, -0.9739065285171717), ten_point.nodes[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.2955242247147529), ten_point.weights[4], 1e-12);
}

const std = @import("std");
