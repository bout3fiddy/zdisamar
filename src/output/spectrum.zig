const std = @import("std");

const instrument_average = @import("../spectrum/instrument_average.zig");
const jacobian_states = @import("../transport/jacobian_states.zig");

const Allocator = std.mem.Allocator;

// spectrum.zig -----------------------------------------------------------------------------------------------|
// Public spectrum output owner for the explicit O2 A forward route.                                           |
//                                                                                                             |
// ownership boundary                                                                                          |
//   O2Spectrum owns copied product-grid arrays returned across the root/API boundary. Session cache rows,     |
//   setup tables, worker memory, and solar lookup memory remain outside this output object.                   |
// ------------------------------------------------------------------------------------------------------------|

// O2Spectrum -------------------------------------------------------------------------------------------------|
// Owned product-grid spectrum arrays returned by root run calls.                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
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
pub const O2Spectrum = struct {
    wavelength_nm: []f64 = &.{},
    radiance: []f64 = &.{},
    irradiance: []f64 = &.{},
    reflectance: []f64 = &.{},
    jacobian: []jacobian_states.Vector = &.{},

    pub fn deinit(self: *O2Spectrum, allocator: Allocator) void {
        // O2Spectrum.deinit ----------------------------------------------------------------------------------|
        // Release product-grid output arrays.                                                                 |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.jacobian);
        allocator.free(self.reflectance);
        allocator.free(self.irradiance);
        allocator.free(self.radiance);
        allocator.free(self.wavelength_nm);
        self.* = .{};
    }

    pub fn sampleCount(self: O2Spectrum) usize {
        // O2Spectrum.sampleCount -----------------------------------------------------------------------------|
        // Return the public product-grid length shared by every output array.                                 |
        // ----------------------------------------------------------------------------------------------------|
        return self.wavelength_nm.len;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// O2SpectrumRunSummary ---------------------------------------------------------------------------------------|
// Scalar accounting emitted by the final radiance/irradiance-to-reflectance assembly.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..79] reflectance_assembly : ReflectanceAssemblySummary                                                  |
pub const O2SpectrumRunSummary = struct {
    reflectance_assembly: instrument_average.ReflectanceAssemblySummary = .{},
};
// ------------------------------------------------------------------------------------------------------------|

// O2SpectrumRunResult ----------------------------------------------------------------------------------------|
// Owned spectrum plus scalar summary returned from one public forward run.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 160 B (0.156 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 79] spectrum : O2Spectrum                                                                            |
// [ 80..159] summary  : O2SpectrumRunSummary                                                                  |
pub const O2SpectrumRunResult = struct {
    spectrum: O2Spectrum = .{},
    summary: O2SpectrumRunSummary = .{},

    pub fn deinit(self: *O2SpectrumRunResult, allocator: Allocator) void {
        // O2SpectrumRunResult.deinit -------------------------------------------------------------------------|
        // Release the owned spectrum arrays; summary fields are scalar.                                       |
        // ----------------------------------------------------------------------------------------------------|
        self.spectrum.deinit(allocator);
        self.summary = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

comptime {
    std.debug.assert(@sizeOf(O2Spectrum) == 80);
    std.debug.assert(@sizeOf(O2SpectrumRunSummary) == 80);
    std.debug.assert(@sizeOf(O2SpectrumRunResult) == 160);
}
