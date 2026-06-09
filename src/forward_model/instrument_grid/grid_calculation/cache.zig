const std = @import("std");

const Allocator = std.mem.Allocator;

// cache.zig -------------------------------------------------------------------------------------------------------------|
// Per-product spectral lookup caches. The current cache is intentionally narrow: it avoids repeated solar                |
// irradiance interpolation for exact high-resolution wavelengths inside one simulation.                                  |
//                                                                                                                        |
// called by                                                                                                              |
//   spectral_eval.zig during irradiance integration                                                                      |
//   storage.zig for workspace-owned cache lifecycle                                                                      |
// -----------------------------------------------------------------------------------------------------------------------|

// SpectralEvaluationCache -----------------------------------------------------------------------------------------------|
// Exact-wavelength irradiance cache for one product simulation.                                                          |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 56 B (0.055 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] allocator  : std.mem.Allocator                                                                                |
// [16..55] irradiance : std.AutoHashMap(u64, f64)                                                                        |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 56 B (0.055 KiB); total also includes hash-map backing storage                               |
pub const SpectralEvaluationCache = struct {
    allocator: Allocator,
    irradiance: std.AutoHashMap(u64, f64),

    pub fn init(allocator: Allocator) SpectralEvaluationCache {
        // SpectralEvaluationCache.init ----------------------------------------------------------------------------------|
        // Create an empty cache. Storage allocation is delayed until a caller reserves or inserts entries.               |
        // ---------------------------------------------------------------------------------------------------------------|

        return .{
            .allocator = allocator,
            .irradiance = std.AutoHashMap(u64, f64).init(allocator),
        };
    }

    pub fn reset(self: *SpectralEvaluationCache) void {
        // SpectralEvaluationCache.reset ---------------------------------------------------------------------------------|
        // Clear values between product simulations while keeping hash-map capacity for the next run.                     |
        // ---------------------------------------------------------------------------------------------------------------|

        self.irradiance.clearRetainingCapacity();
    }

    pub fn reserveIrradiance(self: *SpectralEvaluationCache, count: usize) Allocator.Error!void {
        // SpectralEvaluationCache.reserveIrradiance ---------------------------------------------------------------------|
        // Reserve enough slots for the irradiance integration workload so hot-loop inserts do not rehash.                |
        // ---------------------------------------------------------------------------------------------------------------|

        try self.irradiance.ensureTotalCapacity(@intCast(count));
    }

    pub fn deinit(self: *SpectralEvaluationCache) void {
        // SpectralEvaluationCache.deinit --------------------------------------------------------------------------------|
        // Release the hash-map backing storage and mark the cache as unusable.                                           |
        // ---------------------------------------------------------------------------------------------------------------|

        self.irradiance.deinit();
        self.* = undefined;
    }

    pub fn keyFor(wavelength_nm: f64) u64 {
        // SpectralEvaluationCache.keyFor --------------------------------------------------------------------------------|
        // Use the exact f64 bit pattern as the cache key. Wavelength planning already produced deterministic             |
        // samples, so this avoids lossy rounding that could merge adjacent adaptive-grid wavelengths.                    |
        // ---------------------------------------------------------------------------------------------------------------|

        return @as(u64, @bitCast(wavelength_nm));
    }
};
// -----------------------------------------------------------------------------------------------------------------------|
