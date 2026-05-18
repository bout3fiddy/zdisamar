const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: name=16 B, value=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: name carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total also includes referenced storage above
pub const Parameter = struct {
    name: []const u8 = "",
    value: f64 = 0.0,

    pub fn validate(self: Parameter) errors.Error!void {
        if (self.name.len == 0 or !std.math.isFinite(self.value)) {
            return errors.Error.InvalidRequest;
        }
    }
};

// layout(64-bit):
//   size: 40 B, align: 8 B
//   field storage: albedo=8 B, pressure_hpa=8 B, parameters=16 B, kind=1 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 0 bool-storage slack = 56 bits
//   out-of-line: parameters carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 40 B (0.039 KiB); total also includes referenced storage above
pub const Surface = struct {
    pub const Kind = enum {
        lambertian,
        wavel_dependent,

        pub fn parse(value: []const u8) errors.Error!Kind {
            if (std.mem.eql(u8, value, "lambertian")) return .lambertian;
            if (std.mem.eql(u8, value, "wavel_dependent")) return .wavel_dependent;
            return errors.Error.InvalidRequest;
        }

        pub fn label(self: Kind) []const u8 {
            return @tagName(self);
        }
    };

    kind: Kind = .lambertian,
    // UNITS:
    //   `albedo` is a unitless hemispherical reflectance in the normalized `[0, 1]`
    //   range.
    albedo: f64 = 0.0,
    // UNITS:
    //   Optional surface pressure is expressed in hectopascals so canonical
    //   surface metadata can preserve the boundary pressure used by vendor-like
    //   interval and cloud-fraction configurations.
    pressure_hpa: f64 = 0.0,
    parameters: []const Parameter = &[_]Parameter{},

    pub fn validate(self: Surface) errors.Error!void {
        if (self.albedo < 0.0 or self.albedo > 1.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.pressure_hpa != 0.0 and (!std.math.isFinite(self.pressure_hpa) or self.pressure_hpa <= 0.0)) {
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
