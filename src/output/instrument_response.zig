const std = @import("std");

const scene_input = @import("../input/scene.zig");
const run_tables = @import("../setup/run_tables.zig");
const sampling_table = @import("../spectrum/sampling_table.zig");
const errors = @import("../common/errors.zig");

const Allocator = std.mem.Allocator;

pub const channel_mask_radiance: u32 = 1 << 0;
pub const channel_mask_irradiance: u32 = 1 << 1;
const allowed_channel_mask = channel_mask_radiance | channel_mask_irradiance;
const integration_mode_disamar_hr_grid: u32 = 2;

// instrument_response.zig ------------------------------------------------------------------------------------|
// Public instrument-response support rows for the explicit O2 A route.                                        |
//                                                                                                             |
// boundary                                                                                                    |
//   The builder projects spectrum sampling kernels into the fixed Python C ABI row order. It owns no C        |
//   handles and performs no transport; it expands only instrument-kernel support samples.                     |
//                                                                                                             |
//   requested nominal wavelengths, then rounds only `nominal_index` back to the product grid.                 |
//                                                                                                             |
// row order                                                                                                   |
//   requested wavelength major, channel order radiance then irradiance, then support sample index.            |
//                                                                                                             |
// memory                                                                                                      |
//   `build` allocates one temporary compact sampling table plus one returned row slice.                       |
// ------------------------------------------------------------------------------------------------------------|

// InstrumentResponseRow --------------------------------------------------------------------------------------|
// One support sample from one instrument response kernel.                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 3] nominal_index                 : i32                                                                |
// [ 4.. 7] padding                       : 4 B                                                                |
// [ 8..15] nominal_wavelength_nm         : f64                                                                |
// [16..19] channel                       : u32                                                                |
// [20..23] sample_index                  : u32                                                                |
// [24..27] support_count                 : u32                                                                |
// [28..31] padding                       : 4 B                                                                |
// [32..39] offset_nm                     : f64                                                                |
// [40..47] support_wavelength_nm         : f64                                                                |
// [48..55] weight                        : f64                                                                |
// [56..63] support_width_nm              : f64                                                                |
// [64..71] instrument_fwhm_nm            : f64                                                                |
// [72..79] high_resolution_step_nm       : f64                                                                |
// [80..87] high_resolution_half_span_nm  : f64                                                                |
// [88..91] integration_mode              : u32                                                                |
// [92..92] response_enabled              : u8                                                                 |
// [93..95] trailing padding              : 3 B                                                                |
pub const InstrumentResponseRow = extern struct {
    nominal_index: i32,
    nominal_wavelength_nm: f64,
    channel: u32,
    sample_index: u32,
    support_count: u32,
    offset_nm: f64,
    support_wavelength_nm: f64,
    weight: f64,
    support_width_nm: f64,
    instrument_fwhm_nm: f64,
    high_resolution_step_nm: f64,
    high_resolution_half_span_nm: f64,
    integration_mode: u32,
    response_enabled: u8,
};
// ------------------------------------------------------------------------------------------------------------|

