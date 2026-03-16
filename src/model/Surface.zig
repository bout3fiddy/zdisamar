const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");

pub const Parameter = struct {
    name: []const u8 = "",
    value: f64 = 0.0,

    pub fn validate(self: Parameter) errors.Error!void {
        if (self.name.len == 0 or !std.math.isFinite(self.value)) {
            return errors.Error.InvalidRequest;
        }
    }
};

pub const Surface = struct {
    kind: []const u8 = "lambertian",
    provider: []const u8 = "",
    albedo: f64 = 0.0,
    parameters: []const Parameter = &[_]Parameter{},

    pub fn validate(self: Surface) errors.Error!void {
        if (self.kind.len == 0) {
            return errors.Error.InvalidRequest;
        }
        if (self.albedo < 0.0 or self.albedo > 1.0) {
            return errors.Error.InvalidRequest;
        }
        for (self.parameters) |parameter| {
            try parameter.validate();
        }
    }

    pub fn deinitOwned(self: *Surface, allocator: Allocator) void {
        if (self.parameters.len != 0) allocator.free(self.parameters);
        self.parameters = &[_]Parameter{};
    }
};

test "surface accepts named parameters" {
    try (Surface{
        .kind = "lambertian",
        .parameters = &[_]Parameter{
            .{ .name = "roughness_hint", .value = 0.03 },
            .{ .name = "slope_hint", .value = 0.02 },
        },
    }).validate();
}
