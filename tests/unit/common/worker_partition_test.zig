const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal");

const worker_partition = internal.common.worker_partition;

const ExpectedWorkerPrimitiveLayout = struct {
    chunk_queue_size: usize,
    error_state_size: usize,
};

const expected_worker_primitive_layout: ExpectedWorkerPrimitiveLayout = if (builtin.mode == .Debug)
    .{ .chunk_queue_size = 40, .error_state_size = 24 }
else
    .{ .chunk_queue_size = 32, .error_state_size = 8 };

test "ChunkQueue returns contiguous chunks and drains once" {
    var queue = worker_partition.ChunkQueue.init(10, 4);

    try std.testing.expectEqual(worker_partition.Range{ .start = 0, .end = 4 }, queue.next().?);
    try std.testing.expectEqual(worker_partition.Range{ .start = 4, .end = 8 }, queue.next().?);
    try std.testing.expectEqual(worker_partition.Range{ .start = 8, .end = 10 }, queue.next().?);
    try std.testing.expectEqual(@as(?worker_partition.Range, null), queue.next());
}

test "static worker ranges cover evidence radiance work without overlap" {
    const item_count: usize = 3874;
    const worker_count: usize = 10;
    var expected_start: usize = 0;
    var min_count: usize = std.math.maxInt(usize);
    var max_count: usize = 0;

    for (0..worker_count) |worker_index| {
        const range = worker_partition.staticRange(item_count, worker_count, worker_index);
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

test "nextStaticChunk drains a static worker range in caller-selected chunks" {
    var start: usize = 3;
    const end: usize = 22;
    const chunk_size: usize = 8;

    try std.testing.expectEqual(
        worker_partition.Range{ .start = 3, .end = 11 },
        worker_partition.nextStaticChunk(&start, end, chunk_size).?,
    );
    try std.testing.expectEqual(
        worker_partition.Range{ .start = 11, .end = 19 },
        worker_partition.nextStaticChunk(&start, end, chunk_size).?,
    );
    try std.testing.expectEqual(
        worker_partition.Range{ .start = 19, .end = 22 },
        worker_partition.nextStaticChunk(&start, end, chunk_size).?,
    );
    try std.testing.expectEqual(
        @as(?worker_partition.Range, null),
        worker_partition.nextStaticChunk(&start, end, chunk_size),
    );
}

test "preferred worker count honors explicit limits and available work" {
    try std.testing.expectEqual(
        @as(usize, 2),
        worker_partition.preferredWorkerCountForCpuCount(1024, 32, 12, 2),
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        worker_partition.preferredWorkerCountForCpuCount(128, 32, 12, null),
    );
    try std.testing.expectEqual(
        @as(usize, worker_partition.max_workers),
        worker_partition.preferredWorkerCountForCpuCount(
            worker_partition.max_workers * 128,
            1,
            worker_partition.max_workers * 2,
            null,
        ),
    );
}

test "FirstWorkerErrorState stores only the first worker failure" {
    const ErrorState = worker_partition.FirstWorkerErrorState(error{
        FirstFailure,
        LaterFailure,
    });
    var state = ErrorState{};

    state.store(error.FirstFailure);
    state.store(error.LaterFailure);

    try std.testing.expectEqual(error.FirstFailure, state.err.?);
}

test "runWorkers runs a single worker inline" {
    var run_counts = [_]usize{0};
    var workers = [_]RunWorker{
        .{ .index = 0, .run_counts = run_counts[0..] },
    };

    worker_partition.runWorkers(null, workers[0..], runWorkerMain);

    try std.testing.expectEqual(@as(usize, 1), run_counts[0]);
}

test "runWorkers raw path runs every worker exactly once" {
    var run_counts = [_]usize{ 0, 0, 0, 0 };
    var workers = [_]RunWorker{
        .{ .index = 0, .run_counts = run_counts[0..] },
        .{ .index = 1, .run_counts = run_counts[0..] },
        .{ .index = 2, .run_counts = run_counts[0..] },
        .{ .index = 3, .run_counts = run_counts[0..] },
    };

    worker_partition.runWorkers(null, workers[0..], runWorkerMain);

    for (run_counts) |count| {
        try std.testing.expectEqual(@as(usize, 1), count);
    }
}

test "runWorkers raw path falls back inline when helper spawn fails" {
    worker_partition.testing.force_raw_spawn_failure.store(true, .seq_cst);
    defer worker_partition.testing.force_raw_spawn_failure.store(false, .seq_cst);

    var run_counts = [_]usize{ 0, 0, 0, 0 };
    var workers = [_]RunWorker{
        .{ .index = 0, .run_counts = run_counts[0..] },
        .{ .index = 1, .run_counts = run_counts[0..] },
        .{ .index = 2, .run_counts = run_counts[0..] },
        .{ .index = 3, .run_counts = run_counts[0..] },
    };

    worker_partition.runWorkers(null, workers[0..], runWorkerMain);

    for (run_counts) |count| {
        try std.testing.expectEqual(@as(usize, 1), count);
    }
}

test "runWorkers pool path runs every worker exactly once" {
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{
        .allocator = std.testing.allocator,
        .n_jobs = 2,
    });
    defer pool.deinit();

    var run_counts = [_]usize{ 0, 0, 0, 0 };
    var workers = [_]RunWorker{
        .{ .index = 0, .run_counts = run_counts[0..] },
        .{ .index = 1, .run_counts = run_counts[0..] },
        .{ .index = 2, .run_counts = run_counts[0..] },
        .{ .index = 3, .run_counts = run_counts[0..] },
    };

    worker_partition.runWorkers(&pool, workers[0..], runWorkerMain);

    for (run_counts) |count| {
        try std.testing.expectEqual(@as(usize, 1), count);
    }
}

test "runWorkers lets workers capture the first failure after join" {
    const ErrorState = worker_partition.FirstWorkerErrorState(error{
        FirstFailure,
        LaterFailure,
    });
    var error_state = ErrorState{};
    var workers = [_]ErrorWorker{
        .{ .index = 0, .error_state = &error_state },
        .{ .index = 1, .error_state = &error_state },
        .{ .index = 2, .error_state = &error_state },
    };

    worker_partition.runWorkers(null, workers[0..], errorWorkerMain);

    try std.testing.expect(error_state.err != null);
}

test "worker partition primitives keep explicit layout" {
    const ErrorState = worker_partition.FirstWorkerErrorState(error{WorkerFailed});

    try std.testing.expectEqual(@as(usize, 16), @sizeOf(worker_partition.Range));
    try std.testing.expectEqual(
        expected_worker_primitive_layout.chunk_queue_size,
        @sizeOf(worker_partition.ChunkQueue),
    );
    try std.testing.expectEqual(expected_worker_primitive_layout.error_state_size, @sizeOf(ErrorState));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(worker_partition.Range, "start"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(worker_partition.Range, "end"));
}

const RunWorker = struct {
    index: usize,
    run_counts: []usize,
};

fn runWorkerMain(worker: *RunWorker) void {
    // runWorkerMain ------------------------------------------------------------------------------------------|
    // Mark the worker index as executed for runWorkers orchestration tests.                                   |
    // --------------------------------------------------------------------------------------------------------|
    worker.run_counts[worker.index] += 1;
}

const ErrorWorker = struct {
    index: usize,
    error_state: *worker_partition.FirstWorkerErrorState(error{
        FirstFailure,
        LaterFailure,
    }),
};

fn errorWorkerMain(worker: *ErrorWorker) void {
    // errorWorkerMain ----------------------------------------------------------------------------------------|
    // Store two possible failures so tests can verify shared first-error capture after join.                  |
    // --------------------------------------------------------------------------------------------------------|
    if (worker.index == 0) worker.error_state.store(error.FirstFailure);
    if (worker.index == 1) worker.error_state.store(error.LaterFailure);
}
