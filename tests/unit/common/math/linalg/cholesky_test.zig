const std = @import("std");
const internal = @import("internal");

const cholesky = internal.common.math.linalg.cholesky;

const factorInPlace = cholesky.factorInPlace;
const solveWithFactor = cholesky.solveWithFactor;

test "cholesky factors and solves dense SPD systems" {
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
}

test "cholesky rejects inconsistent slice shapes" {
    var matrix = [_]f64{
        1.0, 0.0,
        0.0, 1.0,
    };
    var output = [_]f64{0.0} ** 2;

    try std.testing.expectError(error.ShapeMismatch, factorInPlace(matrix[0..3], 2));
    try std.testing.expectError(error.ShapeMismatch, solveWithFactor(&matrix, 2, &.{1.0}, &output));
}

test "cholesky rejects non positive-definite systems" {
    var matrix = [_]f64{
        1.0, 2.0,
        2.0, 1.0,
    };

    try std.testing.expectError(error.NotPositiveDefinite, factorInPlace(&matrix, 2));
}
