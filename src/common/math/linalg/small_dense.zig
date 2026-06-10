pub const Error = error{
    SingularMatrix,
    ShapeMismatch,
};

// small_dense.zig --------------------------------------------------------------------------------------------|
// Tiny dense-matrix helpers for places where the caller already owns a short row-major matrix or fixed        |
// stack value. This is not a general linear-algebra layer; it supplies indexing and direct solves used by     |
// preparation code that would be louder and slower if it routed through heap-backed matrix objects.           |
//                                                                                                             |
// called by                                                                                                   |
//   cross_sections.zig assembles polynomial normal-equation matrices with index(row, column, n)               |
//   cholesky.zig shares the same row-major indexing while factoring and solving those normal equations        |
//   unit tests cover the direct 2x2/3x3 helpers and shape checks                                              |
//                                                                                                             |
// main paths                                                                                                  |
//   index       maps a row and column into a row-major flat slice                                             |
//   setIdentity writes an identity matrix into caller-owned storage                                           |
//   trace       sums the diagonal of caller-owned storage                                                     |
//   solve2x2    solves one tiny system directly                                                               |
//   solve3x3    solves one tiny system with pivoted Gaussian elimination                                      |
//                                                                                                             |
// hot path                                                                                                    |
//   index is intentionally just row * column_count + column. Callers keep flat slices so the polynomial-fit   |
//   setup and Cholesky routines can reuse allocator-owned or stack-owned storage without wrapping each cell.  |
//                                                                                                             |
// memory                                                                                                      |
//   Fixed-size solves copy matrix/rhs values onto the stack. Slice helpers mutate caller-owned storage and    |
//   never allocate.                                                                                           |
// ------------------------------------------------------------------------------------------------------------|

pub fn index(row: usize, column: usize, column_count: usize) usize {
    return row * column_count + column;
}

pub fn setIdentity(matrix: []f64, dimension: usize) Error!void {
    if (matrix.len != dimension * dimension) return Error.ShapeMismatch;
    @memset(matrix, 0.0);
    for (0..dimension) |diag_index| {
        matrix[index(diag_index, diag_index, dimension)] = 1.0;
    }
}

pub fn trace(matrix: []const f64, dimension: usize) Error!f64 {
    if (matrix.len != dimension * dimension) return Error.ShapeMismatch;
    var total: f64 = 0.0;
    for (0..dimension) |diag_index| {
        total += matrix[index(diag_index, diag_index, dimension)];
    }
    return total;
}

pub fn solve2x2(matrix: [2][2]f64, rhs: [2]f64) Error![2]f64 {
    const det = matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0];
    if (@abs(det) < 1e-12) return Error.SingularMatrix;

    return .{
        (rhs[0] * matrix[1][1] - rhs[1] * matrix[0][1]) / det,
        (matrix[0][0] * rhs[1] - matrix[1][0] * rhs[0]) / det,
    };
}

pub fn solve3x3(matrix: [3][3]f64, rhs: [3]f64) Error![3]f64 {
    // solve3x3 -----------------------------------------------------------------------------------------------|
    // Solves one fixed 3x3 system with pivoted Gaussian elimination on stack-resident copies.                 |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : small fixed-size scientific fits                                                           |
    //   costly   : pivot selection and row elimination over three rows                                        |
    //   memory   : copies matrix and rhs onto the stack; no heap allocation                                   |
    //                                                                                                         |
    // data                                                                                                    |
    //   a is the mutable matrix copy. b carries the rhs and becomes the returned solution.                    |
    // --------------------------------------------------------------------------------------------------------|

    var a = matrix;
    var b = rhs;

    for (0..3) |pivot| {
        var best_row = pivot;
        var best_value = @abs(a[pivot][pivot]);
        for (pivot + 1..3) |row| {
            const candidate = @abs(a[row][pivot]);
            if (candidate > best_value) {
                best_row = row;
                best_value = candidate;
            }
        }
        if (best_value < 1e-12) return Error.SingularMatrix;

        if (best_row != pivot) {
            const tmp_row = a[pivot];
            a[pivot] = a[best_row];
            a[best_row] = tmp_row;

            const tmp_rhs = b[pivot];
            b[pivot] = b[best_row];
            b[best_row] = tmp_rhs;
        }

        const pivot_value = a[pivot][pivot];
        for (pivot..3) |column| a[pivot][column] /= pivot_value;
        b[pivot] /= pivot_value;

        for (0..3) |row| {
            if (row == pivot) continue;
            const factor = a[row][pivot];
            for (pivot..3) |column| {
                a[row][column] -= factor * a[pivot][column];
            }
            b[row] -= factor * b[pivot];
        }
    }

    return b;
}
