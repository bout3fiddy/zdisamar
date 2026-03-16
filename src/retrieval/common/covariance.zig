const std = @import("std");

pub const Error = error{
    ShapeMismatch,
    SingularVariance,
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
