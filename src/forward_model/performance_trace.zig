const std = @import("std");
const build_options = @import("build_options");
const ztracy = @import("ztracy");

const SourceLocation = std.builtin.SourceLocation;

pub const enabled: bool = if (@hasDecl(build_options, "enable_ztracy"))
    build_options.enable_ztracy
else
    false;

pub const Zone = if (enabled) struct {
    ctx: ?ztracy.ZoneCtx,

    pub inline fn end(self: Zone) void {
        if (self.ctx) |ctx| ctx.End();
    }

    pub inline fn value(self: Zone, val: u64) void {
        if (self.ctx) |ctx| ctx.Value(val);
    }
} else struct {
    pub inline fn end(self: Zone) void {
        _ = self;
    }

    pub inline fn value(self: Zone, val: u64) void {
        _ = self;
        _ = val;
    }
};

pub inline fn staticZone(comptime src: SourceLocation, comptime name: [*:0]const u8) Zone {
    if (!enabled) return .{};
    return .{ .ctx = ztracy.ZoneN(src, name) };
}

pub inline fn deepStaticZone(comptime src: SourceLocation, comptime name: [*:0]const u8) Zone {
    return staticZone(src, name);
}

pub inline fn namedZone(comptime src: SourceLocation, name: []const u8) Zone {
    if (!enabled) return .{};
    const ctx = ztracy.Zone(src);
    ctx.Name(name);
    return .{ .ctx = ctx };
}

pub inline fn deepNamedZone(comptime src: SourceLocation, name: []const u8) Zone {
    return namedZone(src, name);
}

pub inline fn setThreadName(name: [*:0]const u8) void {
    if (enabled) ztracy.SetThreadName(name);
}

pub inline fn frameMark() void {
    if (enabled) ztracy.FrameMark();
}

pub inline fn message(text: []const u8) void {
    if (enabled) ztracy.Message(text);
}

pub inline fn plotU(comptime name: [*:0]const u8, value: u64) void {
    if (enabled) ztracy.PlotU(name, value);
}

pub inline fn plotF(comptime name: [*:0]const u8, value: f64) void {
    if (enabled) ztracy.PlotF(name, value);
}
