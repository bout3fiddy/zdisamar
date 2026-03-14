const std = @import("std");
const App = @import("App.zig");

pub fn main() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    try App.run(std.heap.page_allocator, args, stdout);
}
