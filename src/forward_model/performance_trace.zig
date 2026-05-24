const std = @import("std");
const build_options = @import("build_options");
const ztracy = @import("ztracy");

const SourceLocation = std.builtin.SourceLocation;

// instrumentation: ztracy facade
// captures: phase zones, counters, and frames
// why: compile timeline tracing out of normal builds.
pub const enabled: bool = if (@hasDecl(build_options, "enable_ztracy"))
    build_options.enable_ztracy
else
    false;

// layout(64-bit, enable_ztracy=false):
//   size: 0 B, align: 1 B
//   field storage: 0 B; padding: 0 B (0 bits)
//   alternate: enable_ztracy=true stores ctx:?ztracy.ZoneCtx in the active branch
//   footprint: disabled branch has no runtime field storage
pub const Zone = if (enabled) struct {
    ctx: ?ztracy.ZoneCtx,

    pub inline fn end(self: Zone) void {
        if (self.ctx) |ctx| ctx.End();
    }

    pub inline fn value(self: Zone, val: u64) void {
        if (self.ctx) |ctx| ctx.Value(val);
    }
} else struct {
    // layout(64-bit, enable_ztracy=false):
    //   disabled branch struct: size 0 B, align 1 B
    //   footprint: no runtime field storage; no-op methods only
    pub inline fn end(self: Zone) void {
        _ = self;
    }

    pub inline fn value(self: Zone, val: u64) void {
        _ = self;
        _ = val;
    }
};

// instrumentation: trace zone
// captures: elapsed phase lifetime
// why: show which named model phase owns wall time.
pub inline fn staticZone(comptime src: SourceLocation, comptime name: [*:0]const u8) Zone {
    if (!enabled) return .{};
    return .{ .ctx = ztracy.ZoneN(src, name) };
}

// instrumentation: trace zones
// captures: nested work boundaries
// why: separate setup, optical preparation, RTM, and OE phases in Tracy.
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

// instrumentation: trace markers
// captures: frame/message/counter signals
// why: align runs and count hot-loop events inside a timeline capture.
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
