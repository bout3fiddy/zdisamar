const std = @import("std");
const build_options = @import("build_options");
const ztracy = @import("ztracy");

const SourceLocation = std.builtin.SourceLocation;

// trace.zig ----------------------------------------------------------------------------------------------------|
// ztracy timeline facade used by product code without importing trace writers or CLI scaffolding.               |
//                                                                                                               |
// called from                                                                                                   |
//   input/o2a_reference/run.zig marks case loading, scene build, optical setup, weak-cutoff, solar rewindow,    |
//   and RTM config preparation.                                                                                 |
//   instrument-grid calculation marks wavelength sampling, forward misses, prefetch workers, convolution,       |
//   reflectance assembly, and Jacobian processing.                                                              |
//   optical_properties/state_build marks absorber/profile setup, vertical support work, and parallel chunks.    |
//   LABOS marks Fourier terms, PLM basis, layer build/doubling, orders, reflectance, and Jacobian weighting.    |
//   optimal_estimation/retrieval marks iteration, RTM/Jacobian calls, normal-system solve, updates, and         |
//   correction paths.                                                                                           |
//                                                                                                               |
// main paths                                                                                                    |
//   enabled is true only when build_options.enable_ztracy is present and true. build.zig supplies either the    |
//   real ztracy dependency or the no-op stub module.                                                            |
//   Zone is an EnabledZone with a ztracy context in trace builds and a DisabledZone with no stored state in     |
//   normal product/test builds.                                                                                 |
//   static/deep/named zones, thread names, frame marks, messages, and plots all keep call sites in product code |
//   while compiling to no-op behavior when tracing is disabled.                                                 |
//                                                                                                               |
// runtime shape                                                                                                 |
//   This facade owns no files, buffers, or capture lifecycle. Trace CLIs and retained trace outputs live under  |
//   scaffolding/instrumentation; product code only sees these inline wrappers.                                  |
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
