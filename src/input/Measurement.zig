const std = @import("std");
const Binding = @import("Binding.zig").Binding;
const SpectralWindow = @import("Bands.zig").SpectralWindow;
const errors = @import("../common/errors.zig");
const Allocator = std.mem.Allocator;

// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: band=16 B, exclude=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: band, exclude carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above
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

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: floor=8 B, from_source_noise=1 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
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

// layout(64-bit):
//   size: 128 B, align: 8 B
//   field storage: 125 B across 6 fields; largest: source=56 B, mask=32 B, product_name=16 B; padding: 3 B (24 bits)
//   unused bits: 24 padding + 0 bool-storage slack = 24 bits
//   out-of-line: product_name carry references/descriptors; referenced storage is not included in size
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 128 B (0.125 KiB); total also includes referenced storage above
pub const Measurement = struct {
    product_name: []const u8 = "",
    observable: Quantity = .radiance,
    // UNITS:
    //   `sample_count` counts discrete wavelength samples on the selected measurement
    //   grid; it is not a spectral width or resolution value.
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

    pub fn resolvedProductName(self: Measurement) []const u8 {
        if (self.product_name.len != 0) return self.product_name;
        return self.observable.label();
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
