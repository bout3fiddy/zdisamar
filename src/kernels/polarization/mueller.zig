const StokesVector = @import("stokes.zig").StokesVector;

pub const Matrix = [4][4]f64;

pub fn apply(matrix: Matrix, vector: StokesVector) StokesVector {
    const input = [_]f64{ vector.i, vector.q, vector.u, vector.v };
    var output = [_]f64{ 0.0, 0.0, 0.0, 0.0 };

    for (matrix, 0..) |row, row_index| {
        for (row, 0..) |value, column_index| {
            output[row_index] += value * input[column_index];
        }
    }

    return .{
        .i = output[0],
        .q = output[1],
        .u = output[2],
        .v = output[3],
    };
}

test "mueller matrix application rotates stokes state" {
    const matrix: Matrix = .{
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    };
    const out = apply(matrix, .{ .i = 10.0, .q = 2.0, .u = 3.0, .v = 1.0 });
    try std.testing.expectEqual(@as(f64, 10.0), out.i);
    try std.testing.expectEqual(@as(f64, 3.0), out.q);
    try std.testing.expectEqual(@as(f64, 2.0), out.u);
}

const std = @import("std");
