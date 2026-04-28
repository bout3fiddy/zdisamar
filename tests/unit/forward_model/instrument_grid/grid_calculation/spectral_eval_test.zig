const std = @import("std");
const internal = @import("internal");

const SpectralEvaluationCache = internal.kernels.transport.measurement.spectral_eval.SpectralEvaluationCache;

test "spectral cache key distinguishes adjacent adaptive samples" {
    const first = 759.637013770239;
    const second = 759.6370143839599;
    try std.testing.expect(SpectralEvaluationCache.keyFor(first) != SpectralEvaluationCache.keyFor(second));
}
