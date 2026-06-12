const std = @import("std");

const sampling_table = @import("sampling_table.zig");
const telemetry = @import("../instrumentation/telemetry.zig");

const Allocator = std.mem.Allocator;

// radiance_wavelengths.zig ---------------------------------------------------------------------------------- |
// Exact high-resolution radiance wavelengths required by a SpectrumSamplingTable.                             |
//                                                                                                             |
// provenance                                                                                                  |
//   This ports the forward-miss list from main:                                                               |
//   `src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig` and                              |
//   `src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig`.                             |
//                                                                                                             |
// old names -> new names                                                                                      |
//   ForwardCacheMiss      -> RadianceWavelength                                                               |
//   ForwardSampleIndexRef -> RadianceSampleIndexRef                                                           |
//   ForwardMissPlan       -> RadianceWavelengthList                                                           |
//                                                                                                             |
// key contract                                                                                                |
//   `keyFor` is the old `SpectralEvaluationCache.keyFor`: the exact f64 bit pattern is the key. No rounding,  |
//   binning, decimal formatting, or tolerance comparison is allowed here.                                     |
// ------------------------------------------------------------------------------------------------------------|

// RadianceWavelength ---------------------------------------------------------------------------------------- |
// Unique high-resolution radiance wavelength that must run through optics and transport once.                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] key           : u64                                                                                 |
// [8..15] wavelength_nm : f64                                                                                 |
pub const RadianceWavelength = struct {
    key: u64,
    wavelength_nm: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// RadianceSampleIndexRef ------------------------------------------------------------------------------------ |
// Start offset into the dense sample_indices stream for one nominal output row.                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 4 B (0.004 KiB), align: 4 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..3] start : u32                                                                                          |
pub const RadianceSampleIndexRef = struct {
    start: u32 = 0,
};
// ------------------------------------------------------------------------------------------------------------|

// RadianceWavelengthList ------------------------------------------------------------------------------------ |
// Borrowed view of unique high-resolution radiance wavelengths and per-row sample references.                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] rows           : []const RadianceSampleIndexRef                                                    |
// [16..31] sample_indices : []const u32                                                                       |
// [32..47] wavelengths    : []const RadianceWavelength                                                        |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows, sample_indices, and wavelengths borrow arrays owned by OwnedRadianceWavelengthList.                 |
pub const RadianceWavelengthList = struct {
    rows: []const RadianceSampleIndexRef = &.{},
    sample_indices: []const u32 = &.{},
    wavelengths: []const RadianceWavelength = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

// OwnedRadianceWavelengthList ------------------------------------------------------------------------------- |
// Owned row refs, row-local sample-index stream, and exact radiance wavelength rows.                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] rows           : []RadianceSampleIndexRef                                                          |
// [16..31] sample_indices : []u32                                                                             |
// [32..47] wavelengths    : []RadianceWavelength                                                              |
//                                                                                                             |
// owned storage                                                                                               |
//   all slices own heap storage and are released by deinit.                                                   |
pub const OwnedRadianceWavelengthList = struct {
    rows: []RadianceSampleIndexRef = &.{},
    sample_indices: []u32 = &.{},
    wavelengths: []RadianceWavelength = &.{},

    pub fn view(self: *const OwnedRadianceWavelengthList) RadianceWavelengthList {
        // OwnedRadianceWavelengthList.view ------------------------------------------------------------------ |
        // Borrow the retained wavelength list for spectrum loops.                                             |
        // ----------------------------------------------------------------------------------------------------|
        return .{
            .rows = self.rows,
            .sample_indices = self.sample_indices,
            .wavelengths = self.wavelengths,
        };
    }

    pub fn deinit(self: *OwnedRadianceWavelengthList, allocator: Allocator) void {
        // OwnedRadianceWavelengthList.deinit ---------------------------------------------------------------  |
        // Release row refs, sample indexes, and wavelength rows.                                              |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        allocator.free(self.sample_indices);
        allocator.free(self.wavelengths);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn keyFor(wavelength_nm: f64) u64 {
    // keyFor -------------------------------------------------------------------------------------------------|
    // Use the exact f64 bit pattern as the radiance-wavelength identity.                                      |
    // --------------------------------------------------------------------------------------------------------|
    return @as(u64, @bitCast(wavelength_nm));
}

pub fn radianceSampleIndexCount(table: sampling_table.SpectrumSamplingTable) usize {
    // radianceSampleIndexCount ------------------------------------------------------------------------------ |
    // Count the dense sample-index stream before allocation.                                                  |
    // --------------------------------------------------------------------------------------------------------|
    var count: usize = 0;
    for (table.rows) |row| {
        count += row.radiance_integration.activeSampleCount();
    }
    return count;
}

pub fn buildRadianceWavelengthList(
    allocator: Allocator,
    table: sampling_table.SpectrumSamplingTable,
) !OwnedRadianceWavelengthList {
    // buildRadianceWavelengthList --------------------------------------------------------------------------- |
    // Deduplicate radiance integration wavelengths and build direct indexes into the dense radiance result    |
    // array. Irradiance samples stay out of this list because they are resolved by solar lookup memory.       |
    //                                                                                                         |
    // row contract                                                                                            |
    //   rows[i].start points into sample_indices. The row's radiance_integration.activeSampleCount() gives    |
    //   the row length. sample_indices stores dense indexes into wavelengths/results, not wavelength values.  |
    //                                                                                                         |
    // math                                                                                                    |
    //   direct row     : one wavelength at lambda_radiance_i                                                  |
    //   integrated row : one wavelength for each lambda_radiance_i + offset_ij                                |
    // --------------------------------------------------------------------------------------------------------|
    var index_by_key = std.AutoHashMap(u64, u32).init(allocator);
    defer index_by_key.deinit();

    var wavelengths = std.ArrayList(RadianceWavelength).empty;
    errdefer wavelengths.deinit(allocator);
    var sample_indices = std.ArrayList(u32).empty;
    errdefer sample_indices.deinit(allocator);

    try sample_indices.ensureTotalCapacityPrecise(allocator, radianceSampleIndexCount(table));
    const rows = try allocator.alloc(RadianceSampleIndexRef, table.rows.len);
    errdefer allocator.free(rows);

    for (table.rows, rows) |row, *out_row| {
        const integration = &row.radiance_integration;
        const start = sample_indices.items.len;
        if (!integration.enabled()) {
            try appendRadianceSampleIndex(
                allocator,
                &index_by_key,
                &wavelengths,
                &sample_indices,
                row.radiance_wavelength_nm,
            );
            out_row.* = .{ .start = try castSampleIndexStart(start) };
            continue;
        }

        const samples = integration.samples(table.kernel_storage);
        for (samples.offsets_nm) |offset_nm| {
            try appendRadianceSampleIndex(
                allocator,
                &index_by_key,
                &wavelengths,
                &sample_indices,
                row.radiance_wavelength_nm + offset_nm,
            );
        }
        out_row.* = .{ .start = try castSampleIndexStart(start) };
    }

    // instrumentation: calculation telemetry: radiance wavelength list -------------------------------------- |
    // captures: nominal row count, sample-index count, unique radiance wavelength count                       |
    // why: preserves old wavelength_sampling.forwardMissPlan telemetry at the new spectrum boundary.          |
    telemetry.forwardMissPlan(table.rows.len, sample_indices.items.len, wavelengths.items.len);
    // end instrumentation: calculation telemetry: radiance wavelength list ---------------------------------- |

    return .{
        .rows = rows,
        .sample_indices = try sample_indices.toOwnedSlice(allocator),
        .wavelengths = try wavelengths.toOwnedSlice(allocator),
    };
}

fn castSampleIndexStart(start: usize) !u32 {
    // castSampleIndexStart ---------------------------------------------------------------------------------- |
    // Store sample-index starts as u32 to keep row refs compact; oversized plans fail before truncation.      |
    // --------------------------------------------------------------------------------------------------------|
    if (start > std.math.maxInt(u32)) return error.OutOfMemory;
    return @intCast(start);
}

fn appendRadianceSampleIndex(
    allocator: Allocator,
    index_by_key: *std.AutoHashMap(u64, u32),
    wavelengths: *std.ArrayList(RadianceWavelength),
    sample_indices: *std.ArrayList(u32),
    wavelength_nm: f64,
) !void {
    // appendRadianceSampleIndex ----------------------------------------------------------------------------- |
    // Append the dense result index for one radiance sample; repeated exact bits reuse an existing index.     |
    // --------------------------------------------------------------------------------------------------------|
    const key = keyFor(wavelength_nm);
    if (index_by_key.get(key)) |wavelength_index| {
        sample_indices.appendAssumeCapacity(wavelength_index);
        return;
    }
    if (wavelengths.items.len > std.math.maxInt(u32)) return error.OutOfMemory;
    const wavelength_index: u32 = @intCast(wavelengths.items.len);

    const entry = try index_by_key.getOrPut(key);
    if (entry.found_existing) {
        sample_indices.appendAssumeCapacity(entry.value_ptr.*);
        return;
    }
    wavelengths.append(allocator, .{
        .key = key,
        .wavelength_nm = wavelength_nm,
    }) catch |err| {
        _ = index_by_key.remove(key);

        return err;
    };
    entry.value_ptr.* = wavelength_index;
    sample_indices.appendAssumeCapacity(wavelength_index);
}

comptime {
    std.debug.assert(@sizeOf(RadianceWavelength) == 16);
    std.debug.assert(@sizeOf(RadianceSampleIndexRef) == 4);
    std.debug.assert(@sizeOf(RadianceWavelengthList) == 48);
    std.debug.assert(@sizeOf(OwnedRadianceWavelengthList) == 48);
}
