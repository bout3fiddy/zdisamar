const std = @import("std");
const internal = @import("internal");

const small_dense = internal.common.math.linalg.small_dense;
const solve2x2 = small_dense.solve2x2;
const solve3x3 = small_dense.solve3x3;
const setIdentity = small_dense.setIdentity;
const trace = small_dense.trace;
const index = small_dense.index;

test "small dense solver solves a 2x2 system" {
    const solution = try solve2x2(.{
        .{ 4.0, 1.0 },
        .{ 2.0, 3.0 },
    }, .{ 1.0, 2.0 });

    try std.testing.expectApproxEqRel(@as(f64, 0.1), solution[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.6), solution[1], 1e-12);
}

test "small dense solver solves a 3x3 system" {
    const solution = try solve3x3(.{
        .{ 3.0, 1.0, -1.0 },
        .{ 2.0, 4.0, 1.0 },
        .{ -1.0, 2.0, 5.0 },
    }, .{ 4.0, 1.0, 1.0 });

    try std.testing.expectApproxEqRel(@as(f64, 2.0), solution[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, -1.0), solution[1], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), solution[2], 1e-12);
}

test "small dense helpers build identity matrices and traces" {
    var matrix: [9]f64 = undefined;
    try setIdentity(&matrix, 3);
    try std.testing.expectEqual(@as(f64, 3.0), try trace(&matrix, 3));
    try std.testing.expectEqual(@as(f64, 0.0), matrix[index(0, 1, 3)]);
}
