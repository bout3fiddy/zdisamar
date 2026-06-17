const std = @import("std");

const hashing = @import("../common/hashing.zig");
const memory = @import("../common/memory.zig");
const radiance_results = @import("../spectrum/radiance_results.zig");
const radiance_wavelengths = @import("../spectrum/radiance_wavelengths.zig");
const jacobian_states = @import("../rtm/jacobian_states.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{
    ShapeMismatch,
};

// radiance_memory.zig --------------------------------------------------------------------------------------- |
// Allocation home for exact radiance wavelengths and dense radiance results.                                  |
//                                                                                                             |
// ownership boundary                                                                                          |
//   This memory object owns reusable arrays only. It stores no physics controls, no solar table, no profile   |
//   line values, and no transport settings.                                                                   |
// ------------------------------------------------------------------------------------------------------------|

// RadianceMemory -------------------------------------------------------------------------------------------- |
// Reusable allocation owner for exact radiance wavelength lists and dense split result columns.               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 136 B (0.133 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelength_rows : []RadianceSampleIndexRef                                                         |
// [16..31] sample_indices  : []u32                                                                            |
// [32..47] wavelengths     : []RadianceWavelength                                                             |
// [48..63] radiance        : []f64                                                                            |
// [64..79] jacobian        : []Vector                                                                         |
// [80..119] active         : RadianceMemoryActive                                                             |
// [120..127] wavelength_stamp: ReuseStamp                                                                     |
// [128..135] result_stamp   : ReuseStamp                                                                      |
//                                                                                                             |
// owned storage                                                                                               |
//   all slices own heap arrays and are released by deinit.                                                    |
pub const RadianceMemory = struct {
    wavelength_rows: []radiance_wavelengths.RadianceSampleIndexRef = &.{},
    sample_indices: []u32 = &.{},
    wavelengths: []radiance_wavelengths.RadianceWavelength = &.{},
    radiance: []f64 = &.{},
    jacobian: []jacobian_states.Vector = &.{},
    active: RadianceMemoryActive = .{},
    wavelength_stamp: hashing.ReuseStamp = .{},
    result_stamp: hashing.ReuseStamp = .{},

    pub fn deinit(self: *RadianceMemory, allocator: Allocator) void {
        // RadianceMemory.deinit ----------------------------------------------------------------------------- |
        // Release exact wavelength-list arrays and dense radiance result rows.                                |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.wavelength_rows);
        allocator.free(self.sample_indices);
        allocator.free(self.wavelengths);
        allocator.free(self.radiance);
        allocator.free(self.jacobian);
        self.* = .{};
    }

    pub fn rebuildWavelengthList(
        self: *RadianceMemory,
        allocator: Allocator,
        new_rows: []radiance_wavelengths.RadianceSampleIndexRef,
        new_sample_indices: []u32,
        new_wavelengths: []radiance_wavelengths.RadianceWavelength,
        stamp: hashing.ReuseStamp,
    ) void {
        // RadianceMemory.rebuildWavelengthList -------------------------------------------------------------- |
        // Replace the exact wavelength route and invalidate dense results that indexed the old route.         |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.wavelength_rows);
        allocator.free(self.sample_indices);
        allocator.free(self.wavelengths);
        self.wavelength_rows = new_rows;
        self.sample_indices = new_sample_indices;
        self.wavelengths = new_wavelengths;
        self.active.wavelength_row_count = new_rows.len;
        self.active.sample_index_count = new_sample_indices.len;
        self.active.wavelength_count = new_wavelengths.len;
        self.wavelength_stamp = stamp;
        self.result_stamp = .{};
    }

    pub fn hasWavelengthList(
        self: RadianceMemory,
        stamp: hashing.ReuseStamp,
        row_count: usize,
        sample_index_count: usize,
        wavelength_count: usize,
    ) bool {
        // RadianceMemory.hasWavelengthList ------------------------------------------------------------------ |
        // Confirm the retained exact-wavelength route still matches the freshly computed sampling table.      |
        // ----------------------------------------------------------------------------------------------------|
        return self.wavelength_stamp.eql(stamp) and
            self.active.wavelength_row_count == row_count and
            self.active.sample_index_count == sample_index_count and
            self.active.wavelength_count == wavelength_count;
    }

    pub fn ensureResultCapacity(
        self: *RadianceMemory,
        allocator: Allocator,
        result_count: usize,
        wants_jacobian: bool,
    ) Allocator.Error!void {
        // RadianceMemory.ensureResultCapacity --------------------------------------------------------------- |
        // Ensure dense radiance column storage is large enough. Jacobian storage is retained only for routes  |
        // that gather active derivative lanes. Existing values are not preserved across growth because        |
        // prefetch fills every active result row before nominal gathers read it.                              |
        // ----------------------------------------------------------------------------------------------------|
        const radiance_replaced = try memory.ensureSliceCapacity(
            f64,
            allocator,
            &self.radiance,
            result_count,
        );
        var jacobian_replaced = false;
        if (wants_jacobian) {
            jacobian_replaced = try memory.ensureSliceCapacity(
                jacobian_states.Vector,
                allocator,
                &self.jacobian,
                result_count,
            );
            self.active.result_jacobian_count = result_count;
        } else {
            allocator.free(self.jacobian);
            self.jacobian = &.{};
            self.active.result_jacobian_count = 0;
        }
        if (radiance_replaced or jacobian_replaced) self.result_stamp = .{};
        self.active.result_count = result_count;
    }

    pub fn resultsValid(
        self: RadianceMemory,
        stamp: hashing.ReuseStamp,
        wants_jacobian: bool,
    ) bool {
        // RadianceMemory.resultsValid ----------------------------------------------------------------------- |
        // Check whether dense radiance rows were already computed for this exact route and solve controls.    |
        // ----------------------------------------------------------------------------------------------------|
        return self.result_stamp.eql(stamp) and
            self.result_stamp.value != 0 and
            self.active.result_count == self.active.wavelength_count and
            (!wants_jacobian or self.active.result_jacobian_count == self.active.result_count);
    }

    pub fn markResultsValid(self: *RadianceMemory, stamp: hashing.ReuseStamp) void {
        // RadianceMemory.markResultsValid ------------------------------------------------------------------- |
        // Publish dense radiance rows only after prefetch fills every active exact-wavelength slot.           |
        // ----------------------------------------------------------------------------------------------------|
        self.result_stamp = stamp;
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

    pub fn resultRows(self: *RadianceMemory) radiance_results.DenseRadianceResults {
        // RadianceMemory.resultRows ------------------------------------------------------------------------- |
        // Borrow the active dense radiance result prefixes.                                                   |
        // ----------------------------------------------------------------------------------------------------|
        return .{
            .radiance = self.radiance[0..self.active.result_count],
            .jacobian = self.jacobian[0..self.active.result_jacobian_count],
        };
    }
};
// ------------------------------------------------------------------------------------------------------------|

// RadianceMemoryActive -------------------------------------------------------------------------------------- |
// Active prefixes inside RadianceMemory backing arrays.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_row_count: usize                                                                        |
// [ 8..15] sample_index_count  : usize                                                                        |
// [16..23] wavelength_count    : usize                                                                        |
// [24..31] result_count        : usize                                                                        |
// [32..39] result_jacobian_count: usize                                                                       |
pub const RadianceMemoryActive = struct {
    wavelength_row_count: usize = 0,
    sample_index_count: usize = 0,
    wavelength_count: usize = 0,
    result_count: usize = 0,
    result_jacobian_count: usize = 0,
};
// ------------------------------------------------------------------------------------------------------------|

comptime {
    std.debug.assert(@sizeOf(RadianceMemoryActive) == 40);
    std.debug.assert(@sizeOf(RadianceMemory) == 136);
}
