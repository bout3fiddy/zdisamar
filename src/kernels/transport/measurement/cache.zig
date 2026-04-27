const std = @import("std");
const spectral_forward = @import("spectral_forward.zig");

const Allocator = std.mem.Allocator;
const ForwardIntegratedSample = spectral_forward.ForwardIntegratedSample;

// Exact-wavelength spectral cache for repeated forward and irradiance samples.
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

    pub fn deinit(self: *SpectralEvaluationCache) void {
        self.forward.deinit();
        self.irradiance.deinit();
        self.* = undefined;
    }

    pub fn keyFor(wavelength_nm: f64) u64 {
        return @as(u64, @bitCast(wavelength_nm));
    }
};
