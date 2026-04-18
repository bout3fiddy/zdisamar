const std = @import("std");
const errors = @import("../../core/errors.zig");

pub const Id = union(enum) {
    unset,
    generic,
    tropomi,
    synthetic,
    custom: []const u8,

    pub fn parse(value: []const u8) Id {
        if (value.len == 0) return .unset;
        if (std.mem.eql(u8, value, "generic")) return .generic;
        if (std.mem.eql(u8, value, "tropomi")) return .tropomi;
        if (std.mem.eql(u8, value, "synthetic")) return .synthetic;
        return .{ .custom = value };
    }

    pub fn label(self: Id) []const u8 {
        return switch (self) {
            .unset => "",
            .generic => "generic",
            .tropomi => "tropomi",
            .synthetic => "synthetic",
            .custom => |value| value,
        };
    }

    pub fn validate(self: Id) errors.Error!void {
        switch (self) {
            .unset => return errors.Error.MissingObservationInstrument,
            .custom => |value| if (value.len == 0) return errors.Error.MissingObservationInstrument,
            .generic, .tropomi, .synthetic => {},
        }
    }
};
