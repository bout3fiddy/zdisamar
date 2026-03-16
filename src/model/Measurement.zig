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
