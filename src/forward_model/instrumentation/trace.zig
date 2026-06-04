const std = @import("std");
const build_options = @import("build_options");
const ztracy = @import("ztracy");

const SourceLocation = std.builtin.SourceLocation;

// trace.zig ----------------------------------------------------------------------------------------------------|
// ztracy facade for timeline captures. Disabled builds return zero-size zones and no-op markers/counters.       |
//                                                                                                               |
// inserted in                                                                                                   |
//   input preparation: case loading, scene building, optical setup, grids, and RTM config                       |
//   product simulation: sampling, cache prefetch, convolution, reflectance, and Jacobian processing             |
//   LABOS: Fourier loop, PLM basis, RT layer build, layer doubling, orders, reflectance, and Jacobians          |
//   optimal estimation: iteration, RTM/Jacobian call, normal system, update, and correction paths               |
//   trace CLIs: frame markers, start/end messages, and named capture boundaries                                 |
//                                                                                                               |
// enabled by                                                                                                    |
//   enable_ztracy plus the real ztracy dependency; otherwise this imports the no-op shim                        |
// --------------------------------------------------------------------------------------------------------------|
pub const enabled: bool = enabled_by_build: {
    if (!@hasDecl(build_options, "enable_ztracy")) break :enabled_by_build false;
    break :enabled_by_build build_options.enable_ztracy;
};

const EnabledZone = struct {
    ctx: ?ztracy.ZoneCtx,

    pub inline fn end(self: @This()) void {
        if (self.ctx) |ctx| ctx.End();
    }

    pub inline fn value(self: @This(), val: u64) void {
        if (self.ctx) |ctx| ctx.Value(val);
    }
};

const DisabledZone = struct {
    pub inline fn end(self: @This()) void {
        _ = self;
    }

    pub inline fn value(self: @This(), val: u64) void {
        _ = self;
        _ = val;
    }
};

pub const Zone = zone_type: {
    if (enabled) break :zone_type EnabledZone;
    break :zone_type DisabledZone;
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
