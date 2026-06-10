const std = @import("std");
const dense = @import("small_dense.zig");

// cholesky.zig -----------------------------------------------------------------------------------------------|
// Cholesky factor/solve route for the small symmetric positive-definite normal equations built while          |
// preparing reference cross sections. The production path is narrow: cross_sections.zig builds a weighted     |
// polynomial fit system, duplicates the normal matrix, factors that copy in place, and solves for baseline    |
// coefficients.                                                                                               |
//                                                                                                             |
// The code stays slice-based because the caller already owns the fit scratch: matrix, rhs, factor copy, and   |
// output all move through the same small row-major route.                                                     |
//                                                                                                             |
// called by                                                                                                   |
//   input/reference/cross_sections.zig:differentialVector removes a weighted polynomial baseline from         |
//     diagnostic and effective cross-section vectors.                                                         |
//   effectiveCrossSectionFromSensitivity normalizes sensitivity by air mass, then uses the same differential  |
//     fit route.                                                                                              |
//   unit tests cover the reusable factor + solve contract and shape/positive-definite failures.               |
//                                                                                                             |
// route map                                                                                                   |
//   cross_sections.differentialVector                                                                         |
//     -> assembles normal[row,column] and rhs[row] from weighted wavelength powers                            |
//     -> duplicates normal into factor so the original assembled system can stay conceptually separate        |
//     -> factorInPlace(factor, term_count)                                                                    |
//     -> solveWithFactor(factor, term_count, rhs, coeffs)                                                     |
//     -> evaluates the polynomial baseline and subtracts it from the result vector                            |
//                                                                                                             |
// exported paths                                                                                              |
//   factorInPlace    overwrites a row-major square matrix with its lower-triangular Cholesky factor           |
//   solveWithFactor  solves one rhs against a previously factored matrix                                      |
//                                                                                                             |
// memory                                                                                                      |
//   Callers own matrix, rhs, output, and scratch slices. factorInPlace mutates the factor slice; callers      |
//   that still need the original normal matrix must copy it first. solveWithFactor reuses out as the          |
//   intermediate y vector before writing x. This file does not allocate.                                      |
//                                                                                                             |
// failure model                                                                                               |
//   ShapeMismatch means the caller supplied inconsistent slice lengths. NotPositiveDefinite means the         |
//   normal-equation system is singular or numerically unsafe for this SPD route.                              |
// ------------------------------------------------------------------------------------------------------------|

pub const Error = error{
    NotPositiveDefinite,
    ShapeMismatch,
};

pub fn factorInPlace(matrix: []f64, dimension: usize) Error!void {
    // factorInPlace ------------------------------------------------------------------------------------------|
    // Factors one row-major square matrix in place into a lower-triangular Cholesky factor.                   |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : polynomial baseline fits in cross-section preparation                                      |
    //   costly   : inner product over the already factored lower triangle                                     |
    //   memory   : caller-owned row-major matrix; upper triangle is zeroed after each row                     |
    //                                                                                                         |
    // data                                                                                                    |
    //   index(row, column, dimension) maps matrix cells to the flat row-major slice.                          |
    // --------------------------------------------------------------------------------------------------------|

    if (matrix.len != dimension * dimension) return Error.ShapeMismatch;

    for (0..dimension) |row| {
        for (0..row + 1) |column| {
            var sum = matrix[dense.index(row, column, dimension)];
            var inner: usize = 0;
            while (inner < column) : (inner += 1) {
                sum -= matrix[dense.index(row, inner, dimension)] *
                    matrix[dense.index(column, inner, dimension)];
            }

            if (row == column) {
                if (sum <= 0.0 or !std.math.isFinite(sum)) return Error.NotPositiveDefinite;
                matrix[dense.index(row, column, dimension)] = std.math.sqrt(sum);
            } else {
                matrix[dense.index(row, column, dimension)] = sum /
                    matrix[dense.index(column, column, dimension)];
            }
        }

        for (row + 1..dimension) |column| {
            matrix[dense.index(row, column, dimension)] = 0.0;
        }
    }
}

pub fn solveWithFactor(
    factor: []const f64,
    dimension: usize,
    rhs: []const f64,
    out: []f64,
) Error!void {
    // solveWithFactor ----------------------------------------------------------------------------------------|
    // Solves one rhs vector against a previously computed lower-triangular Cholesky factor.                   |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : coefficient solves after the polynomial normal matrix has been factored                    |
    //   costly   : forward substitution followed by back substitution                                         |
    //   memory   : caller-owned rhs and output slices; output is reused for the intermediate y vector         |
    //                                                                                                         |
    // data                                                                                                    |
    //   factor is row-major. The upper triangle is expected to be zero from factorInPlace.                    |
    // --------------------------------------------------------------------------------------------------------|

    if (factor.len != dimension * dimension or rhs.len != dimension or out.len != dimension) {
        return Error.ShapeMismatch;
    }

    var y_index: usize = 0;
    while (y_index < dimension) : (y_index += 1) {
        var value = rhs[y_index];
        var inner: usize = 0;
        while (inner < y_index) : (inner += 1) {
            value -= factor[dense.index(y_index, inner, dimension)] * out[inner];
        }
        out[y_index] = value / factor[dense.index(y_index, y_index, dimension)];
    }

    var x_index: usize = dimension;
    while (x_index > 0) {
        x_index -= 1;
        var value = out[x_index];
        var inner = x_index + 1;
        while (inner < dimension) : (inner += 1) {
            value -= factor[dense.index(inner, x_index, dimension)] * out[inner];
        }
        out[x_index] = value / factor[dense.index(x_index, x_index, dimension)];
    }
}
