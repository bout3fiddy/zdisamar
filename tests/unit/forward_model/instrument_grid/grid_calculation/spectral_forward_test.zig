const std = @import("std");
const internal = @import("internal");

const spectral_forward = internal.forward_model.instrument_grid.spectral_forward;
const min_parallel_forward_miss_count = spectral_forward.min_parallel_forward_miss_count;
const preferredForwardWorkerCount = spectral_forward.preferredForwardWorkerCount;

test "small forward miss batches stay single-threaded" {
    try std.testing.expectEqual(@as(usize, 1), preferredForwardWorkerCount(min_parallel_forward_miss_count - 1));
}
