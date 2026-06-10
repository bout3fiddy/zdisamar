const std = @import("std");

const Src = std.builtin.SourceLocation;

// ztracy.zig -------------------------------------------------------------------------------------------------|
// Disabled Tracy-compatible shim selected when builds do not link the real ztracy dependency.                 |
//                                                                                                             |
// called by                                                                                                   |
//   trace.zig imports this module through the build.zig module alias when enable_ztracy is false. Product,    |
//   tests, telemetry, and perturbation targets use this shim; trace CLIs swap in the real dependency only     |
//   when requested.                                                                                           |
//                                                                                                             |
// mirrored API                                                                                                |
//   The real dependency exposes ZoneCtx, zone creation, messages, frame marks, plots, thread names, and a     |
//   TracyAllocator wrapper. This file keeps the same surface that trace.zig needs without exposing Tracy to   |
//   normal builds.                                                                                            |
//                                                                                                             |
// disabled path                                                                                               |
//   enabled=false tells callers that no timeline is being captured. Zone creation returns an empty context,   |
//   markers and plots discard their inputs, and TracyAllocator hands back the child allocator unchanged.      |
//                                                                                                             |
// hot path                                                                                                    |
//   RTM preparation, wavelength sampling, LABOS, OE, and trace scaffolding can keep Trace.* calls around      |
//   expensive phases. Disabled builds do not allocate zones, emit messages, touch counters, or link Tracy.    |
//                                                                                                             |
// memory                                                                                                      |
//   ZoneCtx is zero-size. TracyAllocator stores only the borrowed child allocator handle; it does not wrap    |
//   allocations with tracing metadata in this variant.                                                        |
// ------------------------------------------------------------------------------------------------------------|
pub const enabled = false;

// ZoneCtx ----------------------------------------------------------------------------------------------------|
// Empty zone context returned by the disabled Tracy shim.                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 0 B; Trace.DisabledZone and direct shim users keep no zone storage                |
pub const ZoneCtx = struct {
    pub inline fn Text(self: ZoneCtx, text: []const u8) void {
        _ = self;
        _ = text;
    }

    pub inline fn Name(self: ZoneCtx, name: []const u8) void {
        _ = self;
        _ = name;
    }

    pub inline fn Value(self: ZoneCtx, value: u64) void {
        _ = self;
        _ = value;
    }

    pub inline fn End(self: ZoneCtx) void {
        _ = self;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub inline fn SetThreadName(name: [*:0]const u8) void {
    _ = name;
}

pub inline fn Zone(comptime src: Src) ZoneCtx {
    _ = src;
    return .{};
}

pub inline fn ZoneN(comptime src: Src, name: [*:0]const u8) ZoneCtx {
    _ = src;
    _ = name;
    return .{};
}

pub inline fn Message(text: []const u8) void {
    _ = text;
}

pub inline fn FrameMark() void {}

pub inline fn PlotU(name: [*:0]const u8, value: u64) void {
    _ = name;
    _ = value;
}

pub inline fn PlotF(name: [*:0]const u8, value: f64) void {
    _ = name;
    _ = value;
}

// TracyAllocator ---------------------------------------------------------------------------------------------|
// Pass-through allocator shim for code that expects the real TracyAllocator type.                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] child_allocator : std.mem.Allocator                                                                |
//                                                                                                             |
// referenced storage                                                                                          |
//   child_allocator is borrowed; this shim does not own allocator state or tracing buffers.                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = one borrowed allocator handle if a caller stores it     |
pub const TracyAllocator = struct {
    child_allocator: std.mem.Allocator,

    pub fn init(child_allocator: std.mem.Allocator) TracyAllocator {
        return .{ .child_allocator = child_allocator };
    }

    pub fn allocator(self: *TracyAllocator) std.mem.Allocator {
        return self.child_allocator;
    }
};
// ------------------------------------------------------------------------------------------------------------|
