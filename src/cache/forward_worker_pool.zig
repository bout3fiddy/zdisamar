const std = @import("std");

const Allocator = std.mem.Allocator;

// forward_worker_pool.zig ------------------------------------------------------------------------------------|
// Session-retained helper-thread owner for O2 A forward prefetch phases.                                      |
//                                                                                                             |
//   Helper threads stay on product/session storage, reuse unchanged helper counts, and return null on pool    |
//   init failure so callers use the raw-spawn path.                                                           |
//                                                                                                             |
// ownership boundary                                                                                          |
//   This owner stores threads and an optional borrowed shared pool only. It stores no case, wavelength,       |
//   layer, optical, RTM, or output state, so worker scheduling cannot become a hidden physics input.          |
// ------------------------------------------------------------------------------------------------------------|

// ForwardWorkerPool ------------------------------------------------------------------------------------------|
// Owned-or-borrowed thread-pool selector retained by one O2 session.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// Debug build: size 136 B (0.133 KiB), align: 8 B                                                             |
// optimized  : size 112 B (0.109 KiB), align: 8 B                                                             |
//                                                                                                             |
// memory                                                                                                      |
// [  0..111] owned_pool          : std.Thread.Pool in Debug                                                   |
// [  0.. 87] owned_pool          : std.Thread.Pool in optimized builds                                        |
// [112..119] shared_pool         : ?*std.Thread.Pool in Debug                                                 |
// [ 88.. 95] shared_pool         : ?*std.Thread.Pool in optimized builds                                      |
// [120..127] owned_worker_threads: usize in Debug                                                             |
// [ 96..103] owned_worker_threads: usize in optimized builds                                                  |
// [128..128] owned_pool_valid    : bool in Debug                                                              |
// [104..104] owned_pool_valid    : bool in optimized builds                                                   |
// [129..135] trailing padding    : 7 B in Debug                                                               |
// [105..111] trailing padding    : 7 B in optimized builds                                                    |
//                                                                                                             |
// ownership                                                                                                   |
//   owned_pool is initialized only when owned_pool_valid is true. shared_pool is borrowed and never deinit'd. |
//   owned_worker_threads counts helper threads, equal to public worker_count - 1.                             |
pub const ForwardWorkerPool = struct {
    owned_pool: std.Thread.Pool = undefined,
    shared_pool: ?*std.Thread.Pool = null,
    owned_worker_threads: usize = 0,
    owned_pool_valid: bool = false,

    pub fn deinit(self: *ForwardWorkerPool) void {
        // ForwardWorkerPool.deinit ---------------------------------------------------------------------------|
        // Release the owned helper pool only; borrowed shared pools remain owned by their injector.           |
        // ----------------------------------------------------------------------------------------------------|
        if (self.owned_pool_valid) self.owned_pool.deinit();
        self.* = .{};
    }

    pub fn poolForWorkerCount(
        self: *ForwardWorkerPool,
        allocator: Allocator,
        worker_count: usize,
    ) ?*std.Thread.Pool {
        // ForwardWorkerPool.poolForWorkerCount ---------------------------------------------------------------|
        // Return the canonical helper pool for a requested total worker count.                                |
        //                                                                                                     |
        // route                                                                                               |
        //   worker_count <= 1        -> serial caller, no pool                                                |
        //   shared_pool set          -> borrowed pool wins                                                    |
        //   owned helper count match -> reuse retained pool                                                   |
        //   mismatch                 -> destroy pool, create worker_count - 1 helper threads                  |
        //                                                                                                     |
        // fallback                                                                                            |
        //   Pool init failure returns null. The later caller still computes the same chunks through raw       |
        //   spawns or inline fallback; only scheduling changes.                                               |
        // ----------------------------------------------------------------------------------------------------|
        if (worker_count <= 1) return null;
        if (self.shared_pool) |pool| return pool;

        const worker_thread_count = worker_count - 1;
        if (self.owned_pool_valid and self.owned_worker_threads == worker_thread_count) {
            return &self.owned_pool;
        }

        if (self.owned_pool_valid) {
            self.owned_pool.deinit();
            self.owned_pool_valid = false;
            self.owned_worker_threads = 0;
        }

        self.owned_pool.init(.{
            .allocator = allocator,
            .n_jobs = worker_thread_count,
        }) catch return null;
        self.owned_worker_threads = worker_thread_count;
        self.owned_pool_valid = true;
        return &self.owned_pool;
    }
};
// ------------------------------------------------------------------------------------------------------------|

comptime {
    const expected_size: usize = if (@import("builtin").mode == .Debug) 136 else 112;
    std.debug.assert(@sizeOf(ForwardWorkerPool) == expected_size);
    std.debug.assert(@alignOf(ForwardWorkerPool) == 8);
}
