const std = @import("std");

const telemetry = @import("../instrumentation/telemetry.zig");

pub const inline_integration_sample_count: usize = 5;

// sampling_table.zig ----------------------------------------------------------------------------------------  |
// Compact instrument-response rows for the spectrum layer.                                                     |
//                                                                                                              |
// provenance                                                                                                   |
//   Field order and row contracts follow main:                                                                 |
//   `src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`.                                  |
//   The build-time integration kernels are produced by the old route in                                        |
//   `src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig`; this file owns only the      |
//   retained row shape consumed after those kernels are known.                                                 |
//                                                                                                              |
// route                                                                                                        |
//   sampling rows -> radiance_wavelengths.zig exact f64-bit dedup -> transport prefetch -> instrument gather   |
//                                                                                                              |
// key contract                                                                                                 |
//   Wavelength rows keep the exact f64 sample values. Deduplication lives in `radiance_wavelengths.zig` and    |
//   uses `@bitCast(wavelength_nm)` exactly like the old `SpectralEvaluationCache.keyFor` route.                |
// ------------------------------------------------------------------------------------------------------------ |

// IntegrationKernelStorage ----------------------------------------------------------------------------------  |
// Side-array storage for large instrument integration kernels.                                                 |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 32 B (0.031 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0..15] offsets_nm : []const f64                                                                            |
// [16..31] weights    : []const f64                                                                            |
//                                                                                                              |
// referenced storage                                                                                           |
//   offsets_nm and weights borrow table-wide side arrays owned by spectrum memory.                             |
pub const IntegrationKernelStorage = struct {
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------ |

// IntegrationKernelSamples ----------------------------------------------------------------------------------  |
// Borrowed view over either inline samples or side-array samples.                                              |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 32 B (0.031 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0..15] offsets_nm : []const f64                                                                            |
// [16..31] weights    : []const f64                                                                            |
//                                                                                                              |
// referenced storage                                                                                           |
//   slices borrow samples from an IntegrationKernelRef or IntegrationKernelStorage.                            |
pub const IntegrationKernelSamples = struct {
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------ |

pub const IntegrationKernelEncoding = enum(u16) {
    disabled,
    inline_samples,
    side_samples,
};

// IntegrationKernelRef --------------------------------------------------------------------------------------  |
// Compact kernel reference for one nominal row and one signal channel.                                         |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 88 B (0.086 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0..39] inline_offsets_nm : [5]f64                                                                          |
// [40..79] inline_weights    : [5]f64                                                                          |
// [80..83] side_start        : u32                                                                             |
// [84..85] sample_count      : u16                                                                             |
// [86..87] encoding          : IntegrationKernelEncoding                                                       |
//                                                                                                              |
// hot path                                                                                                     |
//   Disabled kernels consume one direct sample with weight 1.0. Inline kernels avoid side-array chasing for    |
//   the old five-sample case. Large adaptive kernels point into table-wide side arrays.                        |
pub const IntegrationKernelRef = struct {
    inline_offsets_nm: [inline_integration_sample_count]f64 =
        [_]f64{0.0} ** inline_integration_sample_count,
    inline_weights: [inline_integration_sample_count]f64 =
        [_]f64{0.0} ** inline_integration_sample_count,
    side_start: u32 = 0,
    sample_count: u16 = 0,
    encoding: IntegrationKernelEncoding = .disabled,

    pub inline fn disabled() IntegrationKernelRef {
        // IntegrationKernelRef.disabled ---------------------------------------------------------------------  |
        // Encode the direct-sample route used when instrument integration is off.                              |
        // ---------------------------------------------------------------------------------------------------- |
        return .{ .sample_count = 1 };
    }

    pub inline fn enabled(self: *const IntegrationKernelRef) bool {
        // IntegrationKernelRef.enabled ----------------------------------------------------------------------  |
        // Return whether this row has an instrument integration kernel.                                        |
        // ---------------------------------------------------------------------------------------------------- |
        return self.encoding != .disabled;
    }

    pub inline fn activeSampleCount(self: *const IntegrationKernelRef) usize {
        // IntegrationKernelRef.activeSampleCount ------------------------------------------------------------  |
        // Return the sample count consumed by the gather loop. Disabled rows still consume one sample.         |
        // ---------------------------------------------------------------------------------------------------- |
        return if (self.enabled()) @intCast(self.sample_count) else 1;
    }

    pub inline fn samples(
        self: *const IntegrationKernelRef,
        storage: IntegrationKernelStorage,
    ) IntegrationKernelSamples {
        // IntegrationKernelRef.samples ----------------------------------------------------------------------  |
        // Resolve compact row storage into borrowed offset and weight slices.                                  |
        // ---------------------------------------------------------------------------------------------------- |
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
        // IntegrationKernelRef.offsetNm ---------------------------------------------------------------------  |
        // Read one sample offset without materializing slices.                                                 |
        // ---------------------------------------------------------------------------------------------------- |
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
        // IntegrationKernelRef.weight -----------------------------------------------------------------------  |
        // Read one integration weight. Disabled rows use 1.0 so direct and integrated gathers share shape.     |
        // ---------------------------------------------------------------------------------------------------- |
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
// ------------------------------------------------------------------------------------------------------------ |

// SpectrumSamplingRow ---------------------------------------------------------------------------------------  |
// One public output wavelength plus radiance and irradiance sample contracts.                                  |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 200 B (0.195 KiB), align: 8 B                                                                          |
//                                                                                                              |
// memory                                                                                                       |
// [  0..  7] nominal_wavelength_nm    : f64                                                                    |
// [  8.. 15] radiance_wavelength_nm   : f64                                                                    |
// [ 16.. 23] irradiance_wavelength_nm : f64                                                                    |
// [ 24..111] radiance_integration     : IntegrationKernelRef                                                   |
// [112..199] irradiance_integration   : IntegrationKernelRef                                                   |
pub const SpectrumSamplingRow = struct {
    nominal_wavelength_nm: f64,
    radiance_wavelength_nm: f64,
    irradiance_wavelength_nm: f64,
    radiance_integration: IntegrationKernelRef,
    irradiance_integration: IntegrationKernelRef,
};
// ------------------------------------------------------------------------------------------------------------ |

// SpectrumSamplingTable -------------------------------------------------------------------------------------  |
// Borrowed table view consumed by spectrum assembly loops.                                                     |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 48 B (0.047 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0..15] rows           : []const SpectrumSamplingRow                                                        |
// [16..47] kernel_storage : IntegrationKernelStorage                                                           |
//                                                                                                              |
// referenced storage                                                                                           |
//   rows and kernel_storage borrow arrays owned by SpectrumMemory.                                             |
pub const SpectrumSamplingTable = struct {
    rows: []const SpectrumSamplingRow = &.{},
    kernel_storage: IntegrationKernelStorage = .{},
};
// ------------------------------------------------------------------------------------------------------------ |

// SamplingTableSummary --------------------------------------------------------------------------------------  |
// Aggregate sampling fan-out metrics mirrored from the old telemetry row.                                      |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 56 B (0.055 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] row_count                 : usize                                                                   |
// [ 8..15] radiance_integrated_rows  : usize                                                                   |
// [16..23] irradiance_integrated_rows: usize                                                                   |
// [24..31] radiance_sample_count     : usize                                                                   |
// [32..39] irradiance_sample_count   : usize                                                                   |
// [40..47] side_sample_count         : usize                                                                   |
// [48..55] max_kernel_sample_count   : usize                                                                   |
pub const SamplingTableSummary = struct {
    row_count: usize = 0,
    radiance_integrated_rows: usize = 0,
    irradiance_integrated_rows: usize = 0,
    radiance_sample_count: usize = 0,
    irradiance_sample_count: usize = 0,
    side_sample_count: usize = 0,
    max_kernel_sample_count: usize = 0,
};
// ------------------------------------------------------------------------------------------------------------ |

pub fn summarize(table: SpectrumSamplingTable) SamplingTableSummary {
    // summarize ---------------------------------------------------------------------------------------------  |
    // Count sampling fan-out exactly as the old wavelengthSamplingPlan telemetry row did.                      |
    // -------------------------------------------------------------------------------------------------------- |
    var summary = SamplingTableSummary{
        .row_count = table.rows.len,
        .side_sample_count = table.kernel_storage.offsets_nm.len,
    };

    for (table.rows) |row| {
        const radiance_count = row.radiance_integration.activeSampleCount();
        const irradiance_count = row.irradiance_integration.activeSampleCount();
        if (row.radiance_integration.enabled()) summary.radiance_integrated_rows += 1;
        if (row.irradiance_integration.enabled()) summary.irradiance_integrated_rows += 1;
        summary.radiance_sample_count += radiance_count;
        summary.irradiance_sample_count += irradiance_count;
        summary.max_kernel_sample_count = @max(summary.max_kernel_sample_count, radiance_count);
        summary.max_kernel_sample_count = @max(summary.max_kernel_sample_count, irradiance_count);
    }

    return summary;
}

pub fn recordSamplingTable(table: SpectrumSamplingTable) void {
    // recordSamplingTable -----------------------------------------------------------------------------------  |
    // Emit the old wavelength-sampling telemetry row when telemetry is compiled in.                            |
    // -------------------------------------------------------------------------------------------------------- |
    const summary = summarize(table);

    // instrumentation: calculation telemetry: spectrum sampling table ---------------------------------------  |
    // captures: row count, integrated rows, sample counts, side samples                                        |
    // why: preserves old wavelength_sampling.wavelengthSamplingPlan telemetry at the new spectrum boundary.    |
    telemetry.wavelengthSamplingPlan(
        summary.row_count,
        summary.radiance_integrated_rows,
        summary.irradiance_integrated_rows,
        summary.radiance_sample_count,
        summary.irradiance_sample_count,
        summary.side_sample_count,
        summary.max_kernel_sample_count,
    );
    // end instrumentation: calculation telemetry: spectrum sampling table -----------------------------------  |

}

comptime {
    std.debug.assert(@sizeOf(IntegrationKernelStorage) == 32);
    std.debug.assert(@sizeOf(IntegrationKernelSamples) == 32);
    std.debug.assert(@sizeOf(IntegrationKernelRef) == 88);
    std.debug.assert(@sizeOf(SpectrumSamplingRow) == 200);
    std.debug.assert(@sizeOf(SpectrumSamplingTable) == 48);
    std.debug.assert(@sizeOf(SamplingTableSummary) == 56);
}
