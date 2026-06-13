const std = @import("std");

const hashing = @import("../common/hashing.zig");
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
// [48..55] table_stamp      : ReuseStamp                                                                      |
//                                                                                                             |
// owned storage                                                                                               |
//   rows, kernel_offsets_nm, and kernel_weights own heap arrays released by deinit.                           |
//                                                                                                             |
// cache key                                                                                                   |
//   table_stamp identifies the wavelength-plan inputs that built the retained rows. A zero stamp means no     |
//   reusable table has been published yet.                                                                    |
pub const SpectrumMemory = struct {
    rows: []sampling_table.SpectrumSamplingRow = &.{},
    kernel_offsets_nm: []f64 = &.{},
    kernel_weights: []f64 = &.{},
    table_stamp: hashing.ReuseStamp = .{},

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

    pub fn takeTable(
        self: *SpectrumMemory,
        allocator: Allocator,
        owned_table: *sampling_table.OwnedSpectrumSamplingTable,
        stamp: hashing.ReuseStamp,
    ) void {
        // SpectrumMemory.takeTable ---------------------------------------------------------------------------|
        // Move an owned sampling table into retained session memory without copying the row or side arrays.   |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        allocator.free(self.kernel_offsets_nm);
        allocator.free(self.kernel_weights);
        self.rows = owned_table.rows;
        self.kernel_offsets_nm = owned_table.kernel_offsets_nm;
        self.kernel_weights = owned_table.kernel_weights;
        self.table_stamp = stamp;
        owned_table.* = .{};
    }

    pub fn hasTable(self: SpectrumMemory, stamp: hashing.ReuseStamp) bool {
        // SpectrumMemory.hasTable ----------------------------------------------------------------------------|
        // Check whether retained rows still match the caller's wavelength-plan inputs.                        |
        //                                                                                                     |
        // provenance                                                                                          |
        //   Mirrors main:`src/forward_model/instrument_grid/grid_calculation/storage.zig`                     |
        //   `wavelength_plan_valid` plus `wavelength_plan_key`; root.zig owns the explicit stamp contents.    |
        // ----------------------------------------------------------------------------------------------------|
        return self.table_stamp.value != 0 and self.table_stamp.eql(stamp);
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
    std.debug.assert(@sizeOf(SpectrumMemory) == 56);
}
