const std = @import("std");
const internal = @import("internal");

const gauss_legendre = internal.common.math.gauss_legendre;
const rule = gauss_legendre.rule;
const fillCanonicalNodesAndWeights = gauss_legendre.fillCanonicalNodesAndWeights;
const fillCanonicalDisamarDivPointNodes = gauss_legendre.fillCanonicalDisamarDivPointNodes;
const fillNodesAndWeights = gauss_legendre.fillNodesAndWeights;
const fillDisamarDivPoints01 = gauss_legendre.fillDisamarDivPoints01;
const fillDisamarDivPointsIntervalNodes = gauss_legendre.fillDisamarDivPointsIntervalNodes;
const scaleIntervalNodes = gauss_legendre.scaleIntervalNodes;
const Rule = gauss_legendre.Rule;

const legacy_fixed_rules = [_]Rule{
    .{
        .count = 1,
        .nodes = .{
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
        .weights = .{
            2.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
    },
    .{
        .count = 2,
        .nodes = .{
            -0.5773502691896257,
            0.5773502691896257,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
        .weights = .{
            1.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
    },
    .{
        .count = 3,
        .nodes = .{
            -0.7745966692414834,
            0.0,
            0.7745966692414834,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
        .weights = .{
            0.5555555555555556,
            0.8888888888888888,
            0.5555555555555556,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
    },
    .{
        .count = 4,
        .nodes = .{
            -0.8611363115940526,
            -0.3399810435848563,
            0.3399810435848563,
            0.8611363115940526,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
        .weights = .{
            0.3478548451374538,
            0.6521451548625461,
            0.6521451548625461,
            0.3478548451374538,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
    },
    .{
        .count = 5,
        .nodes = .{
            -0.9061798459386640,
            -0.5384693101056831,
            0.0,
            0.5384693101056831,
            0.9061798459386640,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
        .weights = .{
            0.2369268850561891,
            0.4786286704993665,
            0.5688888888888889,
            0.4786286704993665,
            0.2369268850561891,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        },
    },
    .{
        .count = 6,
        .nodes = .{
            -0.9324695142031521,
            -0.6612093864662645,
            -0.2386191860831969,
            0.2386191860831969,
            0.6612093864662645,
            0.9324695142031521,
            0.0,
            0.0,
            0.0,
            0.0,
        },
        .weights = .{
            0.1713244923791704,
            0.3607615730481386,
            0.4679139345726910,
            0.4679139345726910,
            0.3607615730481386,
            0.1713244923791704,
            0.0,
            0.0,
            0.0,
            0.0,
        },
    },
    .{
        .count = 7,
        .nodes = .{
            -0.9491079123427585,
            -0.7415311855993945,
            -0.4058451513773972,
            0.0,
            0.4058451513773972,
            0.7415311855993945,
            0.9491079123427585,
            0.0,
            0.0,
            0.0,
        },
        .weights = .{
            0.1294849661688697,
            0.2797053914892766,
            0.3818300505051189,
            0.4179591836734694,
            0.3818300505051189,
            0.2797053914892766,
            0.1294849661688697,
            0.0,
            0.0,
            0.0,
        },
    },
    .{
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
    .{
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
    .{
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
};

test "gauss-legendre generated fixed rules match legacy literals bit-for-bit" {
    for (legacy_fixed_rules, 1..) |expected, order| {
        const actual = try rule(@intCast(order));
        try expectRuleBits(expected, actual);
    }
}

fn expectRuleBits(expected: Rule, actual: Rule) !void {
    try std.testing.expectEqual(expected.count, actual.count);
    for (expected.nodes, actual.nodes) |expected_node, actual_node| {
        try std.testing.expectEqual(@as(u64, @bitCast(expected_node)), @as(u64, @bitCast(actual_node)));
    }
    for (expected.weights, actual.weights) |expected_weight, actual_weight| {
        try std.testing.expectEqual(@as(u64, @bitCast(expected_weight)), @as(u64, @bitCast(actual_weight)));
    }
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

test "gauss-legendre dynamic fill supports higher-order rules" {
    var nodes = [_]f64{0.0} ** 20;
    var weights = [_]f64{0.0} ** 20;

    try fillNodesAndWeights(20, nodes[0..], weights[0..]);
    try std.testing.expectApproxEqRel(@as(f64, -0.9931285991850949), nodes[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.1527533871307258), weights[9], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, -nodes[19]), nodes[0], 1e-12);
}

test "canonical ordinary fill matches dynamic fill bit-for-bit" {
    var canonical_nodes = [_]f64{0.0} ** 20;
    var canonical_weights = [_]f64{0.0} ** 20;
    var dynamic_nodes = [_]f64{0.0} ** 20;
    var dynamic_weights = [_]f64{0.0} ** 20;

    try fillCanonicalNodesAndWeights(20, canonical_nodes[0..], canonical_weights[0..]);
    try fillNodesAndWeights(20, dynamic_nodes[0..], dynamic_weights[0..]);

    try expectEqualF64Bits(canonical_nodes[0..], dynamic_nodes[0..]);
    try expectEqualF64Bits(canonical_weights[0..], dynamic_weights[0..]);
}

test "disamar gauss division points are scaled to unit interval" {
    var nodes = [_]f64{0.0} ** 5;
    var weights = [_]f64{0.0} ** 5;

    try fillDisamarDivPoints01(5, nodes[0..], weights[0..]);

    var sum_weights: f64 = 0.0;
    for (0..5) |index| {
        try std.testing.expect(nodes[index] >= 0.0 and nodes[index] <= 1.0);
        sum_weights += weights[index];
    }
    try std.testing.expect(nodes[0] < nodes[1]);
    try std.testing.expect(nodes[1] < nodes[2]);
    try std.testing.expect(nodes[2] < nodes[3]);
    try std.testing.expect(nodes[3] < nodes[4]);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), sum_weights, 1e-12);
}

test "disamar interval node-only fill scales nodes" {
    var node_only = [_]f64{0.0} ** 28;

    try fillDisamarDivPointsIntervalNodes(28, 2.3, 17.9, node_only[0..]);

    try std.testing.expect(node_only[0] > 2.3);
    try std.testing.expect(node_only[node_only.len - 1] < 17.9);
    for (node_only[0 .. node_only.len - 1], node_only[1..]) |left, right| {
        try std.testing.expect(left < right);
    }
}

test "canonical disamar interval nodes rescale to old fill bit-for-bit" {
    var old_nodes = [_]f64{0.0} ** 28;
    var canonical_nodes = [_]f64{0.0} ** 28;
    var scaled_nodes = [_]f64{0.0} ** 28;

    try fillDisamarDivPointsIntervalNodes(28, 2.3, 17.9, old_nodes[0..]);
    try fillCanonicalDisamarDivPointNodes(28, canonical_nodes[0..]);
    try scaleIntervalNodes(canonical_nodes[0..], 2.3, 17.9, scaled_nodes[0..]);

    try expectEqualF64Bits(old_nodes[0..], scaled_nodes[0..]);
}

fn expectEqualF64Bits(expected: []const f64, actual: []const f64) !void {
    // expectEqualF64Bits -------------------------------------------------------------------------------------|
    // Compare retained quadrature rows exactly so setup reuse cannot change support placement by one ULP.    |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_value, actual_value| {
        try std.testing.expectEqual(@as(u64, @bitCast(expected_value)), @as(u64, @bitCast(actual_value)));
    }
}
