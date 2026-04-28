const std = @import("std");
const config = @import("config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_file = std.fs.File.stdout();
    const stdout_writer = stdout_file.writer(&.{});
    var stdout_interface = stdout_writer.interface;
    try mainWithArgs(allocator, args, &stdout_interface);
    try stdout_interface.flush();
}

pub fn mainWithArgs(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: anytype,
) !void {
    if (args.len < 2) return error.InvalidArguments;

    if (std.mem.eql(u8, args[1], "run")) {
        if (args.len != 3) return error.InvalidArguments;
        var loaded = try config.loadResolvedCaseFromFile(allocator, args[2]);
        defer loaded.deinit();
        const summary = try config.runResolvedCaseAndWriteOutputs(allocator, &loaded.resolved);
        try stdout.print(
            "scene={s} mean_abs_difference={e:.12} max_abs_difference={e:.12}\n",
            .{
                summary.scene_id,
                summary.comparison.mean_abs_difference,
                summary.comparison.max_abs_difference,
            },
        );
        return;
    }

    if (std.mem.eql(u8, args[1], "config")) {
        if (args.len != 4) return error.InvalidArguments;
        if (std.mem.eql(u8, args[2], "validate")) {
            var loaded = try config.loadResolvedCaseFromFile(allocator, args[3]);
            defer loaded.deinit();
            try stdout.print("validated {s}\n", .{args[3]});
            return;
        }
        if (std.mem.eql(u8, args[2], "resolve")) {
            var loaded = try config.loadResolvedCaseFromFile(allocator, args[3]);
            defer loaded.deinit();
            const rendered = try config.renderResolvedJson(allocator, &loaded.resolved);
            defer allocator.free(rendered);
            try stdout.writeAll(rendered);
            return;
        }
    }

    return error.InvalidArguments;
}
