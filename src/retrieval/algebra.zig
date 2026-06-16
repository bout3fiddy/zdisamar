const std = @import("std");

pub const max_state_count: usize = 2;
const eigen_tolerance = 1.0e-18;

pub const Matrix = [max_state_count][max_state_count]f64;
pub const Vector = [max_state_count]f64;

// algebra.zig ------------------------------------------------------------------------------------------------|
// Fixed-size state-space algebra for native optimal estimation.                                          |
//                                                                                                             |
// route map                                                                                                   |
//   root.zig builds the retrieval value layer and later solver slices on top of these fixed arrays.           |
//   Pressure-profile setup reuses the dynamic tridiagonal route for profiles larger than the two retrieval    |
//   states, so retrieval state math stays two-lane.                                                           |
//                                                                                                             |
// state-space storage                                                                                         |
//   Vector is [2]f64 and Matrix is [2][2]f64. OE retrieval always uses both lanes: aerosol optical depth and  |
//   aerosol-layer mid-pressure.                                                                               |
//                                                                                                             |
// retrieval math                                                                                              |
//   Later solver code builds the Rodgers normal system and update in these arrays:                       |
//                                                                                                             |
//     G = sqrt(Sa) * Jt * Se^-1 * J * sqrt(Sa)                                                                |
//     b = sqrt(Sa) * Jt * Se^-1 * residual                                                                    |
//                                                                                                             |
//   jacobiEigenSymmetric diagonalizes symmetric G; invertSymmetric converts the posterior precision to        |
//   covariance and averaging-kernel output.                                                                   |
//                                                                                                             |
// hot path                                                                                                    |
//   The retrieval iteration runs these routines once per active start and iteration. Keep this file free of   |
//   allocators, dynamic dispatch, and product-layer owners unless max_state_count changes with benchmark      |
//   evidence.                                                                                                 |
//                                                                                                             |
// ------------------------------------------------------------------------------------------------------------|

pub fn zeroVector() Vector {
    // zeroVector ---------------------------------------------------------------------------------------------|
    // Return an all-zero fixed state vector.                                                                  |
    // --------------------------------------------------------------------------------------------------------|
    return .{0.0} ** max_state_count;
}

pub fn zeroMatrix() Matrix {
    // zeroMatrix ---------------------------------------------------------------------------------------------|
    // Return an all-zero fixed state matrix.                                                                  |
    // --------------------------------------------------------------------------------------------------------|
    return .{.{0.0} ** max_state_count} ** max_state_count;
}

pub fn identityMatrix() Matrix {
    // identityMatrix -----------------------------------------------------------------------------------------|
    // Build the fixed two-state identity matrix.                                                              |
    // --------------------------------------------------------------------------------------------------------|
    return .{ .{ 1.0, 0.0 }, .{ 0.0, 1.0 } };
}

fn symmetrize(matrix: *Matrix) void {
    // symmetrize ---------------------------------------------------------------------------------------------|
    // Average the single off-diagonal pair before symmetric eigensolve or inversion.                          |
    // --------------------------------------------------------------------------------------------------------|
    const value = 0.5 * (matrix[0][1] + matrix[1][0]);
    matrix[0][1] = value;
    matrix[1][0] = value;
}

pub fn choleskyLowerDiagonal(prior_variance: Vector, sqrt_sa: *Vector, sqrt_inv_sa: *Vector) !void {
    // choleskyLowerDiagonal ----------------------------------------------------------------------------------|
    // Convert diagonal prior covariance values into sqrt(Sa) and sqrt(Sa)^-1 lanes.                           |
    //                                                                                                         |
    // guard                                                                                                   |
    //   variance must be finite and positive because the retrieval update divides by sqrt(variance).          |
    // --------------------------------------------------------------------------------------------------------|
    inline for (0..max_state_count) |index| {
        const variance = prior_variance[index];
        if (variance <= 0.0 or !std.math.isFinite(variance)) return error.InvalidPriorCovariance;
        const root = @sqrt(variance);
        sqrt_sa[index] = root;
        sqrt_inv_sa[index] = 1.0 / root;
    }
}

