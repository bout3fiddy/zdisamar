const std = @import("std");
const Types = @import("types.zig");

const Allocator = std.mem.Allocator;
const ForwardIntegratedSample = Types.ForwardIntegratedSample;

// Exact-wavelength spectral cache for repeated forward and irradiance samples.
// layout(64-bit):
//   size: 96 B, align: 8 B
//   field storage: allocator=16 B, forward=40 B, irradiance=40 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 96 B (0.094 KiB); total = per instance * live instance count
pub const SpectralEvaluationCache = struct {
    allocator: Allocator,
    forward: std.AutoHashMap(u64, ForwardIntegratedSample),
    irradiance: std.AutoHashMap(u64, f64),

    pub fn init(allocator: Allocator) SpectralEvaluationCache {
        return .{
            .allocator = allocator,
            .forward = std.AutoHashMap(u64, ForwardIntegratedSample).init(allocator),
            .irradiance = std.AutoHashMap(u64, f64).init(allocator),
        };
    }

    pub fn reset(self: *SpectralEvaluationCache) void {
        self.forward.clearRetainingCapacity();
        self.irradiance.clearRetainingCapacity();
    }

    pub fn reserveForward(self: *SpectralEvaluationCache, count: usize) Allocator.Error!void {
        try self.forward.ensureTotalCapacity(@intCast(count));
    }

    pub fn reserveIrradiance(self: *SpectralEvaluationCache, count: usize) Allocator.Error!void {
        try self.irradiance.ensureTotalCapacity(@intCast(count));
    }

    pub fn deinit(self: *SpectralEvaluationCache) void {
        self.forward.deinit();
        self.irradiance.deinit();
        self.* = undefined;
    }

    pub fn keyFor(wavelength_nm: f64) u64 {
        return @as(u64, @bitCast(wavelength_nm));
    }
};
