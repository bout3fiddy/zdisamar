const std = @import("std");

pub fn FirstWorkerErrorState(comptime ErrorSet: type) type {

    // FirstWorkerErrorState

    // Shared first-error slot for parallel workers. Workers only write on failure, so the mutex
    // guards a cold path while keeping the success path free of atomics or cross-worker
    // coordination.

    // layout(64-bit, ErrorSet with one or more errors)
    // size: 24 B (0.023 KiB), align: 8 B

    // memory
    // [ 0..15] mutex   : std.Thread.Mutex
    // [16..17] err     : ?ErrorSet
    // [18..23] padding : 6 B

    // footprint: one slot per parallel operation, shared by that operation's workers
    return struct {
        mutex: std.Thread.Mutex = .{},
        err: ?ErrorSet = null,

        pub fn store(self: *@This(), err: ErrorSet) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const has_error = self.err != null;
            if (!has_error) self.err = err;
        }
    };
}
