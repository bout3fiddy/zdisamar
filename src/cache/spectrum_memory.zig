const std = @import("std");

const memory = @import("../common/memory.zig");
const sampling_table = @import("../spectrum/sampling_table.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{
    ShapeMismatch,
};

// spectrum_memory.zig --------------------------------------------------------------------------------------- |
// Allocation home for retained spectrum sampling rows and side-array kernels.                                 |
//                                                                                                             |
// provenance                                                                                                  |
//   Splits the old `ProductStorage.wavelength_sampling` owner from main:                                      |
//   `src/forward_model/instrument_grid/grid_calculation/storage.zig`. The row shapes themselves live in       |
//   `spectrum/sampling_table.zig`, ported from `wavelength_plan.zig`.                                         |
//                                                                                                             |
// ownership boundary                                                                                          |
//   This memory object owns only computed sampling rows and side arrays. It stores no scene, instrument       |
//   controls, line tables, solar data, or transport settings. Callers still pass those physics inputs into    |
//   setup/build functions explicitly.                                                                         |
// ------------------------------------------------------------------------------------------------------------|

// SpectrumMemory -------------------------------------------------------------------------------------------- |
// Reusable allocation owner for spectrum sampling rows and table-wide side samples.                           |
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
//   rows, kernel_offsets_nm, and kernel_weights own heap arrays released by deinit.                           |
pub const SpectrumMemory = struct {
    rows: []sampling_table.SpectrumSamplingRow = &.{},
    kernel_offsets_nm: []f64 = &.{},
    kernel_weights: []f64 = &.{},

    pub fn deinit(self: *SpectrumMemory, allocator: Allocator) void {
        // SpectrumMemory.deinit ----------------------------------------------------------------------------- |
        // Release retained sampling rows and side-array kernels.                                              |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        allocator.free(self.kernel_offsets_nm);
        allocator.free(self.kernel_weights);
        self.* = .{};
    }

    pub fn ensureCapacity(
        self: *SpectrumMemory,
        allocator: Allocator,
        row_count: usize,
        side_sample_count: usize,
    ) Allocator.Error!void {
        // SpectrumMemory.ensureCapacity --------------------------------------------------------------------- |
        // Ensure backing arrays are large enough for the next sampling-table build. Existing values are not   |
        // preserved across growth because callers refill the full active prefix after sizing.                 |
        // ----------------------------------------------------------------------------------------------------|
        _ = try memory.ensureSliceCapacity(
            sampling_table.SpectrumSamplingRow,
            allocator,
            &self.rows,
            row_count,
        );
        _ = try memory.ensureSliceCapacity(f64, allocator, &self.kernel_offsets_nm, side_sample_count);
        _ = try memory.ensureSliceCapacity(f64, allocator, &self.kernel_weights, side_sample_count);
    }

    pub fn table(
        self: *const SpectrumMemory,
        row_count: usize,
        side_sample_count: usize,
    ) Error!sampling_table.SpectrumSamplingTable {
        // SpectrumMemory.table ------------------------------------------------------------------------------ |
        // Borrow an active sampling-table prefix after the caller has filled the retained arrays.             |
        // ----------------------------------------------------------------------------------------------------|
        if (row_count > self.rows.len or
            side_sample_count > self.kernel_offsets_nm.len or
            side_sample_count > self.kernel_weights.len)
        {
            return error.ShapeMismatch;
        }
        return .{
            .rows = self.rows[0..row_count],
            .kernel_storage = .{
                .offsets_nm = self.kernel_offsets_nm[0..side_sample_count],
                .weights = self.kernel_weights[0..side_sample_count],
            },
        };
    }
};
// ------------------------------------------------------------------------------------------------------------|

comptime {
    std.debug.assert(@sizeOf(SpectrumMemory) == 48);
}
