const std = @import("std");

pub const max_state_count: usize = 3;
const eigen_tolerance = 1.0e-18;

pub const Matrix = [max_state_count][max_state_count]f64;
pub const Vector = [max_state_count]f64;

pub fn zeroVector() Vector {
    return .{0.0} ** max_state_count;
}

pub fn zeroMatrix() Matrix {
    return .{.{0.0} ** max_state_count} ** max_state_count;
}

pub fn identityMatrix(state_count: usize) Matrix {
    var result = zeroMatrix();
    for (0..state_count) |index| result[index][index] = 1.0;
    return result;
}

pub fn symmetrize(matrix: *Matrix, state_count: usize) void {
    for (0..state_count) |row| {
        for (row + 1..state_count) |col| {
            const value = 0.5 * (matrix[row][col] + matrix[col][row]);
            matrix[row][col] = value;
            matrix[col][row] = value;
        }
    }
}

pub fn choleskyLowerDiagonal(prior_variance: []const f64, sqrt_sa: *Vector, sqrt_inv_sa: *Vector) !void {
    for (prior_variance, 0..) |variance, index| {
        if (variance <= 0.0 or !std.math.isFinite(variance)) return error.InvalidPriorCovariance;
        const root = @sqrt(variance);
        sqrt_sa[index] = root;
        sqrt_inv_sa[index] = 1.0 / root;
    }
}

pub fn jacobiEigenSymmetric(input: Matrix, state_count: usize) struct {
    values: Vector,
    vectors: Matrix,
} {
    var a = input;
    symmetrize(&a, state_count);
    var vectors = identityMatrix(state_count);

    for (0..24) |_| {
        var changed = false;
        for (0..state_count) |p| {
            for (p + 1..state_count) |q| {
                const apq = a[p][q];
                if (@abs(apq) <= eigen_tolerance) continue;
                changed = true;

                const app = a[p][p];
                const aqq = a[q][q];
                const tau = (aqq - app) / (2.0 * apq);
                const sign: f64 = if (tau < 0.0) -1.0 else 1.0;
                const t = sign / (@abs(tau) + @sqrt(1.0 + tau * tau));
                const c = 1.0 / @sqrt(1.0 + t * t);
                const s = t * c;

                for (0..state_count) |k| {
                    if (k == p or k == q) continue;
                    const akp = a[k][p];
                    const akq = a[k][q];
                    a[k][p] = c * akp - s * akq;
                    a[p][k] = a[k][p];
                    a[k][q] = s * akp + c * akq;
                    a[q][k] = a[k][q];
                }

                const t_apq = t * apq;
                a[p][p] = app - t_apq;
                a[q][q] = aqq + t_apq;
                a[p][q] = 0.0;
                a[q][p] = 0.0;

                for (0..state_count) |k| {
                    const vkp = vectors[k][p];
                    const vkq = vectors[k][q];
                    vectors[k][p] = c * vkp - s * vkq;
                    vectors[k][q] = s * vkp + c * vkq;
                }
            }
        }
        if (!changed) break;
    }

    var values = zeroVector();
    for (0..state_count) |index| values[index] = @max(a[index][index], 0.0);
    sortEigenPairs(&values, &vectors, state_count);
    return .{ .values = values, .vectors = vectors };
}

fn sortEigenPairs(values: *Vector, vectors: *Matrix, state_count: usize) void {
    if (state_count <= 1) return;
    for (0..state_count - 1) |i| {
        var best = i;
        for (i + 1..state_count) |j| {
            if (values[j] > values[best]) best = j;
        }
        if (best == i) continue;
        std.mem.swap(f64, &values[i], &values[best]);
        for (0..state_count) |row| std.mem.swap(f64, &vectors[row][i], &vectors[row][best]);
    }
}

pub fn matrixVector(matrix: Matrix, vector: Vector, state_count: usize) Vector {
    var result = zeroVector();
    for (0..state_count) |row| {
        var sum: f64 = 0.0;
        for (0..state_count) |col| sum += matrix[row][col] * vector[col];
        result[row] = sum;
    }
    return result;
}

pub fn transposeMatrixVector(matrix: Matrix, vector: Vector, state_count: usize) Vector {
    var result = zeroVector();
    for (0..state_count) |col| {
        var sum: f64 = 0.0;
        for (0..state_count) |row| sum += matrix[row][col] * vector[row];
        result[col] = sum;
    }
    return result;
}

pub fn invertSymmetric(input: Matrix, state_count: usize) !Matrix {
    var a = input;
    var inverse = identityMatrix(state_count);

    for (0..state_count) |pivot_index| {
        var pivot_row = pivot_index;
        var pivot_abs = @abs(a[pivot_index][pivot_index]);
        for (pivot_index + 1..state_count) |row| {
            const candidate = @abs(a[row][pivot_index]);
            if (candidate > pivot_abs) {
                pivot_abs = candidate;
                pivot_row = row;
            }
        }
        if (pivot_abs <= 1.0e-24 or !std.math.isFinite(pivot_abs)) return error.SingularMatrix;
        if (pivot_row != pivot_index) {
            for (0..state_count) |col| {
                std.mem.swap(f64, &a[pivot_index][col], &a[pivot_row][col]);
                std.mem.swap(f64, &inverse[pivot_index][col], &inverse[pivot_row][col]);
            }
        }

        const pivot = a[pivot_index][pivot_index];
        for (0..state_count) |col| {
            a[pivot_index][col] /= pivot;
            inverse[pivot_index][col] /= pivot;
        }
        for (0..state_count) |row| {
            if (row == pivot_index) continue;
            const factor = a[row][pivot_index];
            if (factor == 0.0) continue;
            for (0..state_count) |col| {
                a[row][col] -= factor * a[pivot_index][col];
                inverse[row][col] -= factor * inverse[pivot_index][col];
            }
        }
    }
    return inverse;
}

pub fn multiply(a: Matrix, b: Matrix, state_count: usize) Matrix {
    var result = zeroMatrix();
    for (0..state_count) |row| {
        for (0..state_count) |col| {
            var sum: f64 = 0.0;
            for (0..state_count) |k| sum += a[row][k] * b[k][col];
            result[row][col] = sum;
        }
    }
    return result;
}
