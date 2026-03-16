const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");
const Binding = @import("Binding.zig").Binding;

pub const SpectroscopyMode = enum {
    none,
    line_by_line,
    cia,
    cross_sections,
};

pub const Spectroscopy = struct {
    mode: SpectroscopyMode = .none,
    provider: []const u8 = "",
    line_list: Binding = .{},
    line_mixing: Binding = .{},
    strong_lines: Binding = .{},
    cia_table: Binding = .{},
    operational_lut: Binding = .{},

    pub fn validate(self: Spectroscopy) errors.Error!void {
        try self.line_list.validate();
        try self.line_mixing.validate();
        try self.strong_lines.validate();
        try self.cia_table.validate();
        try self.operational_lut.validate();

        if (self.mode == .none and
            (self.provider.len != 0 or
                self.line_list.enabled() or
                self.line_mixing.enabled() or
                self.strong_lines.enabled() or
                self.cia_table.enabled() or
                self.operational_lut.enabled()))
        {
            return errors.Error.InvalidRequest;
        }
    }
};

pub const Absorber = struct {
    id: []const u8 = "",
    species: []const u8 = "",
    profile_source: Binding = .{},
    spectroscopy: Spectroscopy = .{},

    pub fn validate(self: Absorber) errors.Error!void {
        if (self.id.len == 0 or self.species.len == 0) {
            return errors.Error.InvalidRequest;
        }
        try self.profile_source.validate();
        try self.spectroscopy.validate();
    }
};

pub const AbsorberSet = struct {
    items: []const Absorber = &[_]Absorber{},

    pub fn validate(self: AbsorberSet) errors.Error!void {
        for (self.items, 0..) |absorber, index| {
            try absorber.validate();
            for (self.items[index + 1 ..]) |other| {
                if (std.mem.eql(u8, absorber.id, other.id)) {
                    return errors.Error.InvalidRequest;
                }
            }
        }
    }

    pub fn clone(self: AbsorberSet, allocator: Allocator) !AbsorberSet {
        return .{
            .items = try allocator.dupe(Absorber, self.items),
        };
    }

    pub fn deinitOwned(self: *AbsorberSet, allocator: Allocator) void {
        if (self.items.len != 0) allocator.free(self.items);
        self.* = .{};
    }
};

test "absorber set validates explicit spectroscopy bindings" {
    const valid: AbsorberSet = .{
        .items = &[_]Absorber{
            .{
                .id = "o2",
                .species = "o2",
                .profile_source = .{ .kind = .atmosphere },
                .spectroscopy = .{
                    .mode = .line_by_line,
                    .provider = "builtin.cross_sections",
                    .line_list = .{ .kind = .asset, .name = "o2_hitran" },
                },
            },
            .{
                .id = "o2o2",
                .species = "o2o2",
                .profile_source = .{ .kind = .atmosphere },
                .spectroscopy = .{
                    .mode = .cia,
                    .cia_table = .{ .kind = .asset, .name = "o2o2_cia" },
                },
            },
        },
    };
    try valid.validate();

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (AbsorberSet{
            .items = &[_]Absorber{
                .{
                    .id = "o2",
                    .species = "o2",
                    .spectroscopy = .{
                        .mode = .none,
                        .line_list = .{ .kind = .asset, .name = "unexpected" },
                    },
                },
            },
        }).validate(),
    );
}
