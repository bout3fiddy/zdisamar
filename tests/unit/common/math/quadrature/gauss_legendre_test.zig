const std = @import("std");
const internal = @import("internal");

const gauss_legendre = internal.common.math.quadrature.gauss_legendre;
const rule = gauss_legendre.rule;
const fillNodesAndWeights = gauss_legendre.fillNodesAndWeights;
const fillDisamarDivPoints01 = gauss_legendre.fillDisamarDivPoints01;

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
