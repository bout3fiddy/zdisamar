pub const GaussianPrior = struct {
    mean: f64 = 0.0,
    variance: f64 = 1.0,

    pub fn residual(self: GaussianPrior, state_value: f64) f64 {
        return (state_value - self.mean) / std.math.sqrt(self.variance);
    }
};

test "gaussian prior residual is normalized by prior variance" {
    const prior: GaussianPrior = .{ .mean = 1.0, .variance = 4.0 };
    try std.testing.expectApproxEqRel(@as(f64, 1.0), prior.residual(3.0), 1e-12);
}

const std = @import("std");
