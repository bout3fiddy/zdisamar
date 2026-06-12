const std = @import("std");
const builtin = @import("builtin");

const internal = @import("internal");

const forward_worker_pool = internal.cache.forward_worker_pool;

test "ForwardWorkerPool layout matches retained pool owner contract" {
    const ExpectedLayout = struct {
        size: usize,
        shared_pool_offset: usize,
        owned_worker_threads_offset: usize,
        owned_pool_valid_offset: usize,
    };
    const expected_layout = switch (builtin.mode) {
        .Debug => ExpectedLayout{
            .size = 136,
            .shared_pool_offset = 112,
            .owned_worker_threads_offset = 120,
            .owned_pool_valid_offset = 128,
        },
        else => ExpectedLayout{
            .size = 112,
            .shared_pool_offset = 88,
            .owned_worker_threads_offset = 96,
            .owned_pool_valid_offset = 104,
        },
    };

    try std.testing.expectEqual(@as(usize, expected_layout.size), @sizeOf(forward_worker_pool.ForwardWorkerPool));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(forward_worker_pool.ForwardWorkerPool));
    try std.testing.expectEqual(
        @as(usize, 0),
        @offsetOf(forward_worker_pool.ForwardWorkerPool, "owned_pool"),
    );
    try std.testing.expectEqual(
        @as(usize, expected_layout.shared_pool_offset),
        @offsetOf(forward_worker_pool.ForwardWorkerPool, "shared_pool"),
    );
    try std.testing.expectEqual(
        @as(usize, expected_layout.owned_worker_threads_offset),
        @offsetOf(forward_worker_pool.ForwardWorkerPool, "owned_worker_threads"),
    );
    try std.testing.expectEqual(
        @as(usize, expected_layout.owned_pool_valid_offset),
        @offsetOf(forward_worker_pool.ForwardWorkerPool, "owned_pool_valid"),
    );
}

test "ForwardWorkerPool returns null for serial worker counts" {
    var pool_owner = forward_worker_pool.ForwardWorkerPool{};
    defer pool_owner.deinit();

    try std.testing.expect(pool_owner.poolForWorkerCount(std.testing.allocator, 0) == null);
    try std.testing.expect(pool_owner.poolForWorkerCount(std.testing.allocator, 1) == null);
    try std.testing.expect(!pool_owner.owned_pool_valid);
}

test "ForwardWorkerPool reuses owned pool by helper-thread count" {
    var pool_owner = forward_worker_pool.ForwardWorkerPool{};
    defer pool_owner.deinit();

    const first = pool_owner.poolForWorkerCount(std.testing.allocator, 3) orelse return error.MissingPool;
    try std.testing.expect(pool_owner.owned_pool_valid);
    try std.testing.expectEqual(@as(usize, 2), pool_owner.owned_worker_threads);

    const second = pool_owner.poolForWorkerCount(std.testing.allocator, 3) orelse return error.MissingPool;
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(usize, 2), pool_owner.owned_worker_threads);

    _ = pool_owner.poolForWorkerCount(std.testing.allocator, 2) orelse return error.MissingPool;
    try std.testing.expect(pool_owner.owned_pool_valid);
    try std.testing.expectEqual(@as(usize, 1), pool_owner.owned_worker_threads);
}

test "ForwardWorkerPool borrowed shared pool wins and remains borrowed" {
    var shared: std.Thread.Pool = undefined;
    try shared.init(.{
        .allocator = std.testing.allocator,
        .n_jobs = 1,
    });
    defer shared.deinit();

    var pool_owner = forward_worker_pool.ForwardWorkerPool{
        .shared_pool = &shared,
    };
    defer pool_owner.deinit();

    const selected = pool_owner.poolForWorkerCount(std.testing.allocator, 4) orelse return error.MissingPool;
    try std.testing.expectEqual(&shared, selected);
    try std.testing.expect(!pool_owner.owned_pool_valid);
    try std.testing.expectEqual(@as(usize, 0), pool_owner.owned_worker_threads);
}

test "ForwardWorkerPool degrades to null when owned pool allocation fails" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });

    var pool_owner = forward_worker_pool.ForwardWorkerPool{};
    defer pool_owner.deinit();

    try std.testing.expect(pool_owner.poolForWorkerCount(failing_allocator.allocator(), 2) == null);
    try std.testing.expect(!pool_owner.owned_pool_valid);
    try std.testing.expectEqual(@as(usize, 0), pool_owner.owned_worker_threads);
}
