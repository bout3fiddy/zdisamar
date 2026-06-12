const std = @import("std");

const memory = @import("../common/memory.zig");
const radiance_results = @import("../spectrum/radiance_results.zig");
const radiance_wavelengths = @import("../spectrum/radiance_wavelengths.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{
    ShapeMismatch,
};

// radiance_memory.zig --------------------------------------------------------------------------------------- |
// Allocation home for exact radiance wavelengths and dense radiance results.                                  |
//                                                                                                             |
// provenance                                                                                                  |
//   Splits old `ProductStorage.forward_miss_plan` and `ProductStorage.forward_results` from main:             |
//   `src/forward_model/instrument_grid/grid_calculation/storage.zig`. The old names were                      |
//   `OwnedForwardMissPlan` and `ForwardIntegratedSample`; new names describe the retained data directly.      |
//                                                                                                             |
// ownership boundary                                                                                          |
//   This memory object owns reusable arrays only. It stores no physics controls, no solar table, no profile   |
//   line values, and no transport settings.                                                                   |
// ------------------------------------------------------------------------------------------------------------|

// RadianceMemory -------------------------------------------------------------------------------------------- |
// Reusable allocation owner for exact radiance wavelength lists and dense result rows.                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelength_rows : []RadianceSampleIndexRef                                                         |
// [16..31] sample_indices  : []u32                                                                            |
// [32..47] wavelengths     : []RadianceWavelength                                                             |
// [48..63] results         : []RadianceResult                                                                 |
// [64..95] active          : RadianceMemoryActive                                                             |
//                                                                                                             |
// owned storage                                                                                               |
//   all slices own heap arrays and are released by deinit.                                                    |
pub const RadianceMemory = struct {
    wavelength_rows: []radiance_wavelengths.RadianceSampleIndexRef = &.{},
    sample_indices: []u32 = &.{},
    wavelengths: []radiance_wavelengths.RadianceWavelength = &.{},
    results: []radiance_results.RadianceResult = &.{},
    active: RadianceMemoryActive = .{},

    pub fn deinit(self: *RadianceMemory, allocator: Allocator) void {
        // RadianceMemory.deinit ----------------------------------------------------------------------------- |
        // Release exact wavelength-list arrays and dense radiance result rows.                                |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.wavelength_rows);
        allocator.free(self.sample_indices);
        allocator.free(self.wavelengths);
        allocator.free(self.results);
        self.* = .{};
    }

    pub fn takeWavelengthList(
        self: *RadianceMemory,
        allocator: Allocator,
        list: *radiance_wavelengths.OwnedRadianceWavelengthList,
    ) void {
        // RadianceMemory.takeWavelengthList ----------------------------------------------------------------- |
        // Move an owned exact wavelength list into reusable radiance memory without copying its arrays.       |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.wavelength_rows);
        allocator.free(self.sample_indices);
        allocator.free(self.wavelengths);
        self.wavelength_rows = list.rows;
        self.sample_indices = list.sample_indices;
        self.wavelengths = list.wavelengths;
        self.active.wavelength_row_count = list.rows.len;
        self.active.sample_index_count = list.sample_indices.len;
        self.active.wavelength_count = list.wavelengths.len;
        list.* = .{};
    }

    pub fn ensureResultCapacity(
        self: *RadianceMemory,
        allocator: Allocator,
        result_count: usize,
    ) Allocator.Error!void {
        // RadianceMemory.ensureResultCapacity --------------------------------------------------------------- |
        // Ensure dense radiance result storage is large enough. Existing values are not preserved across      |
        // growth because prefetch fills every active result row before nominal gathers read it.               |
        // ----------------------------------------------------------------------------------------------------|
        _ = try memory.ensureSliceCapacity(
            radiance_results.RadianceResult,
            allocator,
            &self.results,
            result_count,
        );
        self.active.result_count = result_count;
    }

    pub fn wavelengthList(self: *const RadianceMemory) radiance_wavelengths.RadianceWavelengthList {
        // RadianceMemory.wavelengthList --------------------------------------------------------------------- |
        // Borrow the active exact wavelength-list prefix.                                                     |
        // ----------------------------------------------------------------------------------------------------|
        return .{
            .rows = self.wavelength_rows[0..self.active.wavelength_row_count],
            .sample_indices = self.sample_indices[0..self.active.sample_index_count],
            .wavelengths = self.wavelengths[0..self.active.wavelength_count],
        };
    }

    pub fn resultRows(self: *RadianceMemory) []radiance_results.RadianceResult {
        // RadianceMemory.resultRows ------------------------------------------------------------------------- |
        // Borrow the active dense radiance result prefix.                                                     |
        // ----------------------------------------------------------------------------------------------------|
        return self.results[0..self.active.result_count];
    }
};
// ------------------------------------------------------------------------------------------------------------|

// RadianceMemoryActive -------------------------------------------------------------------------------------- |
// Active prefixes inside RadianceMemory backing arrays.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_row_count: usize                                                                        |
// [ 8..15] sample_index_count  : usize                                                                        |
// [16..23] wavelength_count    : usize                                                                        |
// [24..31] result_count        : usize                                                                        |
pub const RadianceMemoryActive = struct {
    wavelength_row_count: usize = 0,
    sample_index_count: usize = 0,
    wavelength_count: usize = 0,
    result_count: usize = 0,
};
// ------------------------------------------------------------------------------------------------------------|

comptime {
    std.debug.assert(@sizeOf(RadianceMemoryActive) == 32);
    std.debug.assert(@sizeOf(RadianceMemory) == 96);
}
