const std = @import("std");
const dense = @import("../../kernels/linalg/small_dense.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{
    ShapeMismatch,
    SingularVariance,
    OutOfMemory,
};

pub const DiagonalCovariance = struct {
    variances: []const f64,

    pub fn whiten(self: DiagonalCovariance, residual: []const f64, output: []f64) Error!void {
        if (self.variances.len != residual.len or output.len != residual.len) {
            return error.ShapeMismatch;
        }
        for (self.variances, residual, output) |variance, value, *slot| {
            if (!std.math.isFinite(variance) or variance <= 0.0) {
                return error.SingularVariance;
            }
            slot.* = value / std.math.sqrt(variance);
        }
    }
};

pub const DenseCovariance = struct {
    dimension: usize,
    values: []f64,
    inverse_values: []f64,

    pub fn deinit(self: *DenseCovariance, allocator: Allocator) void {
        if (self.values.len != 0) allocator.free(self.values);
        if (self.inverse_values.len != 0) allocator.free(self.inverse_values);
        self.* = undefined;
    }
};

pub fn diagonalFromSigma(allocator: Allocator, sigma: []const f64) Error!DenseCovariance {
    const dimension = sigma.len;
    const values = allocator.alloc(f64, dimension * dimension) catch return error.OutOfMemory;
    errdefer allocator.free(values);
    const inverse_values = allocator.alloc(f64, dimension * dimension) catch return error.OutOfMemory;
    errdefer allocator.free(inverse_values);

    @memset(values, 0.0);
    @memset(inverse_values, 0.0);

    for (sigma, 0..) |sample_sigma, index| {
        if (!std.math.isFinite(sample_sigma) or sample_sigma <= 0.0) {
            return error.SingularVariance;
        }
        const variance = sample_sigma * sample_sigma;
        values[dense.index(index, index, dimension)] = variance;
        inverse_values[dense.index(index, index, dimension)] = 1.0 / variance;
    }

    return .{
        .dimension = dimension,
        .values = values,
        .inverse_values = inverse_values,
    };
}

pub fn quadraticForm(inverse_covariance: []const f64, vector: []const f64) Error!f64 {
    const dimension = vector.len;
    if (inverse_covariance.len != dimension * dimension) return error.ShapeMismatch;

    var total: f64 = 0.0;
    for (0..dimension) |row| {
        var row_total: f64 = 0.0;
        for (0..dimension) |column| {
            row_total += inverse_covariance[dense.index(row, column, dimension)] * vector[column];
        }
        total += vector[row] * row_total;
    }
    return total;
}

test "diagonal covariance whitens residuals elementwise" {
    const covariance: DiagonalCovariance = .{ .variances = &[_]f64{ 4.0, 9.0 } };
    const residual = [_]f64{ 2.0, 3.0 };
    var output: [2]f64 = undefined;
    try covariance.whiten(&residual, &output);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), output[0], 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), output[1], 1e-12);
}

test "diagonal covariance rejects singular variances" {
    const covariance: DiagonalCovariance = .{ .variances = &[_]f64{0.0} };
    const residual = [_]f64{1.0};
    var output: [1]f64 = undefined;
    try std.testing.expectError(error.SingularVariance, covariance.whiten(&residual, &output));
}

test "dense covariance materializes diagonal sigma definitions" {
    var covariance = try diagonalFromSigma(std.testing.allocator, &.{ 2.0, 3.0 });
    defer covariance.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(f64, 4.0), covariance.values[dense.index(0, 0, 2)]);
    try std.testing.expectEqual(@as(f64, 9.0), covariance.values[dense.index(1, 1, 2)]);
    try std.testing.expectEqual(@as(f64, 0.25), covariance.inverse_values[dense.index(0, 0, 2)]);
    try std.testing.expectEqual(@as(f64, 1.0 / 9.0), covariance.inverse_values[dense.index(1, 1, 2)]);
}

test "quadratic form uses explicit inverse covariance matrices" {
    const inverse_covariance = [_]f64{
        4.0, 0.0,
        0.0, 9.0,
    };
    const vector = [_]f64{ 0.5, 0.25 };
    try std.testing.expectApproxEqRel(@as(f64, 1.5625), try quadraticForm(&inverse_covariance, &vector), 1.0e-12);
}
