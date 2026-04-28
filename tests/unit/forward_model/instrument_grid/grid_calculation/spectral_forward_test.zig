const std = @import("std");
const internal = @import("internal");

const measurement_internal = internal.forward_model.instrument_grid.internal;
const min_parallel_forward_miss_count = measurement_internal.min_parallel_forward_miss_count;
const preferredForwardWorkerCount = measurement_internal.preferredForwardWorkerCount;

test "small forward miss batches stay single-threaded" {
    try std.testing.expectEqual(@as(usize, 1), preferredForwardWorkerCount(min_parallel_forward_miss_count - 1));
}
