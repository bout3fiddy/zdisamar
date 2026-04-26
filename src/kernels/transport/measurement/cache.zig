//! Purpose:
//!   Own reusable spectral-evaluation cache storage for measurement sweeps.
//!
//! Physics:
//!   Caches exact-wavelength transport and irradiance samples so repeated
//!   instrument-kernel support points are solved once per run.
//!
//! Vendor:
//!   `measurement spectral evaluation` stage
//!
//! Design:
//!   Keep cache ownership out of `spectral_eval.zig` so `SummaryWorkspace` can
//!   retain hash-map capacity across repeated prepared runs without creating an
//!   import cycle.

const std = @import("std");
const spectral_forward = @import("spectral_forward.zig");

const Allocator = std.mem.Allocator;
const ForwardIntegratedSample = spectral_forward.ForwardIntegratedSample;

/// Exact-wavelength spectral cache for repeated forward and irradiance samples.
pub const SpectralEvaluationCache = struct {
    allocator: Allocator,
    forward: std.AutoHashMap(u64, ForwardIntegratedSample),
    irradiance: std.AutoHashMap(u64, f64),

    /// Purpose:
    ///   Initialize the cache buckets used by measurement-space sweeps.
    pub fn init(allocator: Allocator) SpectralEvaluationCache {
        return .{
            .allocator = allocator,
            .forward = std.AutoHashMap(u64, ForwardIntegratedSample).init(allocator),
            .irradiance = std.AutoHashMap(u64, f64).init(allocator),
        };
    }

    /// Purpose:
    ///   Clear one run's values while retaining allocated hash-map capacity.
    pub fn reset(self: *SpectralEvaluationCache) void {
        self.forward.clearRetainingCapacity();
        self.irradiance.clearRetainingCapacity();
    }

    /// Purpose:
    ///   Release both spectral cache maps.
    pub fn deinit(self: *SpectralEvaluationCache) void {
        self.forward.deinit();
        self.irradiance.deinit();
        self.* = undefined;
    }

    /// Purpose:
    ///   Convert an exact finite wavelength value into the cache key space.
    pub fn keyFor(wavelength_nm: f64) u64 {
        return @as(u64, @bitCast(wavelength_nm));
    }
};
