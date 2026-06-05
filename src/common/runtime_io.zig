const std = @import("std");

pub const RuntimeIo = struct {
    threaded: std.Io.Threaded,

    pub fn init(allocator: std.mem.Allocator) RuntimeIo {
        return .{
            .threaded = std.Io.Threaded.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *RuntimeIo) void {
        self.threaded.deinit();
    }

    pub fn io(self: *RuntimeIo) std.Io {
        return self.threaded.io();
    }
};

pub const Timer = struct {
    io: std.Io,
    start_timestamp: std.Io.Timestamp,

    pub fn start(io: std.Io) Timer {
        return .{
            .io = io,
            .start_timestamp = std.Io.Clock.boot.now(io),
        };
    }

    pub fn read(self: Timer) u64 {
        const elapsed_ns = self.start_timestamp.durationTo(std.Io.Clock.boot.now(self.io)).toNanoseconds();
        if (elapsed_ns <= 0) return 0;
        return std.math.cast(u64, elapsed_ns) orelse std.math.maxInt(u64);
    }
};
