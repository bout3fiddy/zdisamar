const std = @import("std");
const Binding = @import("Binding.zig").Binding;
const SpectralWindow = @import("Bands.zig").SpectralWindow;
const errors = @import("../core/errors.zig");
const Allocator = std.mem.Allocator;

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

pub const Measurement = struct {
    product: []const u8 = "radiance",
    observable: []const u8 = "",
    sample_count: u32 = 0,
    source: Binding = .{},
    mask: SpectralMask = .{},
    error_model: ErrorModel = .{},

    pub fn validate(self: Measurement) errors.Error!void {
        if (self.product.len == 0) return errors.Error.InvalidRequest;
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

test "measurement validates source masks and error model" {
    try (Measurement{
        .product = "radiance",
        .observable = "radiance",
        .sample_count = 121,
        .source = .{ .kind = .stage_product, .name = "truth_radiance" },
        .mask = .{
            .band = "o2a",
            .exclude = &[_]SpectralWindow{
                .{ .start_nm = 759.35, .end_nm = 759.55 },
                .{ .start_nm = 770.50, .end_nm = 770.80 },
            },
        },
        .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
    }).validate();
}

test "measurement sample selection honors excluded spectral windows" {
    const measurement: Measurement = .{
        .product = "radiance",
        .observable = "radiance",
        .sample_count = 3,
        .source = .{ .kind = .stage_product, .name = "truth_radiance" },
        .mask = .{
            .exclude = &[_]SpectralWindow{
                .{ .start_nm = 760.0, .end_nm = 761.0 },
            },
        },
    };
    const wavelengths = [_]f64{ 759.5, 760.5, 761.5, 762.0 };

    try std.testing.expect(measurement.includesWavelength(759.5));
    try std.testing.expect(!measurement.includesWavelength(760.5));
    try std.testing.expectEqual(@as(u32, 3), measurement.selectedSampleCount(&wavelengths));
}
