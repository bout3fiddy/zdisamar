const std = @import("std");

const Allocator = std.mem.Allocator;

// Exact-wavelength spectral cache for repeated irradiance samples.
// layout(64-bit):
//   size: 56 B, align: 8 B
//   field storage: allocator=16 B, irradiance=40 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 56 B (0.055 KiB); total = per instance * live instance count
pub const SpectralEvaluationCache = struct {
    allocator: Allocator,
    irradiance: std.AutoHashMap(u64, f64),

    pub fn init(allocator: Allocator) SpectralEvaluationCache {
        return .{
            .allocator = allocator,
            .irradiance = std.AutoHashMap(u64, f64).init(allocator),
        };
    }

    pub fn reset(self: *SpectralEvaluationCache) void {
        self.irradiance.clearRetainingCapacity();
    }

    pub fn reserveIrradiance(self: *SpectralEvaluationCache, count: usize) Allocator.Error!void {
        try self.irradiance.ensureTotalCapacity(@intCast(count));
    }

    pub fn deinit(self: *SpectralEvaluationCache) void {
        self.irradiance.deinit();
        self.* = undefined;
    }

    pub fn keyFor(wavelength_nm: f64) u64 {
        return @as(u64, @bitCast(wavelength_nm));
    }
};
