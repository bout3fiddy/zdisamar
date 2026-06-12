const std = @import("std");

const profile_line_memory = @import("profile_line_memory.zig");
const radiance_memory = @import("radiance_memory.zig");
const solar_irradiance_memory = @import("solar_irradiance_memory.zig");
const spectrum_memory = @import("spectrum_memory.zig");
const transport_worker_memory = @import("transport_worker_memory.zig");
const weak_line_cutoff_memory = @import("weak_line_cutoff_memory.zig");

const Allocator = std.mem.Allocator;

// o2_session_memory.zig ------------------------------------------------------------------------------------- |
// Named memory owners retained by one O2 forward session.                                                     |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports the allowed WP3 session-cache shape from the explicit-dataflow plan. Each field names retained      |
//   data directly instead of recreating the old broad `ProductStorage` or `SpectralEvaluationCache` owner.    |
//                                                                                                             |
// ownership boundary                                                                                          |
//   The session memory owns computed rows and reusable work arrays only. It stores no scene, request, RTM     |
//   controls, optical settings, or output formatting state.                                                   |
// ------------------------------------------------------------------------------------------------------------|

// O2SessionMemory ------------------------------------------------------------------------------------------- |
// Top-level allocation owner for reusable O2 A setup, spectrum, solar, and transport work.                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// Debug build: size 3472 B (3.391 KiB), align 8                                                               |
// optimized  : size 3464 B (3.383 KiB), align 8                                                               |
//                                                                                                             |
// memory                                                                                                      |
// [   0..  47] spectrum          : SpectrumMemory                                                             |
// [  48.. 143] radiance          : RadianceMemory                                                             |
// [ 144.. 207] profile_lines     : ProfileLineValues                                                          |
// [ 208.. 247] solar_irradiance  : SolarIrradianceMemory in Debug                                             |
// [ 208.. 239] solar_irradiance  : SolarIrradianceMemory in optimized builds                                  |
// [ 248..3439] transport_workers : TransportWorkerMemory in Debug                                             |
// [ 240..3431] transport_workers : TransportWorkerMemory in optimized builds                                  |
// [3440..3471] weak_line_cutoff  : WeakLineCutoffMemory in Debug                                              |
// [3432..3463] weak_line_cutoff  : WeakLineCutoffMemory in optimized builds                                   |
//                                                                                                             |
// referenced storage                                                                                          |
//   Child memory owners release their own heap storage through deinit.                                        |
pub const O2SessionMemory = struct {
    spectrum: spectrum_memory.SpectrumMemory = .{},
    radiance: radiance_memory.RadianceMemory = .{},
    profile_lines: profile_line_memory.ProfileLineValues = .{},
    solar_irradiance: solar_irradiance_memory.SolarIrradianceMemory,
    transport_workers: transport_worker_memory.TransportWorkerMemory = .{},
    weak_line_cutoff: weak_line_cutoff_memory.WeakLineCutoffMemory = .{},

    pub fn init(allocator: Allocator) O2SessionMemory {
        // O2SessionMemory.init ------------------------------------------------------------------------------ |
        // Create empty child owners; hash-map backed solar memory receives the session allocator.             |
        // ----------------------------------------------------------------------------------------------------|
        return .{
            .solar_irradiance = solar_irradiance_memory.SolarIrradianceMemory.init(allocator),
        };
    }

    pub fn deinit(self: *O2SessionMemory, allocator: Allocator) void {
        // O2SessionMemory.deinit ---------------------------------------------------------------------------- |
        // Release every child memory owner in reverse hot-path dependency order.                              |
        // ----------------------------------------------------------------------------------------------------|
        self.weak_line_cutoff.deinit(allocator);
        self.transport_workers.deinit(allocator);
        self.solar_irradiance.deinit();
        self.profile_lines.deinit(allocator);
        self.radiance.deinit(allocator);
        self.spectrum.deinit(allocator);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

comptime {
    const expected_size: usize = if (@import("builtin").mode == .Debug) 3472 else 3464;
    std.debug.assert(@sizeOf(O2SessionMemory) == expected_size);
}
