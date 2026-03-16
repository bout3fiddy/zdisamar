const std = @import("std");
const Axes = @import("Axes.zig");

pub const Error = error{
    ShapeMismatch,
    IndexOutOfRange,
} || Axes.Error;

pub const HotColumns = struct {
    temperature_k: []const f64,
    pressure_pa: []const f64,
    absorber_density: []const f64,
};

pub const ColdMetadata = struct {
    has_clouds: bool = false,
    has_aerosols: bool = false,
    climatology_tag: []const u8 = "none",
};

pub const LayerView = struct {
    temperature_k: f64,
    pressure_pa: f64,
    absorber_density: f64,
};

pub const AtmosphereSoA = struct {
    axis: Axes.LayerAxis,
    hot: HotColumns,
    cold: ColdMetadata = .{},

    pub fn init(axis: Axes.LayerAxis, hot: HotColumns, cold: ColdMetadata) Error!AtmosphereSoA {
        try axis.validate();
        const expected = axis.layer_count;

        if (hot.temperature_k.len != expected) return Error.ShapeMismatch;
        if (hot.pressure_pa.len != expected) return Error.ShapeMismatch;
        if (hot.absorber_density.len != expected) return Error.ShapeMismatch;

        return .{
            .axis = axis,
            .hot = hot,
            .cold = cold,
        };
    }

    pub fn layer(self: AtmosphereSoA, layer_index: u32) Error!LayerView {
        try self.axis.validate();
        if (layer_index >= self.axis.layer_count) return Error.IndexOutOfRange;

        return .{
            .temperature_k = self.hot.temperature_k[layer_index],
            .pressure_pa = self.hot.pressure_pa[layer_index],
            .absorber_density = self.hot.absorber_density[layer_index],
        };
    }
};

test "atmosphere SoA keeps hot numeric columns aligned while cold metadata stays separate" {
    const temperature = [_]f64{ 280.0, 275.0, 270.0 };
    const pressure = [_]f64{ 101325.0, 85000.0, 70000.0 };
    const absorber = [_]f64{ 1.0e-6, 8.0e-7, 6.0e-7 };

    const atmosphere = try AtmosphereSoA.init(
        .{ .layer_count = 3 },
        .{
            .temperature_k = &temperature,
            .pressure_pa = &pressure,
            .absorber_density = &absorber,
        },
        .{
            .has_clouds = true,
            .climatology_tag = "us-standard",
        },
    );

    const layer_1 = try atmosphere.layer(1);
    try std.testing.expectApproxEqRel(@as(f64, 275.0), layer_1.temperature_k, 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 85000.0), layer_1.pressure_pa, 1e-12);
    try std.testing.expect(atmosphere.cold.has_clouds);
    try std.testing.expectEqualStrings("us-standard", atmosphere.cold.climatology_tag);
}
