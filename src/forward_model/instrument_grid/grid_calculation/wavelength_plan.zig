const instrument_types = @import("../../implementations/instrument/types.zig");

pub const inline_integration_sample_count: usize = instrument_types.default_integration_sample_count;

// wavelength_plan.zig ---------------------------------------------------------------------------------------------------|
// Compact storage types for instrument-response sampling plans. A nominal output wavelength can map to one               |
// direct forward sample or to several high-resolution samples with weights.                                              |
//                                                                                                                        |
// used by                                                                                                                |
//   wavelength_sampling.zig builds these rows                                                                            |
//   spectral_eval.zig consumes them without hashing inside the hot nominal-row loop                                      |
//                                                                                                                        |
// storage idea                                                                                                           |
//   Small kernels live inline in each row. Larger kernels point into side arrays owned by the table. This                |
//   keeps the common no-integration and five-sample cases compact while still supporting large adaptive                  |
//   kernels near strong spectral lines.                                                                                  |
// -----------------------------------------------------------------------------------------------------------------------|

// IntegrationKernelStorage ----------------------------------------------------------------------------------------------|
// Side-array storage for large instrument integration kernels shared by many nominal rows.                               |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 32 B (0.031 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] offsets_nm : []const f64                                                                                      |
// [16..31] weights    : []const f64                                                                                      |
//                                                                                                                        |
// offsets_nm and weights reference side-array samples and do not include that storage in the 32 B struct size.           |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above                               |
pub const IntegrationKernelStorage = struct {
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
};

// IntegrationKernelSamples ----------------------------------------------------------------------------------------------|
// Resolved view over either inline kernel samples or side-array samples.                                                 |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 32 B (0.031 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] offsets_nm : []const f64                                                                                      |
// [16..31] weights    : []const f64                                                                                      |
//                                                                                                                        |
// offsets_nm and weights reference borrowed samples and do not include that storage in the 32 B struct size.             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above                               |
pub const IntegrationKernelSamples = struct {
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
};

const IntegrationKernelEncoding = enum(u16) {
    disabled,
    inline_samples,
    side_samples,
};

