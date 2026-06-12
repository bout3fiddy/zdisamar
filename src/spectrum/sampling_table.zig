const std = @import("std");

const errors = @import("../common/errors.zig");
const gauss_legendre = @import("../common/math/gauss_legendre.zig");
const o2_case = @import("../input/o2_case.zig");
const telemetry = @import("../instrumentation/telemetry.zig");
const instrument_tables = @import("../setup/instrument_tables.zig");
const line_tables = @import("../setup/line_tables.zig");

const Allocator = std.mem.Allocator;

pub const inline_integration_sample_count: usize = 5;
pub const max_integration_sample_count: usize = 2048;

const safe_fwhm_floor_nm: f64 = 1.0e-4;
const flat_top_width_floor_nm: f64 = 1.0e-6;
const strong_line_merge_tolerance_nm: f64 = 1.0e-9;
const interval_progress_tolerance_nm: f64 = 1.0e-12;
const vendor_outside_support_sample_count: usize = 1;

// sampling_table.zig ---------------------------------------------------------------------------------------- |
// Compact instrument-response rows for the spectrum layer.                                                    |
//                                                                                                             |
// provenance                                                                                                  |
//   Field order and row contracts follow main:                                                                |
//   `src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`.                                 |
//   The build-time integration kernels are produced by the old route in                                       |
//   `src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig`; this file owns only the     |
//   retained row shape consumed after those kernels are known.                                                |
//                                                                                                             |
// route                                                                                                       |
//   sampling rows -> radiance_wavelengths.zig exact f64-bit dedup -> transport prefetch -> instrument gather  |
//                                                                                                             |
// key contract                                                                                                |
//   Wavelength rows keep the exact f64 sample values. Deduplication lives in `radiance_wavelengths.zig` and   |
//   uses `@bitCast(wavelength_nm)` exactly like the old `SpectralEvaluationCache.keyFor` route.               |
// ------------------------------------------------------------------------------------------------------------|

