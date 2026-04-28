const std = @import("std");
const internal = @import("internal");

const cholesky = internal.kernels.linalg.cholesky;
const dense = internal.kernels.linalg.small_dense;

const factor2x2 = cholesky.factor2x2;
const factorInPlace = cholesky.factorInPlace;
const solveWithFactor = cholesky.solveWithFactor;
const invertFromFactor = cholesky.invertFromFactor;

test "cholesky factorization reproduces a positive-definite 2x2 matrix" {
    const factor = try factor2x2(.{
        .{ 4.0, 2.0 },
        .{ 2.0, 3.0 },
    });
    try std.testing.expectApproxEqRel(@as(f64, 2.0), factor[0][0], 1e-12);
    try std.testing.expect(factor[1][1] > 0.0);
}

test "cholesky solves and inverts dense SPD systems" {
    var matrix = [_]f64{
        5.0, 1.0, 0.0,
        1.0, 4.0, 1.0,
        0.0, 1.0, 3.0,
    };
    try factorInPlace(&matrix, 3);

    // A * x = b with x = [1, 2, 1] gives b = [7, 10, 5] for the matrix above.
    var solution = [_]f64{ 7.0, 10.0, 5.0 };
    try solveWithFactor(&matrix, 3, &.{ 7.0, 10.0, 5.0 }, &solution);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), solution[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 2.0), solution[1], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), solution[2], 1e-12);

    var inverse = [_]f64{0.0} ** 9;
    var workspace = [_]f64{0.0} ** 6;
    try invertFromFactor(&matrix, 3, &inverse, &workspace);
    try std.testing.expect(inverse[dense.index(0, 0, 3)] > 0.0);
    try std.testing.expect(inverse[dense.index(1, 1, 3)] > 0.0);
}