pub fn jacobiEigenSymmetric(input: Matrix) struct {
    values: Vector,
    vectors: Matrix,
} {
    // jacobiEigenSymmetric -----------------------------------------------------------------------------------|
    // Diagonalize the symmetric state-space matrix used by the Rodgers transformed update.                    |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : once per OE solver update                                                                  |
    //   shape    : fixed 2x2, no heap storage                                                                 |
    //   output   : eigenvalues sorted descending with matching eigenvector columns                            |
    //                                                                                                         |
    // math                                                                                                    |
    //   One Jacobi rotation zeros the only off-diagonal pair while accumulating eigenvectors.                 |
    // --------------------------------------------------------------------------------------------------------|
    var a = input;
    symmetrize(&a);
    var vectors = identityMatrix();

    const apq = a[0][1];
    if (@abs(apq) > eigen_tolerance) {
        const app = a[0][0];
        const aqq = a[1][1];
        const tau = (aqq - app) / (2.0 * apq);
        const sign: f64 = if (tau < 0.0) -1.0 else 1.0;
        const t = sign / (@abs(tau) + @sqrt(1.0 + tau * tau));
        const c = 1.0 / @sqrt(1.0 + t * t);
        const s = t * c;

        const t_apq = t * apq;
        a[0][0] = app - t_apq;
        a[1][1] = aqq + t_apq;
        a[0][1] = 0.0;
        a[1][0] = 0.0;

        vectors[0][0] = c;
        vectors[0][1] = s;
        vectors[1][0] = -s;
        vectors[1][1] = c;
    }

    var values = Vector{ @max(a[0][0], 0.0), @max(a[1][1], 0.0) };
    sortEigenPairs(&values, &vectors);
    return .{ .values = values, .vectors = vectors };
}

fn sortEigenPairs(values: *Vector, vectors: *Matrix) void {
    // sortEigenPairs -----------------------------------------------------------------------------------------|
    // Keep eigenvalues in descending order and swap matching eigenvector columns.                             |
    // --------------------------------------------------------------------------------------------------------|
    if (values[0] >= values[1]) return;

    std.mem.swap(f64, &values[0], &values[1]);
    std.mem.swap(f64, &vectors[0][0], &vectors[0][1]);
    std.mem.swap(f64, &vectors[1][0], &vectors[1][1]);
}

pub fn matrixVector(matrix: Matrix, vector: Vector) Vector {
    // matrixVector -------------------------------------------------------------------------------------------|
    // Multiply the fixed two-state matrix rows by one state vector.                                           |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        matrix[0][0] * vector[0] + matrix[0][1] * vector[1],
        matrix[1][0] * vector[0] + matrix[1][1] * vector[1],
    };
}

pub fn transposeMatrixVector(matrix: Matrix, vector: Vector) Vector {
    // transposeMatrixVector ----------------------------------------------------------------------------------|
    // Multiply the fixed two-state matrix columns by one state vector.                                        |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        matrix[0][0] * vector[0] + matrix[1][0] * vector[1],
        matrix[0][1] * vector[0] + matrix[1][1] * vector[1],
    };
}

pub fn invertSymmetric(input: Matrix) !Matrix {
    // invertSymmetric ----------------------------------------------------------------------------------------|
    // Invert the fixed symmetric 2x2 state-space matrix.                                                      |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : final posterior covariance                                                                 |
    //   shape    : fixed 2x2, no heap storage                                                                 |
    //                                                                                                         |
    // guard                                                                                                   |
    //   det_abs <= 1.0e-24 rejects singular or badly scaled systems before normalization.                     |
    // --------------------------------------------------------------------------------------------------------|
    var a = input;
    symmetrize(&a);

    const det = a[0][0] * a[1][1] - a[0][1] * a[0][1];
    const det_abs = @abs(det);
    if (det_abs <= 1.0e-24 or !std.math.isFinite(det_abs)) return error.SingularMatrix;

    const inv_det = 1.0 / det;
    return .{
        .{ a[1][1] * inv_det, -a[0][1] * inv_det },
        .{ -a[0][1] * inv_det, a[0][0] * inv_det },
    };
}

pub fn multiply(a: Matrix, b: Matrix) Matrix {
    // multiply -----------------------------------------------------------------------------------------------|
    // Multiply two fixed two-state matrices.                                                                  |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .{
            a[0][0] * b[0][0] + a[0][1] * b[1][0],
            a[0][0] * b[0][1] + a[0][1] * b[1][1],
        },
        .{
            a[1][0] * b[0][0] + a[1][1] * b[1][0],
            a[1][0] * b[0][1] + a[1][1] * b[1][1],
        },
    };
}
