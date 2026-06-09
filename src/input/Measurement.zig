const std = @import("std");
const Binding = @import("Binding.zig").Binding;
const SpectralWindow = @import("Bands.zig").SpectralWindow;
const errors = @import("../common/errors.zig");
const Allocator = std.mem.Allocator;

// Measurement.zig --------------------------------------------------------------------------------------------|
// Measurement product metadata, spectral masks, and simple error model controls.                              |
//                                                                                                             |
// data                                                                                                        |
//   SpectralMask stores one band id and optional exclusion windows. ErrorModel carries covariance switches.   |
//   Measurement stores product identity, source binding, sample count, mask, and error model.                 |
//                                                                                                             |
// ownership                                                                                                   |
//   Measurement owns only nested mask exclusion rows when cloned by callers. The source binding owns its own  |
//   copied names.                                                                                             |
// ------------------------------------------------------------------------------------------------------------|

// SpectralMask -----------------------------------------------------------------------------------------------|
// Band selection plus exclusion windows.                                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] band    : []const u8                                                                               |
// [16..31] exclude : []const SpectralWindow                                                                   |
//                                                                                                             |
// referenced storage                                                                                          |
//   band points at name bytes. exclude points at out-of-line SpectralWindow rows released by deinitOwned.     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total also includes referenced mask storage                     |
pub const SpectralMask = struct {
    band: []const u8 = "",
    exclude: []const SpectralWindow = &[_]SpectralWindow{},

    pub fn validate(self: SpectralMask) errors.Error!void {
        var previous_end_nm: f64 = 0.0;
        for (self.exclude, 0..) |window, index| {
            try window.validate();
            if (index != 0 and window.start_nm < previous_end_nm) {
                return errors.Error.InvalidRequest;
            }
            previous_end_nm = window.end_nm;
        }
    }

    pub fn deinitOwned(self: *SpectralMask, allocator: Allocator) void {
        if (self.exclude.len != 0) allocator.free(self.exclude);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

// ErrorModel -------------------------------------------------------------------------------------------------|
// Simple measurement-error controls.                                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] floor             : f64                                                                             |
// [8.. 8] from_source_noise : bool                                                                            |
// [9..15] trailing padding  : 7 B                                                                             |
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live error-model count                   |
pub const ErrorModel = struct {
    from_source_noise: bool = false,
    floor: f64 = 0.0,

    pub fn definesCovariance(self: ErrorModel) bool {
        return self.from_source_noise or self.floor > 0.0;
    }

    pub fn validate(self: ErrorModel) errors.Error!void {
        if (!std.math.isFinite(self.floor) or self.floor < 0.0) {
            return errors.Error.InvalidRequest;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub const Quantity = enum {
    radiance,
    irradiance,
    reflectance,
    slant_column,

    pub fn parse(value: []const u8) errors.Error!Quantity {
        if (std.mem.eql(u8, value, "radiance")) return .radiance;
        if (std.mem.eql(u8, value, "irradiance")) return .irradiance;
        if (std.mem.eql(u8, value, "reflectance")) return .reflectance;
        if (std.mem.eql(u8, value, "slant_column")) return .slant_column;
        return errors.Error.InvalidRequest;
    }

    pub fn label(self: Quantity) []const u8 {
        return @tagName(self);
    }
};

// Measurement ------------------------------------------------------------------------------------------------|
// Public measurement request header.                                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 128 B (0.125 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] product_name : []const u8                                                                        |
// [ 16.. 71] source       : Binding                                                                           |
// [ 72..103] mask         : SpectralMask                                                                      |
// [104..119] error_model  : ErrorModel                                                                        |
// [120..123] sample_count : u32                                                                               |
// [124..124] observable   : Quantity                                                                          |
// [125..127] trailing padding : 3 B                                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   product_name and nested binding/mask fields can point at out-of-line storage.                             |
//                                                                                                             |
// unused bits: 24 padding + 6 enum-storage slack = 30 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 128 B (0.125 KiB); total also includes referenced measurement storage             |
pub const Measurement = struct {
    product_name: []const u8 = "",
    observable: Quantity = .radiance,
    sample_count: u32 = 0,
    source: Binding = .none,
    mask: SpectralMask = .{},
    error_model: ErrorModel = .{},

    pub fn validate(self: Measurement) errors.Error!void {
        if (self.sample_count == 0) return errors.Error.InvalidRequest;
        try self.source.validate();
        try self.mask.validate();
        try self.error_model.validate();
    }

    pub fn includesWavelength(self: Measurement, wavelength_nm: f64) bool {
        _ = self.mask.band;
        for (self.mask.exclude) |window| {
            if (wavelength_nm >= window.start_nm and wavelength_nm <= window.end_nm) {
                return false;
            }
        }
        return true;
    }

    pub fn selectedSampleCount(self: Measurement, wavelengths_nm: []const f64) u32 {
        var count: u32 = 0;
        for (wavelengths_nm) |wavelength_nm| {
            if (self.includesWavelength(wavelength_nm)) count += 1;
        }
        return count;
    }

    pub fn deinitOwned(self: *Measurement, allocator: Allocator) void {
        self.mask.deinitOwned(allocator);
        self.* = .{};
    }
};

pub const MeasurementVector = Measurement;
// ------------------------------------------------------------------------------------------------------------|
