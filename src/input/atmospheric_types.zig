const std = @import("std");

pub const AbsorberSpecies = enum {
    o2_o2,
    o2,

    pub fn isLineAbsorbing(self: AbsorberSpecies) bool {
        return switch (self) {
            .o2 => true,
            else => false,
        };
    }

    pub fn isCrossSection(self: AbsorberSpecies) bool {
        return switch (self) {
            .o2_o2 => true,
            else => false,
        };
    }

    pub fn isColumnFittable(self: AbsorberSpecies) bool {
        return switch (self) {
            .o2, .o2_o2 => false,
        };
    }

    pub fn isProfileFittable(self: AbsorberSpecies) bool {
        return self.isColumnFittable();
    }

    pub fn hitranIndex(self: AbsorberSpecies) ?u8 {
        return switch (self) {
            .o2 => 7,
            else => null,
        };
    }

    pub fn fromVendorName(name: []const u8) ?AbsorberSpecies {
        const map = .{
            .{ "O2-O2", .o2_o2 },
            .{ "O2", .o2 },
        };
        inline for (map) |entry| {
            if (std.mem.eql(u8, name, entry[0])) return entry[1];
        }
        return null;
    }
};
