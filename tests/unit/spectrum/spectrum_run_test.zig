const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal");

const spectrum_run = internal.spectrum.spectrum_run;
const ExpectedWorkerPrimitiveLayout = struct {
    chunk_queue_size: usize,
    error_state_size: usize,
};

const expected_worker_primitive_layout: ExpectedWorkerPrimitiveLayout = if (builtin.mode == .Debug)
    .{ .chunk_queue_size = 40, .error_state_size = 24 }
else
    .{ .chunk_queue_size = 32, .error_state_size = 8 };

test "ChunkQueue returns contiguous chunks and drains once" {
    var queue = spectrum_run.ChunkQueue.init(10, 4);

    try std.testing.expectEqual(spectrum_run.Range{ .start = 0, .end = 4 }, queue.next().?);
    try std.testing.expectEqual(spectrum_run.Range{ .start = 4, .end = 8 }, queue.next().?);
    try std.testing.expectEqual(spectrum_run.Range{ .start = 8, .end = 10 }, queue.next().?);
    try std.testing.expectEqual(@as(?spectrum_run.Range, null), queue.next());
}

test "static worker ranges cover evidence radiance work without overlap" {
    const item_count: usize = 3874;
    const worker_count: usize = 10;
    var expected_start: usize = 0;
    var min_count: usize = std.math.maxInt(usize);
    var max_count: usize = 0;

    for (0..worker_count) |worker_index| {
        const range = spectrum_run.staticRange(item_count, worker_count, worker_index);
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

test "nextStaticChunk drains a static worker range in old radiance-prefetch chunks" {
    var start: usize = 3;
    const end: usize = 22;

    try std.testing.expectEqual(
        spectrum_run.Range{ .start = 3, .end = 11 },
        spectrum_run.nextStaticChunk(&start, end).?,
    );
    try std.testing.expectEqual(
        spectrum_run.Range{ .start = 11, .end = 19 },
        spectrum_run.nextStaticChunk(&start, end).?,
    );
    try std.testing.expectEqual(
        spectrum_run.Range{ .start = 19, .end = 22 },
        spectrum_run.nextStaticChunk(&start, end).?,
    );
    try std.testing.expectEqual(@as(?spectrum_run.Range, null), spectrum_run.nextStaticChunk(&start, end));
}

test "preferred radiance worker count keeps small batches single-threaded" {
    try std.testing.expectEqual(
        @as(usize, 1),
        spectrum_run.preferredRadianceWorkerCount(spectrum_run.min_parallel_radiance_count - 1),
    );
}

test "preferred worker count honors explicit worker limits and available work" {
    try std.testing.expectEqual(
        @as(usize, 2),
        spectrum_run.preferredWorkerCountForCpuCount(1024, 32, 12, 2),
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        spectrum_run.preferredWorkerCountForCpuCount(128, 32, 12, null),
    );
    try std.testing.expectEqual(
        @as(usize, spectrum_run.max_workers),
        spectrum_run.preferredWorkerCountForCpuCount(
            spectrum_run.max_workers * 128,
            1,
            spectrum_run.max_workers * 2,
            null,
        ),
    );
}

test "FirstWorkerErrorState stores only the first worker failure" {
    const ErrorState = spectrum_run.FirstWorkerErrorState(error{
        FirstFailure,
        LaterFailure,
    });
    var state = ErrorState{};

    state.store(error.FirstFailure);
    state.store(error.LaterFailure);

    try std.testing.expectEqual(error.FirstFailure, state.err.?);
}

test "spectrum run worker primitives keep explicit layout" {
    const ErrorState = spectrum_run.FirstWorkerErrorState(error{WorkerFailed});

    try std.testing.expectEqual(@as(usize, 16), @sizeOf(spectrum_run.Range));
    try std.testing.expectEqual(expected_worker_primitive_layout.chunk_queue_size, @sizeOf(spectrum_run.ChunkQueue));
    try std.testing.expectEqual(expected_worker_primitive_layout.error_state_size, @sizeOf(ErrorState));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(spectrum_run.Range, "start"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(spectrum_run.Range, "end"));
}
