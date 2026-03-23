//! Purpose:
//!   Define the canonical surface-reflectance configuration exposed to transport and
//!   plugin providers.
//!
//! Physics:
//!   The surface model captures broadband Lambertian or wavelength-dependent reflectance
//!   hints that participate in top-of-atmosphere radiance synthesis.
//!
//! Vendor:
//!   `surface albedo configuration stage`
//!
//! Design:
//!   The Zig model keeps surface settings as a small typed record with explicit optional
//!   parameters instead of passing loosely structured key/value maps through the engine.
//!
//! Invariants:
//!   Surface albedo remains within `[0, 1]` and any auxiliary parameters must be named
//!   and finite.
//!
//! Validation:
//!   Unit tests below cover kind parsing and parameter validation.
const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");

/// Purpose:
///   Carry one named auxiliary surface parameter.
pub const Parameter = struct {
    name: []const u8 = "",
    value: f64 = 0.0,

    /// Purpose:
    ///   Ensure the parameter is named and finite.
    pub fn validate(self: Parameter) errors.Error!void {
        if (self.name.len == 0 or !std.math.isFinite(self.value)) {
            return errors.Error.InvalidRequest;
        }
    }
};

/// Purpose:
///   Describe the surface reflectance model requested by the scene.
pub const Surface = struct {
    /// Purpose:
    ///   Enumerate the supported surface-reflectance shapes.
    pub const Kind = enum {
        lambertian,
        wavel_dependent,

        /// Purpose:
        ///   Parse the serialized surface-kind label.
        pub fn parse(value: []const u8) errors.Error!Kind {
            if (std.mem.eql(u8, value, "lambertian")) return .lambertian;
            if (std.mem.eql(u8, value, "wavel_dependent")) return .wavel_dependent;
            return errors.Error.InvalidRequest;
        }

        /// Purpose:
        ///   Return the canonical serialized label for the surface kind.
        pub fn label(self: Kind) []const u8 {
            return @tagName(self);
        }
    };

    kind: Kind = .lambertian,
    // UNITS:
    //   `albedo` is a unitless hemispherical reflectance in the normalized `[0, 1]`
    //   range.
    albedo: f64 = 0.0,
    parameters: []const Parameter = &[_]Parameter{},

    /// Purpose:
    ///   Ensure the surface configuration remains within physical bounds.
    pub fn validate(self: Surface) errors.Error!void {
        if (self.albedo < 0.0 or self.albedo > 1.0) {
            return errors.Error.InvalidRequest;
        }
        for (self.parameters) |parameter| {
            try parameter.validate();
        }
    }

    /// Purpose:
    ///   Release allocator-owned parameter storage.
    pub fn deinitOwned(self: *Surface, allocator: Allocator) void {
        if (self.parameters.len != 0) allocator.free(self.parameters);
        self.parameters = &[_]Parameter{};
    }
};

test "surface accepts named parameters" {
    const surface: Surface = .{
        .kind = .lambertian,
        .parameters = &[_]Parameter{
            .{ .name = "roughness_hint", .value = 0.03 },
            .{ .name = "slope_hint", .value = 0.02 },
        },
    };
    try std.testing.expectEqual(Surface.Kind.lambertian, surface.kind);
    try surface.validate();
    try std.testing.expectEqual(Surface.Kind.lambertian, try Surface.Kind.parse("lambertian"));
    try std.testing.expectEqual(Surface.Kind.wavel_dependent, try Surface.Kind.parse("wavel_dependent"));
    try std.testing.expectError(errors.Error.InvalidRequest, Surface.Kind.parse("unknown_surface"));
}