// IntegrationKernelRef --------------------------------------------------------------------------------------------------|
// Compact kernel reference for one nominal row and one signal path. The common five-sample kernel stays                  |
// inline; larger adaptive kernels point into IntegrationKernelStorage.                                                   |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 88 B (0.086 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..39] inline_offsets_nm : [5]f64                                                                                    |
// [40..79] inline_weights    : [5]f64                                                                                    |
// [80..83] side_start        : u32                                                                                       |
// [84..85] sample_count      : u16                                                                                       |
// [86..87] encoding          : IntegrationKernelEncoding                                                                 |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 2 cache lines at 64 B per line                                                                             |
// footprint: per instance = 88 B (0.086 KiB); total = per instance * live instance count                                 |
pub const IntegrationKernelRef = struct {
    inline_offsets_nm: [inline_integration_sample_count]f64 = [_]f64{0.0} ** inline_integration_sample_count,
    inline_weights: [inline_integration_sample_count]f64 = [_]f64{0.0} ** inline_integration_sample_count,
    side_start: u32 = 0,
    sample_count: u16 = 0,
    encoding: IntegrationKernelEncoding = .disabled,

    pub inline fn enabled(self: *const IntegrationKernelRef) bool {
        // IntegrationKernelRef.enabled ----------------------------------------------------------------------------------|
        // Return whether this nominal row has an instrument integration kernel. Disabled rows use one direct             |
        // sample at the shifted channel wavelength.                                                                      |
        // ---------------------------------------------------------------------------------------------------------------|

        return self.encoding != .disabled;
    }

    pub inline fn activeSampleCount(self: *const IntegrationKernelRef) usize {
        // IntegrationKernelRef.activeSampleCount ------------------------------------------------------------------------|
        // Return the number of high-resolution samples consumed by this row. Disabled rows still consume one             |
        // direct sample.                                                                                                 |
        // ---------------------------------------------------------------------------------------------------------------|

        return if (self.enabled()) @intCast(self.sample_count) else 1;
    }

    pub inline fn samples(
        self: *const IntegrationKernelRef,
        storage: IntegrationKernelStorage,
    ) IntegrationKernelSamples {
        // IntegrationKernelRef.samples ----------------------------------------------------------------------------------|
        // Resolve this compact reference into offset and weight slices. Inline rows borrow from the struct;              |
        // side rows borrow from the table-wide side arrays.                                                              |
        // ---------------------------------------------------------------------------------------------------------------|

        const count = self.activeSampleCount();
        return switch (self.encoding) {
            .disabled => .{},
            .inline_samples => .{
                .offsets_nm = self.inline_offsets_nm[0..count],
                .weights = self.inline_weights[0..count],
            },
            .side_samples => choose_side_samples: {
                const start: usize = @intCast(self.side_start);
                break :choose_side_samples .{
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
        // IntegrationKernelRef.offsetNm ---------------------------------------------------------------------------------|
        // Read one sample offset without first materializing the slices. Used by tight loops that only need              |
        // one offset at a time.                                                                                          |
        // ---------------------------------------------------------------------------------------------------------------|

        return switch (self.encoding) {
            .disabled => 0.0,
            .inline_samples => self.inline_offsets_nm[sample_index],
            .side_samples => choose_side_offset: {
                const start: usize = @intCast(self.side_start);
                break :choose_side_offset storage.offsets_nm[start + sample_index];
            },
        };
    }

    pub inline fn weight(
        self: *const IntegrationKernelRef,
        storage: IntegrationKernelStorage,
        sample_index: usize,
    ) f64 {
        // IntegrationKernelRef.weight -----------------------------------------------------------------------------------|
        // Read one integration weight. Disabled rows use weight 1.0 so direct and integrated rows share the              |
        // same accumulation contract.                                                                                    |
        // ---------------------------------------------------------------------------------------------------------------|

        return switch (self.encoding) {
            .disabled => 1.0,
            .inline_samples => self.inline_weights[sample_index],
            .side_samples => choose_side_weight: {
                const start: usize = @intCast(self.side_start);
                break :choose_side_weight storage.weights[start + sample_index];
            },
        };
    }
};

// WavelengthSampling ----------------------------------------------------------------------------------------------------|
// One nominal output wavelength plus the radiance and irradiance high-resolution sampling contracts.                     |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 200 B (0.195 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0..  7] nominal_wavelength_nm    : f64                                                                              |
// [  8.. 15] radiance_wavelength_nm   : f64                                                                              |
// [ 16.. 23] irradiance_wavelength_nm : f64                                                                              |
// [ 24..111] radiance_integration     : IntegrationKernelRef                                                             |
// [112..199] irradiance_integration   : IntegrationKernelRef                                                             |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 4 cache lines at 64 B per line                                                                             |
// footprint: per instance = 200 B (0.195 KiB); total = per instance * live instance count                                |
pub const WavelengthSampling = struct {
    nominal_wavelength_nm: f64,
    radiance_wavelength_nm: f64,
    irradiance_wavelength_nm: f64,
    radiance_integration: IntegrationKernelRef,
    irradiance_integration: IntegrationKernelRef,
};

// WavelengthSamplingTable -----------------------------------------------------------------------------------------------|
// Borrowed table view consumed by simulation loops.                                                                      |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 48 B (0.047 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] rows           : []const WavelengthSampling                                                                   |
// [16..47] kernel_storage : IntegrationKernelStorage                                                                     |
//                                                                                                                        |
// rows and kernel_storage reference external storage and do not include it in the 48 B struct size.                      |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above                               |
pub const WavelengthSamplingTable = struct {
    rows: []const WavelengthSampling = &.{},
    kernel_storage: IntegrationKernelStorage = .{},
};

// OwnedWavelengthSampling -----------------------------------------------------------------------------------------------|
// Owned wavelength sampling rows and side-array kernel samples.                                                          |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 48 B (0.047 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] rows              : []WavelengthSampling                                                                      |
// [16..31] kernel_offsets_nm : []f64                                                                                     |
// [32..47] kernel_weights    : []f64                                                                                     |
//                                                                                                                        |
// rows, kernel_offsets_nm, and kernel_weights own heap storage not included in the 48 B struct size.                     |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above                               |
pub const OwnedWavelengthSampling = struct {
    rows: []WavelengthSampling = &.{},
    kernel_offsets_nm: []f64 = &.{},
    kernel_weights: []f64 = &.{},

    pub fn view(self: *const OwnedWavelengthSampling) WavelengthSamplingTable {
        // OwnedWavelengthSampling.view ----------------------------------------------------------------------------------|
        // Borrow the owned rows and side arrays as one read-only table for simulation.                                   |
        // ---------------------------------------------------------------------------------------------------------------|

        return .{
            .rows = self.rows,
            .kernel_storage = .{
                .offsets_nm = self.kernel_offsets_nm,
                .weights = self.kernel_weights,
            },
        };
    }

    pub fn deinit(self: *OwnedWavelengthSampling, allocator: @import("std").mem.Allocator) void {
        // OwnedWavelengthSampling.deinit --------------------------------------------------------------------------------|
        // Release wavelength-plan rows and any side-storage samples for large kernels.                                   |
        // ---------------------------------------------------------------------------------------------------------------|

        allocator.free(self.rows);
        allocator.free(self.kernel_offsets_nm);
        allocator.free(self.kernel_weights);
        self.* = .{};
    }
};

// ForwardSampleIndexRef -------------------------------------------------------------------------------------------------|
// Start offset into the dense sample_indices stream for one nominal wavelength row.                                      |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 4 B (0.004 KiB), align: 4 B                                                                                      |
//                                                                                                                        |
// memory                                                                                                                 |
// [0..3] start : u32                                                                                                     |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 4 B (0.004 KiB); dense rows point into ForwardMissPlan.sample_indices                        |
pub const ForwardSampleIndexRef = struct {
    start: u32 = 0,
};

// ForwardMissPlan -------------------------------------------------------------------------------------------------------|
// Borrowed view of unique high-resolution forward samples and per-row sample references.                                 |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 48 B (0.047 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] rows           : []const ForwardSampleIndexRef                                                                |
// [16..31] sample_indices : []const u32                                                                                  |
// [32..47] misses         : []const ForwardCacheMiss                                                                     |
//                                                                                                                        |
// rows, sample_indices, and misses reference borrowed storage not included in the 48 B struct size.                      |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above                               |
pub const ForwardMissPlan = struct {
    rows: []const ForwardSampleIndexRef = &.{},
    sample_indices: []const u32 = &.{},
    misses: []const ForwardCacheMiss = &.{},
};

// OwnedForwardMissPlan --------------------------------------------------------------------------------------------------|
// Owned forward-miss rows, row-local sample index stream, and unique miss list.                                          |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 48 B (0.047 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] rows           : []ForwardSampleIndexRef                                                                      |
// [16..31] sample_indices : []u32                                                                                        |
// [32..47] misses         : []ForwardCacheMiss                                                                           |
//                                                                                                                        |
// rows, sample_indices, and misses own heap storage not included in the 48 B struct size.                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above                               |
pub const OwnedForwardMissPlan = struct {
    rows: []ForwardSampleIndexRef = &.{},
    sample_indices: []u32 = &.{},
    misses: []ForwardCacheMiss = &.{},

    pub fn view(self: *const OwnedForwardMissPlan) ForwardMissPlan {
        // OwnedForwardMissPlan.view -------------------------------------------------------------------------------------|
        // Borrow the retained miss plan. Each row points into sample_indices, and sample_indices points into             |
        // the dense misses/result array.                                                                                 |
        // ---------------------------------------------------------------------------------------------------------------|

        return .{
            .rows = self.rows,
            .sample_indices = self.sample_indices,
            .misses = self.misses,
        };
    }

    pub fn deinit(self: *OwnedForwardMissPlan, allocator: @import("std").mem.Allocator) void {
        // OwnedForwardMissPlan.deinit -----------------------------------------------------------------------------------|
        // Release the miss rows, row-local sample-index stream, and unique forward-miss list.                            |
        // ---------------------------------------------------------------------------------------------------------------|

        allocator.free(self.rows);
        allocator.free(self.sample_indices);
        allocator.free(self.misses);
        self.* = .{};
    }
};

// ForwardCacheMiss ------------------------------------------------------------------------------------------------------|
// Unique high-resolution radiance wavelength that must run through LABOS prefetch.                                       |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 16 B (0.016 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] key           : u64                                                                                           |
// [ 8..15] wavelength_nm : f64                                                                                           |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                                 |
pub const ForwardCacheMiss = struct {
    key: u64,
    wavelength_nm: f64,
};
