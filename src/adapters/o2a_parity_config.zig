const std = @import("std");
const parser = @import("o2a_parity_parser.zig");
const scene = @import("o2a_parity_scene.zig");
const output = @import("o2a_parity_output.zig");
const parity_runtime = @import("../o2a/data/vendor_parity_runtime.zig");

const Allocator = std.mem.Allocator;

pub const RunSummary = output.RunSummary;

pub const LoadedResolvedCase = struct {
    arena: std.heap.ArenaAllocator,
    root: parser.Node,
    resolved: parity_runtime.ResolvedVendorO2ACase,

    pub fn deinit(self: *LoadedResolvedCase) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn loadResolvedCaseFromFile(
    allocator: Allocator,
    path: []const u8,
) !LoadedResolvedCase {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();

    const bytes = try std.fs.cwd().readFileAlloc(arena_allocator, path, 512 * 1024);
    const root = try parser.parseDocument(arena_allocator, bytes);
    const resolved = try scene.compileResolvedCase(arena_allocator, root);
    return .{
        .arena = arena,
        .root = root,
        .resolved = resolved,
    };
}

pub fn renderResolvedJson(
    allocator: Allocator,
    resolved: *const parity_runtime.ResolvedVendorO2ACase,
) ![]u8 {
    return output.renderResolvedJson(allocator, resolved);
}

pub fn runResolvedCaseAndWriteOutputs(
    allocator: Allocator,
    resolved: *const parity_runtime.ResolvedVendorO2ACase,
) !RunSummary {
    return output.runResolvedCaseAndWriteOutputs(allocator, resolved);
}
