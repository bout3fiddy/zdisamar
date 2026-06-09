const std = @import("std");

const Allocator = std.mem.Allocator;

// cache.zig -------------------------------------------------------------------------------------------------------------|
// Per-product spectral lookup cache for irradiance integration. It deliberately caches one thing: solar                  |
// irradiance at exact high-resolution wavelengths inside the active simulation.                                          |
//                                                                                                                        |
// called by                                                                                                              |
//   storage.zig creates or reuses one SpectralEvaluationCache for a ProductStorage-backed run, then resets values        |
//   while keeping capacity. simulate.zig reserves the expected irradiance integration workload before the gather.        |
//   spectral_eval.zig looks up E0(lambda) while integrating nominal irradiance rows. wavelength_sampling.zig uses        |
//   the same key shape while building deduplicated sample plans.                                                         |
//                                                                                                                        |
// hot path                                                                                                               |
//   Integrated irradiance may revisit the same high-resolution wavelength from neighboring nominal rows. The cache       |
//   avoids repeated interpolation through operational solar support or reference solar data. reserveIrradiance keeps     |
//   hash-map growth out of the integration loop when simulate.zig can predict the sample count.                          |
//                                                                                                                        |
// key contract                                                                                                           |
//   keyFor uses the exact f64 bit pattern, not rounded wavelength bins. The wavelength plan is deterministic and the     |
//   adaptive grid can place close but distinct support wavelengths; rounding would risk merging real samples.            |
//                                                                                                                        |
// memory                                                                                                                 |
//   SpectralEvaluationCache is a 56 B owner header over AutoHashMap storage. reset clears values between product         |
//   simulations so old irradiance cannot leak, while retaining allocation for repeated retrieval/session runs.           |
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
