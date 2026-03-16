const std = @import("std");
const App = @import("cli_app");

fn makeScratchPath(prefix: []const u8, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "zig-cache/cli-integration/{s}-{d}",
        .{ prefix, @as(u64, @intCast(@abs(std.time.nanoTimestamp()))) },
    );
}

test "cli run executes canonical yaml example" {
    var stdout_buffer = std.ArrayList(u8).empty;
    defer stdout_buffer.deinit(std.testing.allocator);
    var stderr_buffer = std.ArrayList(u8).empty;
    defer stderr_buffer.deinit(std.testing.allocator);

    const argv = [_][]const u8{
        "zdisamar",
        "run",
        "data/examples/canonical_config.yaml",
    };

    try App.run(
        std.testing.allocator,
        &argv,
        stdout_buffer.writer(std.testing.allocator),
        stderr_buffer.writer(std.testing.allocator),
    );

    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "zdisamar run:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "stage=simulation"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "cli import emits canonical yaml that validates and resolves" {
    var stdout_buffer = std.ArrayList(u8).empty;
    defer stdout_buffer.deinit(std.testing.allocator);
    var stderr_buffer = std.ArrayList(u8).empty;
    defer stderr_buffer.deinit(std.testing.allocator);

    const import_argv = [_][]const u8{
        "zdisamar",
        "config",
        "import",
        "data/examples/legacy_config.in",
    };

    try App.run(
        std.testing.allocator,
        &import_argv,
        stdout_buffer.writer(std.testing.allocator),
        stderr_buffer.writer(std.testing.allocator),
    );

    try std.testing.expect(std.mem.startsWith(u8, stdout_buffer.items, "# Imported from legacy Config.in subset."));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "warning:"));

    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const scratch_root = try makeScratchPath("imported", &path_buffer);
    defer std.fs.cwd().deleteTree(scratch_root) catch {};
    try std.fs.cwd().makePath(scratch_root);

    const yaml_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/imported.yaml", .{scratch_root});
    defer std.testing.allocator.free(yaml_path);

    {
        const file = try std.fs.cwd().createFile(yaml_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(stdout_buffer.items);
    }

    var validate_stdout = std.ArrayList(u8).empty;
    defer validate_stdout.deinit(std.testing.allocator);
    var validate_stderr = std.ArrayList(u8).empty;
    defer validate_stderr.deinit(std.testing.allocator);

    const validate_argv = [_][]const u8{
        "zdisamar",
        "config",
        "validate",
        yaml_path,
    };

    try App.run(
        std.testing.allocator,
        &validate_argv,
        validate_stdout.writer(std.testing.allocator),
        validate_stderr.writer(std.testing.allocator),
    );

    try std.testing.expect(std.mem.containsAtLeast(u8, validate_stdout.items, 1, "status=valid"));

    var resolve_stdout = std.ArrayList(u8).empty;
    defer resolve_stdout.deinit(std.testing.allocator);
    var resolve_stderr = std.ArrayList(u8).empty;
    defer resolve_stderr.deinit(std.testing.allocator);

    const resolve_argv = [_][]const u8{
        "zdisamar",
        "config",
        "resolve",
        yaml_path,
    };

    try App.run(
        std.testing.allocator,
        &resolve_argv,
        resolve_stdout.writer(std.testing.allocator),
        resolve_stderr.writer(std.testing.allocator),
    );

    try std.testing.expect(std.mem.containsAtLeast(u8, resolve_stdout.items, 1, "stages:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, resolve_stdout.items, 1, "products:"));
}
