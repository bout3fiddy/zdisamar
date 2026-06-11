const std = @import("std");

const units = @import("../common/units.zig");

const Allocator = std.mem.Allocator;

// WeakLineCutoffMemory ---------------------------------------------------------------------------------------|
// Retrieval/setup memory for weak-line cutoff support wavelengths and wavenumbers.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelengths_nm : []f64                                                                             |
// [16..31] wavenumbers_cm1: []f64                                                                             |
//                                                                                                             |
// referenced storage                                                                                          |
//   Both slices own dense f64 arrays with matching lengths and are released by deinit.                        |
pub const WeakLineCutoffMemory = struct {
    wavelengths_nm: []f64 = &.{},
    wavenumbers_cm1: []f64 = &.{},

    pub fn deinit(self: *WeakLineCutoffMemory, allocator: Allocator) void {
        // WeakLineCutoffMemory.deinit ------------------------------------------------------------------------|
        // Release retained wavelength and wavenumber support grids.                                           |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.wavelengths_nm);
        allocator.free(self.wavenumbers_cm1);
        self.* = .{};
    }

    pub fn valid(self: WeakLineCutoffMemory) bool {
        // WeakLineCutoffMemory.valid -------------------------------------------------------------------------|
        // Check that both support grids are present and length-aligned.                                       |
        // ----------------------------------------------------------------------------------------------------|
        return self.wavelengths_nm.len >= 2 and self.wavelengths_nm.len == self.wavenumbers_cm1.len;
    }

    pub fn replaceFromSupport(
        self: *WeakLineCutoffMemory,
        allocator: Allocator,
        support_wavelengths_nm: []const f64,
    ) !void {
        // WeakLineCutoffMemory.replaceFromSupport ------------------------------------------------------------|
        // Replace support wavelengths and rebuild matching wavenumbers in one ownership handoff.              |
        // ----------------------------------------------------------------------------------------------------|
        const wavelengths = try allocator.dupe(f64, support_wavelengths_nm);
        errdefer allocator.free(wavelengths);
        const wavenumbers = try allocator.alloc(f64, support_wavelengths_nm.len);
        errdefer allocator.free(wavenumbers);

        for (support_wavelengths_nm, wavenumbers) |wavelength_nm, *wavenumber_cm1| {
            wavenumber_cm1.* = units.wavelengthToWavenumberCm1(wavelength_nm);
        }

        self.deinit(allocator);
        self.wavelengths_nm = wavelengths;
        self.wavenumbers_cm1 = wavenumbers;
    }
};
// ------------------------------------------------------------------------------------------------------------|
