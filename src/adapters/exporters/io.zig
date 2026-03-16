const std = @import("std");

pub const Error = error{
    UnsupportedDestinationScheme,
    InvalidDestinationUri,
};

pub fn filePathFromUri(destination_uri: []const u8) Error![]const u8 {
    const file_prefix = "file://";
    if (!std.mem.startsWith(u8, destination_uri, file_prefix)) {
        return Error.UnsupportedDestinationScheme;
    }

    const path = destination_uri[file_prefix.len..];
    if (path.len == 0) {
        return Error.InvalidDestinationUri;
    }
    return path;
}

pub fn ensureParentDirectory(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0) return;
    try std.fs.cwd().makePath(parent);
}

pub fn writeTextFile(path: []const u8, payload: []const u8) !usize {
    try ensureParentDirectory(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(payload);
    return payload.len;
}

pub fn writeBinaryFile(path: []const u8, payload: []const u8) !usize {
    try ensureParentDirectory(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(payload);
    return payload.len;
}

test "file uri parsing requires explicit file scheme" {
    try std.testing.expectEqualStrings("out/result.nc", try filePathFromUri("file://out/result.nc"));
    try std.testing.expectError(Error.UnsupportedDestinationScheme, filePathFromUri("s3://bucket/result.nc"));
    try std.testing.expectError(Error.InvalidDestinationUri, filePathFromUri("file://"));
}
