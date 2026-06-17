const std = @import("std");
const build_options = @import("build_options");
const ztracy = @import("ztracy");

const SourceLocation = std.builtin.SourceLocation;

// trace.zig --------------------------------------------------------------------------------------------------|
// ztracy timeline facade used by product code without importing trace writers or CLI scaffolding.             |
//                                                                                                             |
// called from                                                                                                 |
//   spectrum/spectrum_run.zig marks exact-wavelength work, dense radiance prefetch chunks, nominal row gather,|
//   postprocess bands, and reflectance assembly.                                                              |
//   rtm/solve.zig and rtm/layer_reflect_transmit.zig mark LABOS Fourier terms, layer visits, phase            |
//   matrix builds, doubling decisions, q-series work, and fixed-kernel product gates.                         |
//   rtm/scattering_orders.zig marks initial source setup, order transport, local source passes, retained      |
//   order accumulation, convergence exits, and paired Gaussian dot products.                                  |
//   cache/profile_line_memory.zig and setup refresh code may add retained setup zones as land.      |
//                                                                                                             |
// primary paths                                                                                               |
//   enabled is true only when build_options.enable_ztracy is present and true. build.zig supplies either the  |
//   real ztracy dependency or the no-op stub module.                                                          |
//   Zone is an EnabledZone with a ztracy context in trace builds and a DisabledZone with no stored state in   |
//   normal product/test builds.                                                                               |
//   static/deep/named zones, thread names, frame marks, messages, and plots keep call sites in product code   |
//   while compiling to no-op behavior when tracing is disabled.                                               |
//                                                                                                             |
// runtime shape                                                                                               |
//   This facade owns no files, buffers, or capture lifecycle. Trace CLIs and retained trace outputs live under|
//   scaffolding/instrumentation; product code only sees these inline wrappers and stable counter names.       |
//                                                                                                             |
// hot path                                                                                                    |
//   Trace calls sit inside exact-wavelength optics, spectrum prefetch, LABOS Fourier/order loops, fixed       |
//   doubling kernels, and final spectrum assembly. In normal builds, comptime enabled=false selects           |
//   DisabledZone and every inline wrapper returns before touching Tracy state. Trace harness builds keep the  |
//   same call sites but store the ztracy zone context in EnabledZone until end() is called.                   |
//                                                                                                             |
// memory                                                                                                      |
//   The product/test Zone is zero-size because DisabledZone stores no fields. Enabled trace harnesses carry   |
//   only the optional ztracy context returned by the selected dependency; capture buffers and timeline output |
//   stay in Tracy/scaffolding code, not in this facade.                                                       |
// ------------------------------------------------------------------------------------------------------------|
pub const enabled: bool = enabled_by_build: {
    if (!@hasDecl(build_options, "enable_ztracy")) break :enabled_by_build false;
    break :enabled_by_build build_options.enable_ztracy;
};

// EnabledZone ------------------------------------------------------------------------------------------------|
// Trace-enabled zone handle returned by Trace.* calls when ztracy is compiled in.                             |
//                                                                                                             |
// layout(64-bit, disabled ztracy stub)                                                                        |
// size: 1 B (0.001 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..0] ctx : ?ztracy.ZoneCtx                                                                                |
//                                                                                                             |
// trace dependency variant                                                                                    |
//   Real ztracy builds use the dependency's ZoneCtx layout inside this optional field. Capture buffers and    |
//   timeline output stay in Tracy/scaffolding code; this facade stores only the returned zone context.        |
const EnabledZone = struct {
    ctx: ?ztracy.ZoneCtx,

    pub inline fn end(self: @This()) void {
        if (self.ctx) |ctx| ctx.End();
    }

    pub inline fn value(self: @This(), val: u64) void {
        if (self.ctx) |ctx| ctx.Value(val);
    }
};
// ------------------------------------------------------------------------------------------------------------|

// DisabledZone -----------------------------------------------------------------------------------------------|
// Zero-state zone handle used by normal product and test builds.                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 0 B; Trace.* call sites keep no zone storage when ztracy is disabled              |
const DisabledZone = struct {
    pub inline fn end(self: @This()) void {
        _ = self;
    }

    pub inline fn value(self: @This(), val: u64) void {
        _ = self;
        _ = val;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub const Zone = zone_type: {
    if (enabled) break :zone_type EnabledZone;
    break :zone_type DisabledZone;
};

pub inline fn staticZone(comptime src: SourceLocation, comptime name: [*:0]const u8) Zone {
    if (!enabled) return .{};
    return .{ .ctx = ztracy.ZoneN(src, name) };
}

pub const deepStaticZone = staticZone;

pub inline fn namedZone(comptime src: SourceLocation, name: []const u8) Zone {
    if (!enabled) return .{};
    const ctx = ztracy.Zone(src);
    ctx.Name(name);
    return .{ .ctx = ctx };
}

pub const deepNamedZone = namedZone;

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
