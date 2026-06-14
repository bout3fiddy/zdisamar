const std = @import("std");
const builtin = @import("builtin");

const internal = @import("internal");

const session_memory = internal.cache.session_memory;

test "SessionMemory groups named reusable memory owners only" {
    var memory = session_memory.SessionMemory.init(std.testing.allocator);
    defer memory.deinit(std.testing.allocator);

    try std.testing.expect(@hasField(session_memory.SessionMemory, "spectrum"));
    try std.testing.expect(@hasField(session_memory.SessionMemory, "radiance"));
    try std.testing.expect(@hasField(session_memory.SessionMemory, "profile_lines"));
    try std.testing.expect(@hasField(session_memory.SessionMemory, "solar_irradiance"));
    try std.testing.expect(@hasField(session_memory.SessionMemory, "worker_pool"));
    try std.testing.expect(@hasField(session_memory.SessionMemory, "transport_workers"));
    try std.testing.expect(!@hasField(session_memory.SessionMemory, "scene"));
    try std.testing.expect(!@hasField(session_memory.SessionMemory, "request"));
    try std.testing.expect(!@hasField(session_memory.SessionMemory, "controls"));

    try memory.solar_irradiance.reserve(1);
    memory.solar_irradiance.putAssumeCapacity(760.0, 4.0);
    try std.testing.expectApproxEqAbs(4.0, memory.solar_irradiance.get(760.0) orelse return error.MissingSolar, 0.0);
}

test "SessionMemory layout matches named owner composition" {
    const ExpectedLayout = struct {
        size: usize,
        worker_pool_offset: usize,
        transport_workers_offset: usize,
    };
    const expected_layout = switch (builtin.mode) {
        .Debug => ExpectedLayout{
            .size = 424,
            .worker_pool_offset = 272,
            .transport_workers_offset = 408,
        },
        else => ExpectedLayout{
            .size = 392,
            .worker_pool_offset = 264,
            .transport_workers_offset = 376,
        },
    };

    try std.testing.expectEqual(@as(usize, expected_layout.size), @sizeOf(session_memory.SessionMemory));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(session_memory.SessionMemory));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(session_memory.SessionMemory, "spectrum"));
    try std.testing.expectEqual(@as(usize, 56), @offsetOf(session_memory.SessionMemory, "radiance"));
    try std.testing.expectEqual(@as(usize, 168), @offsetOf(session_memory.SessionMemory, "profile_lines"));
    try std.testing.expectEqual(@as(usize, 232), @offsetOf(session_memory.SessionMemory, "solar_irradiance"));

    try std.testing.expectEqual(
        @as(usize, expected_layout.worker_pool_offset),
        @offsetOf(session_memory.SessionMemory, "worker_pool"),
    );
    try std.testing.expectEqual(
        @as(usize, expected_layout.transport_workers_offset),
        @offsetOf(session_memory.SessionMemory, "transport_workers"),
    );
}

test "SessionMemory preserves warm per-worker memory across collection growth" {
    var memory = session_memory.SessionMemory.init(std.testing.allocator);
    defer memory.deinit(std.testing.allocator);

    try memory.transport_workers.ensureWorkerCount(std.testing.allocator, 2);
    const first_worker = memory.transport_workers.worker(0);
    try first_worker.ensureOpticsCapacity(std.testing.allocator, 5, 3);
    try first_worker.ensureCapacity(std.testing.allocator, 4, 6, 5, 3, true);

    const line_sigma_ptr = first_worker.line_sigma_cm2_per_molecule.ptr;
    const support_ptr = first_worker.support_optics.ptr;
    const order_ptr = first_worker.order_ud.ptr;

    try memory.transport_workers.ensureWorkerCount(std.testing.allocator, 2);
    try std.testing.expectEqual(line_sigma_ptr, memory.transport_workers.worker(0).line_sigma_cm2_per_molecule.ptr);
    try std.testing.expectEqual(support_ptr, memory.transport_workers.worker(0).support_optics.ptr);
    try std.testing.expectEqual(order_ptr, memory.transport_workers.worker(0).order_ud.ptr);

    try memory.transport_workers.ensureWorkerCount(std.testing.allocator, 3);
    try std.testing.expectEqual(@as(usize, 3), memory.transport_workers.workers.len);
    try std.testing.expectEqual(line_sigma_ptr, memory.transport_workers.worker(0).line_sigma_cm2_per_molecule.ptr);
    try std.testing.expectEqual(support_ptr, memory.transport_workers.worker(0).support_optics.ptr);
    try std.testing.expectEqual(order_ptr, memory.transport_workers.worker(0).order_ud.ptr);
}
