const std = @import("std");

const internal = @import("internal");

const gauss_angles = internal.rtm.gauss_angles;

// GeometryValueEvidence --------------------------------------------------------------------------------------|
// Old LABOS Geometry.init values for n_gauss=4, solar_mu=0.58, view_mu=0.64.                                  |
//                                                                                                             |
// source                                                                                                      |
//   Derived from main:`radiative_transfer/labos/types.zig` Geometry.init formula and the WP2 ported           |
//   DISAMAR Gauss division-point helper.                                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 144 B (0.141 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 47] stream_mu      : [6]f64                                                                          |
// [ 48.. 95] stream_weight  : [6]f64                                                                          |
// [ 96..103] dmu_plus_0_1  : f64                                                                              |
// [104..111] dmu_min_0_1   : f64                                                                              |
// [112..119] dmu_plus_2_2  : f64                                                                              |
// [120..127] dmu_min_2_2   : f64                                                                              |
// [128..135] dmu_plus_4_5  : f64                                                                              |
// [136..143] dmu_min_4_5   : f64                                                                              |
const GeometryValueEvidence = struct {
    stream_mu: [6]f64,
    stream_weight: [6]f64,
    dmu_plus_0_1: f64,
    dmu_min_0_1: f64,
    dmu_plus_2_2: f64,
    dmu_min_2_2: f64,
    dmu_plus_4_5: f64,
    dmu_min_4_5: f64,
};
// ------------------------------------------------------------------------------------------------------------|

const geometry_4_stream_evidence = GeometryValueEvidence{
    .stream_mu = .{
        0.06943184420297371,
        0.33000947820757187,
        0.66999052179242810,
        0.93056815579702620,
        0.64000000000000000,
        0.58000000000000000,
    },
    .stream_weight = .{
        0.15540979188208606,
        0.46391171818761484,
        0.66100761916241240,
        0.56894871625184380,
        1.00000000000000000,
        1.00000000000000000,
    },
    .dmu_plus_0_1 = 0.62587415466006820,
    .dmu_min_0_1 = -0.95940697656188130,
    .dmu_plus_2_2 = 0.18656980350346902,
    .dmu_min_2_2 = 0.55693266526916860,
    .dmu_plus_4_5 = 0.20491803278688525,
    .dmu_min_4_5 = 4.16666666666666300,
};

test "gauss geometry preserves old LABOS layout constants" {
    try std.testing.expectEqual(@as(usize, 10), gauss_angles.max_gauss);
    try std.testing.expectEqual(@as(usize, 2), gauss_angles.max_extra_streams);
    try std.testing.expectEqual(@as(usize, 12), gauss_angles.max_stream_count);
    try std.testing.expectEqual(@as(usize, 144), gauss_angles.max_pair_count);
    try std.testing.expectEqual(@as(usize, 2832), @sizeOf(gauss_angles.GaussGeometry));
}

test "gauss geometry builds old stream order and pair factors" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);

    try std.testing.expectEqual(@as(usize, 4), geometry.n_gauss);
    try std.testing.expectEqual(@as(usize, 6), geometry.stream_count);
    try std.testing.expectEqual(@as(usize, 4), geometry.viewIndex());
    try std.testing.expectEqual(@as(usize, 5), geometry.solarIndex());
    try std.testing.expectEqual(@as(f64, 0.58), geometry.solar_mu);
    try std.testing.expectEqual(@as(f64, 0.64), geometry.view_mu);

    for (geometry_4_stream_evidence.stream_mu, 0..) |expected, index| {
        try std.testing.expectApproxEqAbs(expected, geometry.u[index], 1.0e-16);
    }
    for (geometry_4_stream_evidence.stream_weight, 0..) |expected, index| {
        try std.testing.expectApproxEqAbs(expected, geometry.w[index], 1.0e-16);
    }

    const pair_0_1 = geometry.pairIndex(0, 1);
    try std.testing.expectApproxEqAbs(geometry_4_stream_evidence.dmu_plus_0_1, geometry.dmu_plus[pair_0_1], 1.0e-16);
    try std.testing.expectApproxEqAbs(geometry_4_stream_evidence.dmu_min_0_1, geometry.dmu_min[pair_0_1], 1.0e-16);
    try std.testing.expect(!geometry.dmu_same[pair_0_1]);

    const pair_2_2 = geometry.pairIndex(2, 2);
    try std.testing.expectApproxEqAbs(geometry_4_stream_evidence.dmu_plus_2_2, geometry.dmu_plus[pair_2_2], 1.0e-16);
    try std.testing.expectApproxEqAbs(geometry_4_stream_evidence.dmu_min_2_2, geometry.dmu_min[pair_2_2], 1.0e-16);
    try std.testing.expect(geometry.dmu_same[pair_2_2]);

    const pair_4_5 = geometry.pairIndex(4, 5);
    try std.testing.expectApproxEqAbs(geometry_4_stream_evidence.dmu_plus_4_5, geometry.dmu_plus[pair_4_5], 1.0e-16);
    try std.testing.expectApproxEqAbs(geometry_4_stream_evidence.dmu_min_4_5, geometry.dmu_min[pair_4_5], 1.0e-16);
    try std.testing.expect(!geometry.dmu_same[pair_4_5]);
}

test "gauss geometry clears inactive fixed storage and rejects invalid counts" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);

    for (geometry.u[6..]) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }
    for (geometry.w[6..]) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }
    for (geometry.ug[4..]) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }
    for (geometry.wg[4..]) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }

    try std.testing.expectError(error.InvalidGaussCount, gauss_angles.GaussGeometry.init(0, 0.58, 0.64));
    try std.testing.expectError(error.InvalidGaussCount, gauss_angles.GaussGeometry.init(11, 0.58, 0.64));
}
