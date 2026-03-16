const std = @import("std");

pub const Error = error{
    ShapeMismatch,
    InvalidNoiseScaleFactor,
    SingularWhiteningWeight,
};

pub fn shotNoiseStd(signal: []const f64, electrons_per_count: f64, output: []f64) Error!void {
    if (signal.len != output.len) return error.ShapeMismatch;
    if (!std.math.isFinite(electrons_per_count) or electrons_per_count <= 0.0) {
        return error.InvalidNoiseScaleFactor;
    }
    for (signal, output) |sample, *slot| {
        const electrons = @max(sample * electrons_per_count, 0.0);
        slot.* = std.math.sqrt(electrons) / electrons_per_count;
    }
}

pub fn whitenResiduals(residual: []const f64, sigma: []const f64, output: []f64) Error!void {
    if (residual.len != sigma.len or residual.len != output.len) return error.ShapeMismatch;
    for (residual, sigma, output) |value, sigma_value, *slot| {
        if (!std.math.isFinite(sigma_value) or sigma_value <= 0.0) {
            return error.SingularWhiteningWeight;
        }
        slot.* = value / sigma_value;
    }
}

test "noise helpers estimate shot-noise sigma and whiten residuals" {
    const signal = [_]f64{ 100.0, 400.0 };
    var sigma: [2]f64 = undefined;
    try shotNoiseStd(&signal, 2.0, &sigma);

    const residual = [_]f64{ 5.0, 10.0 };
    var whitened: [2]f64 = undefined;
    try whitenResiduals(&residual, &sigma, &whitened);

    try std.testing.expect(sigma[1] > sigma[0]);
    try std.testing.expect(whitened[0] > 0.0);
}

test "noise helpers reject invalid scale factors and singular whitening weights" {
    const signal = [_]f64{100.0};
    var sigma: [1]f64 = undefined;
    try std.testing.expectError(error.InvalidNoiseScaleFactor, shotNoiseStd(&signal, 0.0, &sigma));

    const residual = [_]f64{5.0};
    const invalid_sigma = [_]f64{0.0};
    var whitened: [1]f64 = undefined;
    try std.testing.expectError(error.SingularWhiteningWeight, whitenResiduals(&residual, &invalid_sigma, &whitened));
}
