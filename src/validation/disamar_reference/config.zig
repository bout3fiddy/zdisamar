const std = @import("std");
const parser = @import("parser.zig");
const scene = @import("scene.zig");
const output = @import("output.zig");
const reference_run = @import("run.zig");

const Allocator = std.mem.Allocator;

pub const RunSummary = output.RunSummary;

pub const LoadedResolvedCase = struct {
    arena: std.heap.ArenaAllocator,
    root: parser.Node,
    resolved: reference_run.ResolvedVendorO2ACase,

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
    resolved: *const reference_run.ResolvedVendorO2ACase,
) ![]u8 {
    return output.renderResolvedJson(allocator, resolved);
}

pub fn runResolvedCaseAndWriteOutputs(
    allocator: Allocator,
    resolved: *const reference_run.ResolvedVendorO2ACase,
) !RunSummary {
    return output.runResolvedCaseAndWriteOutputs(allocator, resolved);
}
