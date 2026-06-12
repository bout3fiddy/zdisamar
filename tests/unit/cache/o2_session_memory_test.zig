const std = @import("std");
const builtin = @import("builtin");

const internal = @import("internal");

const o2_session_memory = internal.cache.o2_session_memory;

test "O2SessionMemory groups named reusable memory owners only" {
    var memory = o2_session_memory.O2SessionMemory.init(std.testing.allocator);
    defer memory.deinit(std.testing.allocator);

    try std.testing.expect(@hasField(o2_session_memory.O2SessionMemory, "spectrum"));
    try std.testing.expect(@hasField(o2_session_memory.O2SessionMemory, "radiance"));
    try std.testing.expect(@hasField(o2_session_memory.O2SessionMemory, "profile_lines"));
    try std.testing.expect(@hasField(o2_session_memory.O2SessionMemory, "solar_irradiance"));
    try std.testing.expect(@hasField(o2_session_memory.O2SessionMemory, "transport_workers"));
    try std.testing.expect(@hasField(o2_session_memory.O2SessionMemory, "weak_line_cutoff"));
    try std.testing.expect(!@hasField(o2_session_memory.O2SessionMemory, "scene"));
    try std.testing.expect(!@hasField(o2_session_memory.O2SessionMemory, "request"));
    try std.testing.expect(!@hasField(o2_session_memory.O2SessionMemory, "controls"));

    try memory.solar_irradiance.reserve(1);
    memory.solar_irradiance.putAssumeCapacity(760.0, 4.0);
    try std.testing.expectApproxEqAbs(4.0, memory.solar_irradiance.get(760.0) orelse return error.MissingSolar, 0.0);
}

test "O2SessionMemory layout matches named owner composition" {
    const expected_size: usize = if (builtin.mode == .Debug) 3384 else 3376;
    try std.testing.expectEqual(expected_size, @sizeOf(o2_session_memory.O2SessionMemory));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(o2_session_memory.O2SessionMemory));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(o2_session_memory.O2SessionMemory, "spectrum"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(o2_session_memory.O2SessionMemory, "radiance"));
    try std.testing.expectEqual(@as(usize, 144), @offsetOf(o2_session_memory.O2SessionMemory, "profile_lines"));
}
