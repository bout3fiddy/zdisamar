pub const Error = error{
    SingularMatrix,
    ShapeMismatch,
};

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
