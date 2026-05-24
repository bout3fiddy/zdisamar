const std = @import("std");

const Src = std.builtin.SourceLocation;

// instrumentation: ztracy stub
// captures: nothing
// why: satisfy trace imports with zero runtime work in product builds.
pub const enabled = false;

// layout(64-bit):
//   size: 0 B, align: 1 B
//   field storage: 0 B; padding: 0 B (0 bits)
//   footprint: no runtime field storage; namespace/type declarations only
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

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: child_allocator=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const TracyAllocator = struct {
    child_allocator: std.mem.Allocator,

    pub fn init(child_allocator: std.mem.Allocator) TracyAllocator {
        return .{ .child_allocator = child_allocator };
    }

    pub fn allocator(self: *TracyAllocator) std.mem.Allocator {
        return self.child_allocator;
    }
};