// InstrumentResponse -----------------------------------------------------------------------------------------|
// Owned instrument-response diagnostic table returned through root/API calls.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] rows : []InstrumentResponseRow                                                                      |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns one record per requested wavelength, enabled channel, and support sample.                       |
pub const InstrumentResponse = struct {
    rows: []InstrumentResponseRow = &.{},

    pub fn deinit(self: *InstrumentResponse, allocator: Allocator) void {
        // InstrumentResponse.deinit --------------------------------------------------------------------------|
        // Release the owned instrument-response row table.                                                    |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(
    allocator: Allocator,
    scene: scene_input.Scene,
    tables: *const run_tables.RunTables,
    nominal_wavelengths_nm: []const f64,
    channel_mask: u32,
) !InstrumentResponse {
    // build --------------------------------------------------------------------------------------------------|
    // Build public instrument-response support rows for caller-selected wavelengths and channels.             |
    // --------------------------------------------------------------------------------------------------------|
    if (nominal_wavelengths_nm.len == 0) return errors.Error.InvalidControl;

    if ((channel_mask & allowed_channel_mask) == 0) return errors.Error.InvalidControl;

    if ((channel_mask & ~allowed_channel_mask) != 0) return errors.Error.InvalidControl;

    var owned_sampling = try sampling_table.buildSpectrumSamplingTableForWavelengths(
        allocator,
        scene,
        tables.instrument,
        tables.lines,
        nominal_wavelengths_nm,
    );
    defer owned_sampling.deinit(allocator);

    const table = owned_sampling.view();
    const row_count = responseRowCount(table, channel_mask);
    const rows = try allocator.alloc(InstrumentResponseRow, row_count);
    errdefer allocator.free(rows);

    var row_index: usize = 0;
    for (table.rows) |row| {
        if ((channel_mask & channel_mask_radiance) != 0) {
            row_index = writeChannelRows(scene, tables, table, row, .radiance, rows, row_index);
        }
        if ((channel_mask & channel_mask_irradiance) != 0) {
            row_index = writeChannelRows(scene, tables, table, row, .irradiance, rows, row_index);
        }
    }
    std.debug.assert(row_index == rows.len);

    return .{ .rows = rows };
}

const Channel = enum {
    radiance,
    irradiance,
};

fn responseRowCount(table: sampling_table.SpectrumSamplingTable, channel_mask: u32) usize {
    // responseRowCount ---------------------------------------------------------------------------------------|
    // Count expanded support rows before allocation so row append is a single linear fill.                    |
    // --------------------------------------------------------------------------------------------------------|
    var count: usize = 0;
    for (table.rows) |row| {
        if ((channel_mask & channel_mask_radiance) != 0) {
            count += row.radiance_integration.activeSampleCount();
        }
        if ((channel_mask & channel_mask_irradiance) != 0) {
            count += row.irradiance_integration.activeSampleCount();
        }
    }
    return count;
}

fn writeChannelRows(
    scene: scene_input.Scene,
    tables: *const run_tables.RunTables,
    table: sampling_table.SpectrumSamplingTable,
    row: sampling_table.SpectrumSamplingRow,
    channel: Channel,
    rows: []InstrumentResponseRow,
    row_start: usize,
) usize {
    // writeChannelRows ---------------------------------------------------------------------------------------|
    // Expand one compact kernel reference into contiguous fixed-ABI diagnostic rows.                          |
    // --------------------------------------------------------------------------------------------------------|
    const kernel = switch (channel) {
        .radiance => row.radiance_integration,
        .irradiance => row.irradiance_integration,
    };
    const support_count = kernel.activeSampleCount();
    const support_width_nm = supportWidthNm(kernel, table.kernel_storage, support_count);
    const channel_code: u32 = switch (channel) {
        .radiance => 0,
        .irradiance => 1,
    };
    const nominal_index = nearestNominalIndex(scene, row.nominal_wavelength_nm);

    var row_index = row_start;
    for (0..support_count) |sample_index| {
        const offset_nm = kernel.offsetNm(table.kernel_storage, sample_index);
        rows[row_index] = .{
            .nominal_index = nominal_index,
            .nominal_wavelength_nm = row.nominal_wavelength_nm,
            .channel = channel_code,
            .sample_index = @intCast(sample_index),
            .support_count = @intCast(support_count),
            .offset_nm = offset_nm,
            .support_wavelength_nm = row.nominal_wavelength_nm + offset_nm,
            .weight = kernel.weight(table.kernel_storage, sample_index),
            .support_width_nm = support_width_nm,
            .instrument_fwhm_nm = tables.instrument.line_fwhm_nm,
            .high_resolution_step_nm = tables.instrument.high_resolution_step_nm,
            .high_resolution_half_span_nm = tables.instrument.high_resolution_half_span_nm,
            .integration_mode = integration_mode_disamar_hr_grid,
            .response_enabled = if (kernel.enabled()) 1 else 0,
        };
        row_index += 1;
    }
    return row_index;
}

fn supportWidthNm(
    kernel: sampling_table.IntegrationKernelRef,
    storage: sampling_table.IntegrationKernelStorage,
    support_count: usize,
) f64 {
    // supportWidthNm -----------------------------------------------------------------------------------------|
    // Match the diagnostic width: last selected offset minus first selected offset.                           |
    // --------------------------------------------------------------------------------------------------------|
    if (support_count <= 1) return 0.0;
    return kernel.offsetNm(storage, support_count - 1) - kernel.offsetNm(storage, 0);
}

fn nearestNominalIndex(scene: scene_input.Scene, nominal_wavelength_nm: f64) i32 {
    // nearestNominalIndex ------------------------------------------------------------------------------------|
    // Round diagnostic wavelengths back to the product grid without changing the sampled kernel location.     |
    // --------------------------------------------------------------------------------------------------------|
    const sample_count = scene.spectral_grid.sample_count;
    if (sample_count <= 1) return 0;

    const step_nm = (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) /
        @as(f64, @floatFromInt(sample_count - 1));
    if (step_nm <= 0.0) return 0;

    const raw = @round((nominal_wavelength_nm - scene.spectral_grid.start_nm) / step_nm);
    const clamped = std.math.clamp(raw, 0.0, @as(f64, @floatFromInt(sample_count - 1)));
    return @intFromFloat(clamped);
}

comptime {
    std.debug.assert(@sizeOf(InstrumentResponseRow) == 96);
    std.debug.assert(@sizeOf(InstrumentResponse) == 16);
}