// IntegrationKernelStorage ---------------------------------------------------------------------------------- |
// Side-array storage for large instrument integration kernels.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] offsets_nm : []const f64                                                                           |
// [16..31] weights    : []const f64                                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   offsets_nm and weights borrow table-wide side arrays owned by spectrum memory.                            |
pub const IntegrationKernelStorage = struct {
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

// IntegrationKernelSamples ---------------------------------------------------------------------------------- |
// Borrowed view over either inline samples or side-array samples.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] offsets_nm : []const f64                                                                           |
// [16..31] weights    : []const f64                                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   slices borrow samples from an IntegrationKernelRef or IntegrationKernelStorage.                           |
pub const IntegrationKernelSamples = struct {
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

pub const IntegrationKernelEncoding = enum(u16) {
    disabled,
    inline_samples,
    side_samples,
};

// IntegrationKernelRef -------------------------------------------------------------------------------------- |
// Compact kernel reference for one nominal row and one signal channel.                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 88 B (0.086 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..39] inline_offsets_nm : [5]f64                                                                         |
// [40..79] inline_weights    : [5]f64                                                                         |
// [80..83] side_start        : u32                                                                            |
// [84..85] sample_count      : u16                                                                            |
// [86..87] encoding          : IntegrationKernelEncoding                                                      |
//                                                                                                             |
// hot path                                                                                                    |
//   Disabled kernels consume one direct sample with weight 1.0. Inline kernels avoid side-array chasing for   |
//   the old five-sample case. Large adaptive kernels point into table-wide side arrays.                       |
pub const IntegrationKernelRef = struct {
    inline_offsets_nm: [inline_integration_sample_count]f64 =
        [_]f64{0.0} ** inline_integration_sample_count,
    inline_weights: [inline_integration_sample_count]f64 =
        [_]f64{0.0} ** inline_integration_sample_count,
    side_start: u32 = 0,
    sample_count: u16 = 0,
    encoding: IntegrationKernelEncoding = .disabled,

    pub inline fn disabled() IntegrationKernelRef {
        // IntegrationKernelRef.disabled --------------------------------------------------------------------- |
        // Encode the direct-sample route used when instrument integration is off.                             |
        // ----------------------------------------------------------------------------------------------------|
        return .{ .sample_count = 1 };
    }

    pub inline fn enabled(self: *const IntegrationKernelRef) bool {
        // IntegrationKernelRef.enabled ---------------------------------------------------------------------- |
        // Return whether this row has an instrument integration kernel.                                       |
        // ----------------------------------------------------------------------------------------------------|
        return self.encoding != .disabled;
    }

    pub inline fn activeSampleCount(self: *const IntegrationKernelRef) usize {
        // IntegrationKernelRef.activeSampleCount ------------------------------------------------------------ |
        // Return the sample count consumed by the gather loop. Disabled rows still consume one sample.        |
        // ----------------------------------------------------------------------------------------------------|
        return if (self.enabled()) @intCast(self.sample_count) else 1;
    }

    pub inline fn samples(
        self: *const IntegrationKernelRef,
        storage: IntegrationKernelStorage,
    ) IntegrationKernelSamples {
        // IntegrationKernelRef.samples ---------------------------------------------------------------------- |
        // Resolve compact row storage into borrowed offset and weight slices.                                 |
        // ----------------------------------------------------------------------------------------------------|
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
        // IntegrationKernelRef.offsetNm --------------------------------------------------------------------- |
        // Read one sample offset without materializing slices.                                                |
        // ----------------------------------------------------------------------------------------------------|
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
        // IntegrationKernelRef.weight ----------------------------------------------------------------------- |
        // Read one integration weight. Disabled rows use 1.0 so direct and integrated gathers share shape.    |
        // ----------------------------------------------------------------------------------------------------|
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
// ------------------------------------------------------------------------------------------------------------|

// SpectrumSamplingRow --------------------------------------------------------------------------------------- |
// One public output wavelength plus radiance and irradiance sample contracts.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 200 B (0.195 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] nominal_wavelength_nm    : f64                                                                   |
// [  8.. 15] radiance_wavelength_nm   : f64                                                                   |
// [ 16.. 23] irradiance_wavelength_nm : f64                                                                   |
// [ 24..111] radiance_integration     : IntegrationKernelRef                                                  |
// [112..199] irradiance_integration   : IntegrationKernelRef                                                  |
pub const SpectrumSamplingRow = struct {
    nominal_wavelength_nm: f64,
    radiance_wavelength_nm: f64,
    irradiance_wavelength_nm: f64,
    radiance_integration: IntegrationKernelRef,
    irradiance_integration: IntegrationKernelRef,
};
// ------------------------------------------------------------------------------------------------------------|

// SpectrumSamplingTable ------------------------------------------------------------------------------------- |
// Borrowed table view consumed by spectrum assembly loops.                                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] rows           : []const SpectrumSamplingRow                                                       |
// [16..47] kernel_storage : IntegrationKernelStorage                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows and kernel_storage borrow arrays owned by SpectrumMemory.                                            |
pub const SpectrumSamplingTable = struct {
    rows: []const SpectrumSamplingRow = &.{},
    kernel_storage: IntegrationKernelStorage = .{},
};
// ------------------------------------------------------------------------------------------------------------|

// OwnedSpectrumSamplingTable -------------------------------------------------------------------------------- |
// Owned sampling rows and side-array kernels returned by the reference builder.                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] rows             : []SpectrumSamplingRow                                                           |
// [16..31] kernel_offsets_nm: []f64                                                                           |
// [32..47] kernel_weights   : []f64                                                                           |
//                                                                                                             |
// owned storage                                                                                               |
//   all three slices own heap storage and are released by deinit.                                             |
pub const OwnedSpectrumSamplingTable = struct {
    rows: []SpectrumSamplingRow = &.{},
    kernel_offsets_nm: []f64 = &.{},
    kernel_weights: []f64 = &.{},

    pub fn view(self: *const OwnedSpectrumSamplingTable) SpectrumSamplingTable {
        // OwnedSpectrumSamplingTable.view ------------------------------------------------------------------- |
        // Borrow the retained sampling table for spectrum loops and exact-wavelength deduplication.           |
        // ----------------------------------------------------------------------------------------------------|
        return .{
            .rows = self.rows,
            .kernel_storage = .{
                .offsets_nm = self.kernel_offsets_nm,
                .weights = self.kernel_weights,
            },
        };
    }

    pub fn deinit(self: *OwnedSpectrumSamplingTable, allocator: Allocator) void {
        // OwnedSpectrumSamplingTable.deinit ----------------------------------------------------------------- |
        // Release retained sampling rows and table-wide side samples.                                         |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        allocator.free(self.kernel_offsets_nm);
        allocator.free(self.kernel_weights);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

// IntegrationKernelScratch ---------------------------------------------------------------------------------- |
// Fixed-capacity build row before compaction into inline or side-array table storage.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32784 B (32.016 KiB), align: 8 B                                                                      |
//                                                                                                             |
// memory                                                                                                      |
// [    0..    7] sample_count : usize                                                                         |
// [    8..16391] offsets_nm   : [2048]f64                                                                     |
// [16392..32775] weights      : [2048]f64                                                                     |
// [32776..32776] enabled      : bool                                                                          |
// [32777..32783] trailing padding : 7 B                                                                       |
//                                                                                                             |
// hot path                                                                                                    |
//   The sampling builder reuses one row for radiance and one for irradiance while walking nominal wavelengths.|
const IntegrationKernelScratch = struct {
    sample_count: usize = 0,
    offsets_nm: [max_integration_sample_count]f64 = undefined,
    weights: [max_integration_sample_count]f64 = undefined,
    enabled: bool = false,
};
// ------------------------------------------------------------------------------------------------------------|

// AdaptiveKernelSupportWindow ------------------------------------------------------------------------------- |
// Global and row-local support bounds for DISAMAR-style adaptive integration.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] global_start_nm : f64                                                                              |
// [ 8..15] global_end_nm   : f64                                                                              |
// [16..23] window_start_nm : f64                                                                              |
// [24..31] window_end_nm   : f64                                                                              |
const AdaptiveKernelSupportWindow = struct {
    global_start_nm: f64,
    global_end_nm: f64,
    window_start_nm: f64,
    window_end_nm: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// AdaptiveIntervalPlan -------------------------------------------------------------------------------------- |
// Fixed-capacity interval ends and Gauss division counts for instrument sampling.                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 20504 B (20.023 KiB), align: 8 B                                                                      |
//                                                                                                             |
// memory                                                                                                      |
// [    0..    7] count           : usize                                                                      |
// [    8..   15] global_start_nm : f64                                                                        |
// [   16..   23] global_end_nm   : f64                                                                        |
// [   24..16407] interval_end_nm : [2048]f64                                                                  |
// [16408..20503] division_counts : [2048]u16                                                                  |
//                                                                                                             |
// encoded fields                                                                                              |
//   interval starts derive from global_start_nm and the previous interval end.                                |
const AdaptiveIntervalPlan = struct {
    count: usize = 0,
    global_start_nm: f64 = 0.0,
    global_end_nm: f64 = 0.0,
    interval_end_nm: [max_integration_sample_count]f64 = undefined,
    division_counts: [max_integration_sample_count]u16 = undefined,

    inline fn reset(self: *AdaptiveIntervalPlan, global_start_nm: f64, global_end_nm: f64) void {
        // AdaptiveIntervalPlan.reset ------------------------------------------------------------------------ |
        // Reset the active interval prefix for one expanded spectral support span.                            |
        // --------------------------------------------------------------------------------------------------- |
        self.count = 0;
        self.global_start_nm = global_start_nm;
        self.global_end_nm = global_end_nm;
    }

    inline fn append(self: *AdaptiveIntervalPlan, interval_end_nm: f64, division_count: usize) bool {
        // AdaptiveIntervalPlan.append ----------------------------------------------------------------------- |
        // Append one interval end and one Gauss division count without truncating fixed storage.              |
        // --------------------------------------------------------------------------------------------------- |
        if (self.count >= max_integration_sample_count) return false;
        if (division_count > std.math.maxInt(u16)) return false;
        self.interval_end_nm[self.count] = interval_end_nm;
        self.division_counts[self.count] = @intCast(division_count);
        self.count += 1;
        return true;
    }

    inline fn setDivisionCount(self: *AdaptiveIntervalPlan, index: usize, division_count: usize) bool {
        // AdaptiveIntervalPlan.setDivisionCount ------------------------------------------------------------- |
        // Rewrite the interval order after strong-line width scaling.                                         |
        // --------------------------------------------------------------------------------------------------- |
        if (index >= self.count) return false;
        if (division_count > std.math.maxInt(u16)) return false;
        self.division_counts[index] = @intCast(division_count);
        return true;
    }

    inline fn intervalStartNm(self: *const AdaptiveIntervalPlan, index: usize) f64 {
        // AdaptiveIntervalPlan.intervalStartNm -------------------------------------------------------------- |
        // Decode the implicit start boundary for one interval.                                                |
        // --------------------------------------------------------------------------------------------------- |
        return if (index == 0) self.global_start_nm else self.interval_end_nm[index - 1];
    }

    inline fn intervalEndNm(self: *const AdaptiveIntervalPlan, index: usize) f64 {
        // AdaptiveIntervalPlan.intervalEndNm ---------------------------------------------------------------- |
        // Read one stored interval end boundary.                                                              |
        // --------------------------------------------------------------------------------------------------- |
        return self.interval_end_nm[index];
    }

    inline fn intervalWidthNm(self: *const AdaptiveIntervalPlan, index: usize) f64 {
        // AdaptiveIntervalPlan.intervalWidthNm -------------------------------------------------------------- |
        // Compute the support interval width in nanometers.                                                   |
        // --------------------------------------------------------------------------------------------------- |
        return self.intervalEndNm(index) - self.intervalStartNm(index);
    }

    inline fn divisionCount(self: *const AdaptiveIntervalPlan, index: usize) usize {
        // AdaptiveIntervalPlan.divisionCount ---------------------------------------------------------------- |
        // Return the Gauss order for one support interval.                                                    |
        // --------------------------------------------------------------------------------------------------- |
        return @intCast(self.division_counts[index]);
    }
};
// ------------------------------------------------------------------------------------------------------------|

// AdaptiveSupportRange -------------------------------------------------------------------------------------- |
// Inclusive candidate-sample index range selected for one nominal wavelength.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] start_index : usize                                                                                |
// [ 8..15] end_index   : usize                                                                                |
const AdaptiveSupportRange = struct {
    start_index: usize,
    end_index: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// SamplingTableSummary -------------------------------------------------------------------------------------- |
// Aggregate sampling fan-out metrics mirrored from the old telemetry row.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] row_count                 : usize                                                                  |
// [ 8..15] radiance_integrated_rows  : usize                                                                  |
// [16..23] irradiance_integrated_rows: usize                                                                  |
// [24..31] radiance_sample_count     : usize                                                                  |
// [32..39] irradiance_sample_count   : usize                                                                  |
// [40..47] side_sample_count         : usize                                                                  |
// [48..55] max_kernel_sample_count   : usize                                                                  |
pub const SamplingTableSummary = struct {
    row_count: usize = 0,
    radiance_integrated_rows: usize = 0,
    irradiance_integrated_rows: usize = 0,
    radiance_sample_count: usize = 0,
    irradiance_sample_count: usize = 0,
    side_sample_count: usize = 0,
    max_kernel_sample_count: usize = 0,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn buildReferenceSpectrumSamplingTable(
    allocator: Allocator,
    case: o2_case.O2Case,
    instrument: instrument_tables.InstrumentTable,
    lines: line_tables.O2LineTable,
) !OwnedSpectrumSamplingTable {
    // buildReferenceSpectrumSamplingTable ------------------------------------------------------------------- |
    // Build the DISAMAR-reference spectrum sampling plan from explicit setup tables.                          |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports the exercised old route from main:                                                              |
    //   `instrument_grid/grid_calculation/wavelength_sampling.zig`                                            |
    //   `forward_model/implementations/instrument/integration.zig`                                            |
    //   `forward_model/implementations/instrument/adaptive_plan.zig`                                          |
    //                                                                                                         |
    // route                                                                                                   |
    //   spectral grid -> strong-line adaptive interval plan -> radiance/irradiance kernels -> compact rows    |
    //                                                                                                         |
    // math                                                                                                    |
    //   nominal_i = start + i * (end - start) / (count - 1)                                                   |
    //   raw_w_j   = flat_top_n4(lambda_j - nominal_i) * interval_width * Gauss weight                         |
    //   w_j       = raw_w_j / sum_k raw_w_k after duplicate wavelengths are merged                            |
    // --------------------------------------------------------------------------------------------------------|
    if (case.spectral_grid.sample_count == 0) return errors.Error.InvalidControl;

    var plan: AdaptiveIntervalPlan = .{};
    if (!buildAdaptiveIntervalPlan(case.spectral_grid, instrument, lines, &plan)) {
        return errors.Error.InvalidControl;
    }

    const rows = try allocator.alloc(SpectrumSamplingRow, case.spectral_grid.sample_count);
    errdefer allocator.free(rows);

    var side_offsets = std.ArrayList(f64).empty;
    errdefer side_offsets.deinit(allocator);
    var side_weights = std.ArrayList(f64).empty;
    errdefer side_weights.deinit(allocator);

    var radiance_kernel: IntegrationKernelScratch = .{};
    var irradiance_kernel: IntegrationKernelScratch = .{};

    for (rows, 0..) |*row, index| {
        const nominal_wavelength_nm = nominalWavelengthNm(case.spectral_grid, index);
        if (!buildAdaptiveIntegrationKernelFromPlan(
            &plan,
            instrument,
            nominal_wavelength_nm,
            false,
            &radiance_kernel,
        )) return errors.Error.InvalidControl;
        if (!buildAdaptiveIntegrationKernelFromPlan(
            &plan,
            instrument,
            nominal_wavelength_nm,
            true,
            &irradiance_kernel,
        )) return errors.Error.InvalidControl;

        row.* = .{
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .radiance_wavelength_nm = nominal_wavelength_nm,
            .irradiance_wavelength_nm = nominal_wavelength_nm,
            .radiance_integration = try compactIntegrationKernel(
                allocator,
                radiance_kernel,
                &side_offsets,
                &side_weights,
            ),
            .irradiance_integration = try compactIntegrationKernel(
                allocator,
                irradiance_kernel,
                &side_offsets,
                &side_weights,
            ),
        };
    }

    return .{
        .rows = rows,
        .kernel_offsets_nm = try side_offsets.toOwnedSlice(allocator),
        .kernel_weights = try side_weights.toOwnedSlice(allocator),
    };
}

pub fn summarize(table: SpectrumSamplingTable) SamplingTableSummary {
    // summarize --------------------------------------------------------------------------------------------- |
    // Count sampling fan-out exactly as the old wavelengthSamplingPlan telemetry row did.                     |
    // --------------------------------------------------------------------------------------------------------|
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

fn nominalWavelengthNm(grid: o2_case.SpectralGrid, index: usize) f64 {
    // nominalWavelengthNm ----------------------------------------------------------------------------------- |
    // Compute the public output grid coordinate using the old linear endpoint-inclusive grid rule.            |
    // --------------------------------------------------------------------------------------------------------|
    if (grid.sample_count == 1) return grid.start_nm;
    const fraction = @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(grid.sample_count - 1));
    return grid.start_nm + (grid.end_nm - grid.start_nm) * fraction;
}

fn compactIntegrationKernel(
    allocator: Allocator,
    kernel: IntegrationKernelScratch,
    side_offsets: *std.ArrayList(f64),
    side_weights: *std.ArrayList(f64),
) !IntegrationKernelRef {
    // compactIntegrationKernel ------------------------------------------------------------------------------ |
    // Move one scratch kernel into the retained row shape used by spectrum loops.                             |
    // --------------------------------------------------------------------------------------------------------|
    if (!kernel.enabled) {
        return IntegrationKernelRef.disabled();
    }

    if (kernel.sample_count > std.math.maxInt(u16)) {
        return errors.Error.InvalidControl;
    }

    if (kernel.sample_count <= inline_integration_sample_count) {
        return inlineIntegrationKernelRef(kernel);
    }

    if (side_offsets.items.len > std.math.maxInt(u32)) {
        return errors.Error.InvalidControl;
    }

    const side_start: u32 = @intCast(side_offsets.items.len);
    const active_offsets = kernel.offsets_nm[0..kernel.sample_count];
    const active_weights = kernel.weights[0..kernel.sample_count];
    try side_offsets.appendSlice(allocator, active_offsets);
    errdefer side_offsets.shrinkRetainingCapacity(side_start);
    try side_weights.appendSlice(allocator, active_weights);

    return .{
        .side_start = side_start,
        .sample_count = @intCast(kernel.sample_count),
        .encoding = .side_samples,
    };
}

fn inlineIntegrationKernelRef(kernel: IntegrationKernelScratch) IntegrationKernelRef {
    // inlineIntegrationKernelRef ---------------------------------------------------------------------------- |
    // Copy a small active prefix into the retained inline kernel storage.                                     |
    // --------------------------------------------------------------------------------------------------------|
    var compact = IntegrationKernelRef{
        .sample_count = @intCast(kernel.sample_count),
        .encoding = .inline_samples,
    };

    const active_offsets = kernel.offsets_nm[0..kernel.sample_count];
    const active_weights = kernel.weights[0..kernel.sample_count];
    @memcpy(compact.inline_offsets_nm[0..kernel.sample_count], active_offsets);
    @memcpy(compact.inline_weights[0..kernel.sample_count], active_weights);

    return compact;
}

fn buildAdaptiveIntegrationKernelFromPlan(
    plan: *const AdaptiveIntervalPlan,
    instrument: instrument_tables.InstrumentTable,
    nominal_wavelength_nm: f64,
    apply_disamar_midpoint_bias: bool,
    kernel: *IntegrationKernelScratch,
) bool {
    // buildAdaptiveIntegrationKernelFromPlan ---------------------------------------------------------------- |
    // Reuse interval boundaries and emit nominal-wavelength-specific offsets and weights.                     |
    //                                                                                                         |
    // math                                                                                                    |
    //   lambda_j = interval_start + interval_width * DISAMAR node                                             |
    //   delta_j  = lambda_j - nominal                                                                         |
    // --------------------------------------------------------------------------------------------------------|
    var sample_count: usize = 0;
    if (!appendAdaptiveSamplesFromPlan(
        plan,
        instrument,
        nominal_wavelength_nm,
        apply_disamar_midpoint_bias,
        &kernel.offsets_nm,
        &kernel.weights,
        &sample_count,
    )) return false;

    return finalizeAdaptiveKernel(
        kernel,
        nominal_wavelength_nm,
        kernel.offsets_nm[0..sample_count],
        kernel.weights[0..sample_count],
    );
}

fn buildAdaptiveIntervalPlan(
    grid: o2_case.SpectralGrid,
    instrument: instrument_tables.InstrumentTable,
    lines: line_tables.O2LineTable,
    plan: *AdaptiveIntervalPlan,
) bool {
    // buildAdaptiveIntervalPlan ----------------------------------------------------------------------------- |
    // Partition the expanded spectral support around strong O2 line centers and assign Gauss orders.          |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Mirrors old `adaptive_plan.zig` buildAdaptiveIntervalPlan for the DISAMAR reference case.             |
    // --------------------------------------------------------------------------------------------------------|
    const support_window = adaptiveKernelSupportWindow(grid, instrument, grid.start_nm);
    const fwhm_nm = @max(instrument.line_fwhm_nm, safe_fwhm_floor_nm);

    var strong_centers_nm: [max_integration_sample_count]f64 = undefined;
    var strong_center_count: usize = 0;
    if (!collectAdaptiveStrongLineCenters(
        lines,
        support_window.global_start_nm,
        support_window.global_end_nm,
        &strong_centers_nm,
        &strong_center_count,
    )) {
        return false;
    }

    plan.reset(support_window.global_start_nm, support_window.global_end_nm);
    var current_nm = support_window.global_start_nm;
    var strong_index: usize = 0;
    while (strong_index < strong_center_count and
        strong_centers_nm[strong_index] <= current_nm + interval_progress_tolerance_nm) : (strong_index += 1)
    {}

    while (plan.count < max_integration_sample_count) {
        var next_nm = current_nm + fwhm_nm;
        if (strong_index < strong_center_count and
            strong_centers_nm[strong_index] < next_nm - interval_progress_tolerance_nm)
        {
            next_nm = strong_centers_nm[strong_index];
            strong_index += 1;
        }

        if (next_nm <= current_nm + interval_progress_tolerance_nm) next_nm = current_nm + fwhm_nm;
        if (!plan.append(next_nm, 1)) return false;
        current_nm = next_nm;

        while (strong_index < strong_center_count and
            strong_centers_nm[strong_index] <= current_nm + interval_progress_tolerance_nm) : (strong_index += 1)
        {}

        if (current_nm > support_window.global_end_nm) break;
    }
    if (plan.count == 0 or current_nm <= support_window.global_end_nm) return false;

    const max_interval_nm = maxAdaptiveIntervalWidth(plan);
    for (0..plan.count) |interval_index| {
        const division_count = adaptiveIntervalDivisionCount(
            instrument,
            plan.intervalWidthNm(interval_index),
            max_interval_nm,
            strong_center_count != 0,
        );
        if (!plan.setDivisionCount(interval_index, division_count)) return false;
    }
    return true;
}

fn adaptiveKernelSupportWindow(
    grid: o2_case.SpectralGrid,
    instrument: instrument_tables.InstrumentTable,
    nominal_wavelength_nm: f64,
) AdaptiveKernelSupportWindow {
    // adaptiveKernelSupportWindow --------------------------------------------------------------------------- |
    // Compute the global expanded support span and row-local response window.                                 |
    //                                                                                                         |
    // math                                                                                                    |
    //   global span = spectral grid expanded by 2 * FWHM                                                      |
    //   window span = nominal wavelength +/- configured half span                                             |
    // --------------------------------------------------------------------------------------------------------|
    const fwhm_nm = @max(instrument.line_fwhm_nm, safe_fwhm_floor_nm);
    const half_span_nm = adaptiveKernelHalfSpanNm(instrument);
    const global_start_nm = grid.start_nm - (2.0 * fwhm_nm);
    const global_end_nm = grid.end_nm + (2.0 * fwhm_nm);
    return .{
        .global_start_nm = global_start_nm,
        .global_end_nm = global_end_nm,
        .window_start_nm = @max(global_start_nm, nominal_wavelength_nm - half_span_nm),
        .window_end_nm = @min(global_end_nm, nominal_wavelength_nm + half_span_nm),
    };
}

fn appendAdaptiveSamplesFromPlan(
    plan: *const AdaptiveIntervalPlan,
    instrument: instrument_tables.InstrumentTable,
    nominal_wavelength_nm: f64,
    apply_disamar_midpoint_bias: bool,
    sample_wavelengths_nm: *[max_integration_sample_count]f64,
    sample_raw_weights: *[max_integration_sample_count]f64,
    sample_count: *usize,
) bool {
    // appendAdaptiveSamplesFromPlan ------------------------------------------------------------------------- |
    // Emit finite Gauss candidates near one nominal wavelength and keep the vendor support edge shape.        |
    //                                                                                                         |
    // math                                                                                                    |
    //   raw_w = flat_top_n4(lambda - nominal) * interval_width * Gauss weight                                 |
    // --------------------------------------------------------------------------------------------------------|
    const support_half_span_nm = adaptiveKernelHalfSpanNm(instrument);
    const safe_fwhm_nm = @max(instrument.line_fwhm_nm, safe_fwhm_floor_nm);
    const generation_start_nm = @max(
        plan.global_start_nm,
        nominal_wavelength_nm - support_half_span_nm - safe_fwhm_nm,
    );
    const generation_end_nm = @min(
        plan.global_end_nm,
        nominal_wavelength_nm + support_half_span_nm + safe_fwhm_nm,
    );

    var candidate_count: usize = 0;
    sample_count.* = 0;

    var gauss_nodes_01: [max_integration_sample_count]f64 = undefined;
    var gauss_weights_01: [max_integration_sample_count]f64 = undefined;

    for (0..plan.count) |interval_index| {
        const interval_start_nm = plan.intervalStartNm(interval_index);
        const interval_end_nm = plan.intervalEndNm(interval_index);
        if (interval_end_nm < generation_start_nm - interval_progress_tolerance_nm) continue;
        if (interval_start_nm > generation_end_nm + interval_progress_tolerance_nm) continue;

        const order = plan.divisionCount(interval_index);
        if (order == 0) continue;
        gauss_legendre.fillDisamarDivPoints01(
            @intCast(order),
            gauss_nodes_01[0..order],
            gauss_weights_01[0..order],
        ) catch return false;

        const interval_width_nm = interval_end_nm - interval_start_nm;
        for (0..order) |gauss_index| {
            const wavelength_nm = realizedIntervalWavelengthNm(
                interval_start_nm,
                interval_width_nm,
                gauss_nodes_01[gauss_index],
                order,
                gauss_index,
                apply_disamar_midpoint_bias,
            );
            const raw_weight = flatTopN4Weight(instrument.line_fwhm_nm, wavelength_nm - nominal_wavelength_nm) *
                (interval_width_nm * gauss_weights_01[gauss_index]);
            if (!appendAdaptiveSample(
                sample_wavelengths_nm,
                sample_raw_weights,
                &candidate_count,
                wavelength_nm,
                raw_weight,
            )) return false;
        }
    }
    if (candidate_count == 0) return false;

    insertionSortSamples(sample_wavelengths_nm[0..candidate_count], sample_raw_weights[0..candidate_count]);

    const support_range = selectVendorSupportRange(
        sample_wavelengths_nm[0..candidate_count],
        nominal_wavelength_nm,
        support_half_span_nm,
    );
    var selected_count: usize = 0;
    for (support_range.start_index..support_range.end_index + 1) |candidate_index| {
        sample_wavelengths_nm[selected_count] = sample_wavelengths_nm[candidate_index];
        sample_raw_weights[selected_count] = sample_raw_weights[candidate_index];
        selected_count += 1;
    }
    sample_count.* = selected_count;
    return sample_count.* != 0;
}

fn finalizeAdaptiveKernel(
    kernel: *IntegrationKernelScratch,
    nominal_wavelength_nm: f64,
    sample_wavelengths_nm: []f64,
    sample_raw_weights: []f64,
) bool {
    // finalizeAdaptiveKernel -------------------------------------------------------------------------------- |
    // Sort, merge duplicate wavelengths, normalize raw weights, and write relative offsets.                   |
    // --------------------------------------------------------------------------------------------------------|
    if (sample_wavelengths_nm.len == 0 or sample_wavelengths_nm.len != sample_raw_weights.len) return false;

    insertionSortSamples(sample_wavelengths_nm, sample_raw_weights);

    var merged_count: usize = 0;
    for (sample_wavelengths_nm, sample_raw_weights) |wavelength_nm, raw_weight| {
        const should_merge =
            merged_count != 0 and
            @abs(sample_wavelengths_nm[merged_count - 1] - wavelength_nm) <= strong_line_merge_tolerance_nm;
        if (should_merge) {
            sample_raw_weights[merged_count - 1] += raw_weight;
            continue;
        }
        sample_wavelengths_nm[merged_count] = wavelength_nm;
        sample_raw_weights[merged_count] = raw_weight;
        merged_count += 1;
    }
    if (merged_count == 0) return false;

    var total_weight: f64 = 0.0;
    for (sample_raw_weights[0..merged_count]) |raw_weight| total_weight += raw_weight;
    if (!std.math.isFinite(total_weight) or total_weight <= 0.0) return false;

    kernel.enabled = true;
    kernel.sample_count = merged_count;
    for (0..merged_count) |index| {
        kernel.offsets_nm[index] = sample_wavelengths_nm[index] - nominal_wavelength_nm;
        kernel.weights[index] = sample_raw_weights[index] / total_weight;
    }
    return true;
}

fn collectAdaptiveStrongLineCenters(
    lines: line_tables.O2LineTable,
    global_start_nm: f64,
    global_end_nm: f64,
    centers_nm: *[max_integration_sample_count]f64,
    center_count: *usize,
) bool {
    // collectAdaptiveStrongLineCenters ---------------------------------------------------------------------- |
    // Collect, sort, and deduplicate line centers that split adaptive instrument intervals.                   |
    //                                                                                                         |
    // math                                                                                                    |
    //   threshold = max(line_strength_cm2_per_molecule) * threshold_line_sim                                  |
    // --------------------------------------------------------------------------------------------------------|
    center_count.* = 0;
    const threshold_strength = thresholdStrength(lines.rows, lines.threshold_line_sim) orelse return true;

    for (lines.rows) |*line| {
        if (line.line_strength_cm2_per_molecule < threshold_strength) continue;
        if (line.center_wavelength_nm < global_start_nm or line.center_wavelength_nm > global_end_nm) continue;
        if (center_count.* >= max_integration_sample_count) return false;
        centers_nm[center_count.*] = line.center_wavelength_nm;
        center_count.* += 1;
    }
    if (center_count.* == 0) return true;

    std.sort.block(f64, centers_nm[0..center_count.*], {}, lessThanF64);
    var merged_count: usize = 1;
    for (1..center_count.*) |index| {
        if (@abs(centers_nm[index] - centers_nm[merged_count - 1]) <= strong_line_merge_tolerance_nm) continue;
        centers_nm[merged_count] = centers_nm[index];
        merged_count += 1;
    }
    center_count.* = merged_count;
    return true;
}

fn thresholdStrength(rows: []const @import("../assets/readers.zig").O2LineAssetRow, scale: f64) ?f64 {
    // thresholdStrength ------------------------------------------------------------------------------------- |
    // Return the absolute strong-center cutoff used by the old SpectroscopyRuntimeControls route.             |
    // --------------------------------------------------------------------------------------------------------|
    if (rows.len == 0) return null;
    var max_strength: f64 = 0.0;
    for (rows) |*row| max_strength = @max(max_strength, row.line_strength_cm2_per_molecule);
    return max_strength * scale;
}

fn maxAdaptiveIntervalWidth(plan: *const AdaptiveIntervalPlan) f64 {
    // maxAdaptiveIntervalWidth ------------------------------------------------------------------------------ |
    // Return the widest interior interval used to scale strong-line division counts.                          |
    // --------------------------------------------------------------------------------------------------------|
    if (plan.count == 0) return 1.0;

    var max_width_nm: f64 = 0.0;
    if (plan.count > 2) {
        const inner_end = plan.count - 1;
        for (1..inner_end) |interval_index| {
            max_width_nm = @max(max_width_nm, plan.intervalWidthNm(interval_index));
        }
    }
    if (max_width_nm <= 0.0) {
        for (0..plan.count) |interval_index| {
            max_width_nm = @max(max_width_nm, plan.intervalWidthNm(interval_index));
        }
    }
    return @max(max_width_nm, strong_line_merge_tolerance_nm);
}

fn adaptiveIntervalDivisionCount(
    instrument: instrument_tables.InstrumentTable,
    interval_width_nm: f64,
    max_interval_nm: f64,
    has_strong_lines: bool,
) usize {
    // adaptiveIntervalDivisionCount ------------------------------------------------------------------------- |
    // Choose the Gauss order for one interval using the old strong-line scaling rule.                         |
    // --------------------------------------------------------------------------------------------------------|
    if (!has_strong_lines) return @max(instrument.adaptive_points_per_fwhm, 1);
    const min_divisions = @max(instrument.strong_line_min_divisions, 1);
    const max_divisions = @max(instrument.strong_line_max_divisions, min_divisions);
    const scaled: usize = @intFromFloat(std.math.round(
        @as(f64, @floatFromInt(max_divisions)) *
            (@max(interval_width_nm, strong_line_merge_tolerance_nm) /
                @max(max_interval_nm, strong_line_merge_tolerance_nm)),
    ));
    return std.math.clamp(@max(scaled, min_divisions), min_divisions, max_divisions);
}

fn adaptiveKernelHalfSpanNm(instrument: instrument_tables.InstrumentTable) f64 {
    // adaptiveKernelHalfSpanNm ------------------------------------------------------------------------------ |
    // Prefer explicit support span; otherwise use the old finite FWHM-only default.                           |
    // --------------------------------------------------------------------------------------------------------|
    return if (instrument.high_resolution_half_span_nm > 0.0)
        instrument.high_resolution_half_span_nm
    else
        @max(3.0 * @max(instrument.line_fwhm_nm, safe_fwhm_floor_nm), safe_fwhm_floor_nm);
}

fn realizedIntervalWavelengthNm(
    interval_start_nm: f64,
    interval_width_nm: f64,
    node_01: f64,
    order: usize,
    gauss_index: usize,
    apply_disamar_midpoint_bias: bool,
) f64 {
    // realizedIntervalWavelengthNm -------------------------------------------------------------------------- |
    // Realize one interval-local node as an absolute wavelength, preserving the old irradiance midpoint bias. |
    // --------------------------------------------------------------------------------------------------------|
    const wavelength_nm = interval_start_nm + interval_width_nm * node_01;

    if (!apply_disamar_midpoint_bias) return wavelength_nm;

    const is_midpoint_node =
        order % 2 != 0 and
        gauss_index == order / 2 and
        node_01 == 0.5;
    if (!is_midpoint_node) return wavelength_nm;

    return std.math.nextAfter(f64, wavelength_nm, -std.math.inf(f64));
}

fn appendAdaptiveSample(
    sample_wavelengths_nm: *[max_integration_sample_count]f64,
    sample_raw_weights: *[max_integration_sample_count]f64,
    sample_count: *usize,
    wavelength_nm: f64,
    raw_weight: f64,
) bool {
    // appendAdaptiveSample ---------------------------------------------------------------------------------- |
    // Append one finite non-negative candidate sample into the active prefix.                                 |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(raw_weight) or raw_weight < 0.0) return true;
    if (sample_count.* >= max_integration_sample_count) return false;

    sample_wavelengths_nm[sample_count.*] = wavelength_nm;
    sample_raw_weights[sample_count.*] = raw_weight;
    sample_count.* += 1;
    return true;
}

fn selectVendorSupportRange(
    sample_wavelengths_nm: []const f64,
    nominal_wavelength_nm: f64,
    support_half_span_nm: f64,
) AdaptiveSupportRange {
    // selectVendorSupportRange ------------------------------------------------------------------------------ |
    // Select all in-window candidates plus one outside support sample when present on each side.              |
    // --------------------------------------------------------------------------------------------------------|
    std.debug.assert(sample_wavelengths_nm.len != 0);

    var closest_index: usize = 0;
    var closest_distance_nm = @abs(sample_wavelengths_nm[0] - nominal_wavelength_nm);
    for (sample_wavelengths_nm[1..], 1..) |wavelength_nm, index| {
        const distance_nm = @abs(wavelength_nm - nominal_wavelength_nm);
        if (distance_nm < closest_distance_nm) {
            closest_distance_nm = distance_nm;
            closest_index = index;
        }
    }

    var start_index: usize = 0;
    var left_index = closest_index;
    while (left_index > 0) {
        left_index -= 1;
        if (@abs(nominal_wavelength_nm - sample_wavelengths_nm[left_index]) > support_half_span_nm) {
            start_index = left_index;
            break;
        }
    }

    var end_index = sample_wavelengths_nm.len - 1;
    var right_index = closest_index;
    while (right_index + vendor_outside_support_sample_count < sample_wavelengths_nm.len) {
        right_index += 1;
        if (@abs(sample_wavelengths_nm[right_index] - nominal_wavelength_nm) > support_half_span_nm) {
            end_index = right_index;
            break;
        }
    }

    return .{
        .start_index = start_index,
        .end_index = end_index,
    };
}

fn insertionSortSamples(sample_wavelengths_nm: []f64, sample_raw_weights: []f64) void {
    // insertionSortSamples ---------------------------------------------------------------------------------- |
    // Sort the active prefix by wavelength while keeping raw weights paired.                                  |
    // --------------------------------------------------------------------------------------------------------|
    if (sample_wavelengths_nm.len != sample_raw_weights.len) return;
    for (1..sample_wavelengths_nm.len) |index| {
        var cursor = index;
        while (cursor > 0 and sample_wavelengths_nm[cursor] < sample_wavelengths_nm[cursor - 1]) : (cursor -= 1) {
            std.mem.swap(f64, &sample_wavelengths_nm[cursor], &sample_wavelengths_nm[cursor - 1]);
            std.mem.swap(f64, &sample_raw_weights[cursor], &sample_raw_weights[cursor - 1]);
        }
    }
}

fn flatTopN4Weight(fwhm_nm: f64, offset_nm: f64) f64 {
    // flatTopN4Weight --------------------------------------------------------------------------------------- |
    // Evaluate the DISAMAR-reference flat-top N4 response.                                                    |
    //                                                                                                         |
    // math                                                                                                    |
    //   flat_top_n4(delta) = 2^(-2 * (delta / max(FWHM / 1.681793, 1e-6))^4)                                  |
    // --------------------------------------------------------------------------------------------------------|
    const width_nm = fwhm_nm / 1.681793;
    return std.math.pow(f64, 2.0, -2.0 * std.math.pow(f64, offset_nm / @max(width_nm, flat_top_width_floor_nm), 4.0));
}

fn lessThanF64(_: void, lhs: f64, rhs: f64) bool {
    // lessThanF64 ------------------------------------------------------------------------------------------- |
    // Sort helper for f64 support lists; all callers filter non-finite values before sorting.                 |
    // --------------------------------------------------------------------------------------------------------|
    return lhs < rhs;
}

pub fn recordSamplingTable(table: SpectrumSamplingTable) void {
    // recordSamplingTable ----------------------------------------------------------------------------------- |
    // Emit the old wavelength-sampling telemetry row when telemetry is compiled in.                           |
    // --------------------------------------------------------------------------------------------------------|
    const summary = summarize(table);

    // instrumentation: calculation telemetry: spectrum sampling table --------------------------------------- |
    // captures: row count, integrated rows, sample counts, side samples                                       |
    // why: preserves old wavelength_sampling.wavelengthSamplingPlan telemetry at the new spectrum boundary.   |
    telemetry.wavelengthSamplingPlan(
        summary.row_count,
        summary.radiance_integrated_rows,
        summary.irradiance_integrated_rows,
        summary.radiance_sample_count,
        summary.irradiance_sample_count,
        summary.side_sample_count,
        summary.max_kernel_sample_count,
    );
    // end instrumentation: calculation telemetry: spectrum sampling table ----------------------------------- |

}

comptime {
    std.debug.assert(@sizeOf(IntegrationKernelStorage) == 32);
    std.debug.assert(@sizeOf(IntegrationKernelSamples) == 32);
    std.debug.assert(@sizeOf(IntegrationKernelRef) == 88);
    std.debug.assert(@sizeOf(SpectrumSamplingRow) == 200);
    std.debug.assert(@sizeOf(SpectrumSamplingTable) == 48);
    std.debug.assert(@sizeOf(OwnedSpectrumSamplingTable) == 48);
    std.debug.assert(@sizeOf(IntegrationKernelScratch) == 32784);
    std.debug.assert(@sizeOf(AdaptiveKernelSupportWindow) == 32);
    std.debug.assert(@sizeOf(AdaptiveIntervalPlan) == 20504);
    std.debug.assert(@sizeOf(AdaptiveSupportRange) == 16);
    std.debug.assert(@sizeOf(SamplingTableSummary) == 56);
}
