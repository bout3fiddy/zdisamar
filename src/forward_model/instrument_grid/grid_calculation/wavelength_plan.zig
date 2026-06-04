const instrument_types = @import("../../implementations/instrument/types.zig");

pub const inline_integration_sample_count: usize = instrument_types.default_integration_sample_count;

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: offsets_nm=16 B, weights=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: offsets_nm, weights carry references/descriptors; referenced storage is not included in size
//   count: one per wavelength sampling table
//   footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above
pub const IntegrationKernelStorage = struct {
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
};

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: offsets_nm=16 B, weights=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: offsets_nm, weights carry references/descriptors; referenced storage is not included in size
//   count: transient view resolved once before an integration loop
//   footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above
pub const IntegrationKernelSamples = struct {
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
};

const IntegrationKernelEncoding = enum(u16) {
    disabled,
    inline_samples,
    side_samples,
};

// layout(64-bit):
//   size: 88 B, align: 8 B
//   field storage: 88 B across 5 fields; largest: inline_offsets_nm=40 B, inline_weights=40 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   inline arrays: inline_offsets_nm:[5]f64=40 B, inline_weights:[5]f64=40 B
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 88 B (0.086 KiB); total = per instance * live instance count
pub const IntegrationKernelRef = struct {
    inline_offsets_nm: [inline_integration_sample_count]f64 = [_]f64{0.0} ** inline_integration_sample_count,
    inline_weights: [inline_integration_sample_count]f64 = [_]f64{0.0} ** inline_integration_sample_count,
    side_start: u32 = 0,
    sample_count: u16 = 0,
    encoding: IntegrationKernelEncoding = .disabled,

    pub inline fn enabled(self: *const IntegrationKernelRef) bool {
        return self.encoding != .disabled;
    }

    pub inline fn activeSampleCount(self: *const IntegrationKernelRef) usize {
        return if (self.enabled()) @intCast(self.sample_count) else 1;
    }

    pub inline fn samples(
        self: *const IntegrationKernelRef,
        storage: IntegrationKernelStorage,
    ) IntegrationKernelSamples {
        const count = self.activeSampleCount();
        return switch (self.encoding) {
            .disabled => .{},
            .inline_samples => .{
                .offsets_nm = self.inline_offsets_nm[0..count],
                .weights = self.inline_weights[0..count],
            },
            .side_samples => blk: {
                const start: usize = @intCast(self.side_start);
                break :blk .{
                    .offsets_nm = storage.offsets_nm[start .. start + count],
                    .weights = storage.weights[start .. start + count],
                };
            },
        };
    }

    pub inline fn offsetNm(
        self: *const IntegrationKernelRef,
        storage: IntegrationKernelStorage,
        sample_index: usize,
    ) f64 {
        return switch (self.encoding) {
            .disabled => 0.0,
            .inline_samples => self.inline_offsets_nm[sample_index],
            .side_samples => blk: {
                const start: usize = @intCast(self.side_start);
                break :blk storage.offsets_nm[start + sample_index];
            },
        };
    }

    pub inline fn weight(
        self: *const IntegrationKernelRef,
        storage: IntegrationKernelStorage,
        sample_index: usize,
    ) f64 {
        return switch (self.encoding) {
            .disabled => 1.0,
            .inline_samples => self.inline_weights[sample_index],
            .side_samples => blk: {
                const start: usize = @intCast(self.side_start);
                break :blk storage.weights[start + sample_index];
            },
        };
    }
};

// layout(64-bit):
//   size: 200 B, align: 8 B
//   field storage: 200 B across 5 fields; largest: radiance_integration=88 B, irradiance_integration=88 B, nominal_wavelength_nm=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 200 B (0.195 KiB); total = per instance * live instance count
pub const WavelengthSampling = struct {
    nominal_wavelength_nm: f64,
    radiance_wavelength_nm: f64,
    irradiance_wavelength_nm: f64,
    radiance_integration: IntegrationKernelRef,
    irradiance_integration: IntegrationKernelRef,
};

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: rows=16 B, kernel_storage=32 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: rows, kernel_storage offsets/weights carry references/descriptors; referenced storage is not included in size
//   count: transient view over owned wavelength sampling storage
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
pub const WavelengthSamplingTable = struct {
    rows: []const WavelengthSampling = &.{},
    kernel_storage: IntegrationKernelStorage = .{},
};

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: rows=16 B, kernel_offsets_nm=16 B, kernel_weights=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: rows, kernel_offsets_nm, kernel_weights carry references/descriptors; referenced storage is not included in size
//   count: one per reusable or transient wavelength plan owner
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
pub const OwnedWavelengthSampling = struct {
    rows: []WavelengthSampling = &.{},
    kernel_offsets_nm: []f64 = &.{},
    kernel_weights: []f64 = &.{},

    pub fn view(self: *const OwnedWavelengthSampling) WavelengthSamplingTable {
        return .{
            .rows = self.rows,
            .kernel_storage = .{
                .offsets_nm = self.kernel_offsets_nm,
                .weights = self.kernel_weights,
            },
        };
    }

    pub fn deinit(self: *OwnedWavelengthSampling, allocator: @import("std").mem.Allocator) void {
        allocator.free(self.rows);
        allocator.free(self.kernel_offsets_nm);
        allocator.free(self.kernel_weights);
        self.* = .{};
    }
};

// layout(64-bit):
//   size: 4 B, align: 4 B
//   field storage: start=4 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: one per nominal wavelength in a forward-miss plan
//   footprint: per instance = 4 B (0.004 KiB); dense rows point into ForwardMissPlan.sample_indices
pub const ForwardSampleIndexRef = struct {
    start: u32 = 0,
};

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: rows=16 B, sample_indices=16 B, misses=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: rows, sample_indices, and misses carry borrowed slice descriptors
//   count: one transient view per simulation plan
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
pub const ForwardMissPlan = struct {
    rows: []const ForwardSampleIndexRef = &.{},
    sample_indices: []const u32 = &.{},
    misses: []const ForwardCacheMiss = &.{},
};

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: rows=16 B, sample_indices=16 B, misses=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: rows, sample_indices, and misses own backing storage
//   count: one retained wavelength-plan cache owner
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
pub const OwnedForwardMissPlan = struct {
    rows: []ForwardSampleIndexRef = &.{},
    sample_indices: []u32 = &.{},
    misses: []ForwardCacheMiss = &.{},

    pub fn view(self: *const OwnedForwardMissPlan) ForwardMissPlan {
        return .{
            .rows = self.rows,
            .sample_indices = self.sample_indices,
            .misses = self.misses,
        };
    }

    pub fn deinit(self: *OwnedForwardMissPlan, allocator: @import("std").mem.Allocator) void {
        allocator.free(self.rows);
        allocator.free(self.sample_indices);
        allocator.free(self.misses);
        self.* = .{};
    }
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: key=8 B, wavelength_nm=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const ForwardCacheMiss = struct {
    key: u64,
    wavelength_nm: f64,
};
