const std = @import("std");

const instrument_average = @import("../spectrum/instrument_average.zig");
const jacobian_states = @import("../rtm/jacobian_states.zig");

const Allocator = std.mem.Allocator;

// spectrum.zig -----------------------------------------------------------------------------------------------|
// Public spectrum output owner for the explicit forward route.                                           |
//                                                                                                             |
// ownership boundary                                                                                          |
//   Spectrum owns copied product-grid arrays returned across the root/API boundary. Session cache rows,       |
//   setup tables, worker memory, and solar lookup memory remain outside this output object.                   |
// ------------------------------------------------------------------------------------------------------------|

// Spectrum ---------------------------------------------------------------------------------------------------|
// Owned product-grid spectrum arrays returned by root run calls.                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 72 B (0.070 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelength_nm : []f64                                                                              |
// [16..31] radiance      : []f64                                                                              |
// [32..47] irradiance    : []f64                                                                              |
// [48..63] reflectance   : []f64                                                                              |
// [64..79] jacobian      : []Vector                                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   Every slice owns one product-grid heap array and shares the same sample count.                            |
pub const Spectrum = struct {
    wavelength_nm: []f64 = &.{},
    radiance: []f64 = &.{},
    irradiance: []f64 = &.{},
    reflectance: []f64 = &.{},
    jacobian: []jacobian_states.Vector = &.{},

    pub fn deinit(self: *Spectrum, allocator: Allocator) void {
        // Spectrum.deinit ------------------------------------------------------------------------------------|
        // Release product-grid output arrays.                                                                 |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.jacobian);
        allocator.free(self.reflectance);
        allocator.free(self.irradiance);
        allocator.free(self.radiance);
        allocator.free(self.wavelength_nm);
        self.* = .{};
    }

    pub fn sampleCount(self: Spectrum) usize {
        // Spectrum.sampleCount -------------------------------------------------------------------------------|
        // Return the public product-grid length shared by every output array.                                 |
        // ----------------------------------------------------------------------------------------------------|
        return self.wavelength_nm.len;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// SpectrumRunSummary -----------------------------------------------------------------------------------------|
// Scalar accounting emitted by the final radiance/irradiance-to-reflectance assembly.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..71] reflectance_assembly : ReflectanceAssemblySummary                                                  |
pub const SpectrumRunSummary = struct {
    reflectance_assembly: instrument_average.ReflectanceAssemblySummary = .{},
};
// ------------------------------------------------------------------------------------------------------------|

// SpectrumRunResult ------------------------------------------------------------------------------------------|
// Owned spectrum plus scalar summary returned from one public forward run.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 152 B (0.148 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 79] spectrum : Spectrum                                                                              |
// [ 80..151] summary  : SpectrumRunSummary                                                                    |
pub const SpectrumRunResult = struct {
    spectrum: Spectrum = .{},
    summary: SpectrumRunSummary = .{},

    pub fn deinit(self: *SpectrumRunResult, allocator: Allocator) void {
        // SpectrumRunResult.deinit ---------------------------------------------------------------------------|
        // Release the owned spectrum arrays; summary fields are scalar.                                       |
        // ----------------------------------------------------------------------------------------------------|
        self.spectrum.deinit(allocator);
        self.summary = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

comptime {
    std.debug.assert(@sizeOf(Spectrum) == 80);
    std.debug.assert(@sizeOf(SpectrumRunSummary) == 72);
    std.debug.assert(@sizeOf(SpectrumRunResult) == 152);
}
