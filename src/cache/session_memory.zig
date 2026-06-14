const std = @import("std");
const builtin = @import("builtin");

const forward_worker_pool = @import("forward_worker_pool.zig");
const profile_line_memory = @import("profile_line_memory.zig");
const radiance_memory = @import("radiance_memory.zig");
const solar_irradiance_memory = @import("solar_irradiance_memory.zig");
const spectrum_memory = @import("spectrum_memory.zig");
const transport_worker_memory = @import("transport_worker_memory.zig");

const Allocator = std.mem.Allocator;

// session_memory.zig -------------------------------------------------------------------------------------    |
// Named memory owners retained by one O2 forward session.                                                     |
//                                                                                                             |
// ownership boundary                                                                                          |
//   The session memory owns computed rows and reusable work arrays only. It stores no scene, request, RTM     |
//   controls, optical settings, or output formatting state.                                                   |
// ------------------------------------------------------------------------------------------------------------|

// SessionMemory -------------------------------------------------------------------------------------------   |
// Top-level allocation owner for reusable O2 A setup, spectrum, solar, workers, and transport work.           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// Debug build: size 424 B (0.414 KiB), align 8                                                                |
// optimized  : size 392 B (0.383 KiB), align 8                                                                |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 55] spectrum          : SpectrumMemory                                                               |
// [ 56..167] radiance          : RadianceMemory                                                               |
// [168..231] profile_lines     : ProfileLineValues                                                            |
// [232..271] solar_irradiance  : SolarIrradianceMemory in Debug                                               |
// [232..263] solar_irradiance  : SolarIrradianceMemory in optimized builds                                    |
// [272..407] worker_pool       : ForwardWorkerPool in Debug                                                   |
// [264..375] worker_pool       : ForwardWorkerPool in optimized builds                                        |
// [408..423] transport_workers : TransportWorkerMemoryCollection in Debug                                     |
// [376..391] transport_workers : TransportWorkerMemoryCollection in optimized builds                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   Child memory owners release their own heap storage through deinit. Worker-local transport buffers live    |
//   out-of-line in transport_workers so the session can grow from one worker to many.                         |
pub const SessionMemory = struct {
    spectrum: spectrum_memory.SpectrumMemory = .{},
    radiance: radiance_memory.RadianceMemory = .{},
    profile_lines: profile_line_memory.ProfileLineValues = .{},
    solar_irradiance: solar_irradiance_memory.SolarIrradianceMemory,
    worker_pool: forward_worker_pool.ForwardWorkerPool = .{},
    transport_workers: transport_worker_memory.TransportWorkerMemoryCollection = .{},

    pub fn init(allocator: Allocator) SessionMemory {
        // SessionMemory.init ------------------------------------------------------------------------------   |
        // Create empty child owners; hash-map backed solar memory receives the session allocator.             |
        // ----------------------------------------------------------------------------------------------------|
        return .{
            .solar_irradiance = solar_irradiance_memory.SolarIrradianceMemory.init(allocator),
        };
    }

    pub fn deinit(self: *SessionMemory, allocator: Allocator) void {
        // SessionMemory.deinit ----------------------------------------------------------------------------   |
        // Release every child memory owner in reverse hot-path dependency order.                              |
        // ----------------------------------------------------------------------------------------------------|
        self.transport_workers.deinit(allocator);
        self.worker_pool.deinit();
        self.solar_irradiance.deinit();
        self.profile_lines.deinit(allocator);
        self.radiance.deinit(allocator);
        self.spectrum.deinit(allocator);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

comptime {
    const expected_size: usize = if (@import("builtin").mode == .Debug) 424 else 392;
    if (builtin.target.os.tag != .windows) {
        std.debug.assert(@sizeOf(SessionMemory) == expected_size);
    }
}
