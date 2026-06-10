const std = @import("std");
const internal = @import("internal");

const work_partition = internal.forward_model.work_partition;

test "chunk queue returns contiguous chunks and drains once" {
    var queue = work_partition.ChunkQueue.init(10, 4);

    try std.testing.expectEqual(work_partition.Range{ .start = 0, .end = 4 }, queue.next().?);
    try std.testing.expectEqual(work_partition.Range{ .start = 4, .end = 8 }, queue.next().?);
    try std.testing.expectEqual(work_partition.Range{ .start = 8, .end = 10 }, queue.next().?);
    try std.testing.expectEqual(@as(?work_partition.Range, null), queue.next());
}

test "static worker ranges cover work without overlap" {
    const item_count: usize = 3874;
    const worker_count: usize = 10;
    var expected_start: usize = 0;
    var min_count: usize = std.math.maxInt(usize);
    var max_count: usize = 0;

    for (0..worker_count) |worker_index| {
        const range = work_partition.staticRange(item_count, worker_count, worker_index);
        try std.testing.expectEqual(expected_start, range.start);
        try std.testing.expect(range.end >= range.start);
        const count = range.len();
        min_count = @min(min_count, count);
        max_count = @max(max_count, count);
        expected_start = range.end;
    }

    try std.testing.expectEqual(item_count, expected_start);
    try std.testing.expect(max_count - min_count <= 1);
}

test "preferred worker count stays single-threaded below threshold" {
    try std.testing.expectEqual(@as(usize, 1), work_partition.preferredWorkerCount(31, 32));
}

test "preferred worker count honors an explicit worker limit" {
    try std.testing.expectEqual(
        @as(usize, 2),
        work_partition.preferredWorkerCountForCpuCount(1024, 32, 12, 2),
    );
}

test "preferred worker count still respects available work and hard cap" {
    try std.testing.expectEqual(
        @as(usize, 4),
        work_partition.preferredWorkerCountForCpuCount(128, 32, 12, null),
    );
    try std.testing.expectEqual(
        @as(usize, work_partition.max_workers),
        work_partition.preferredWorkerCountForCpuCount(
            work_partition.max_workers * 128,
            1,
            work_partition.max_workers * 2,
            null,
        ),
    );
}
