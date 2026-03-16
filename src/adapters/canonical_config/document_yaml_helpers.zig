const std = @import("std");
const yaml = @import("yaml.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{
    DuplicateKey,
    InvalidFlowValue,
    InvalidIndentation,
    UnknownField,
    MissingField,
    InvalidType,
    InvalidValue,
    InvalidYaml,
    MissingAsset,
    OutOfMemory,
    UnterminatedFlowCollection,
};

pub fn resolveInputPath(allocator: Allocator, source_dir: []const u8, path: []const u8) Error![]const u8 {
    if (std.fs.path.isAbsolute(path)) {
        const file = std.fs.openFileAbsolute(path, .{}) catch return error.MissingAsset;
        file.close();
        return allocator.dupe(u8, path) catch return error.InvalidValue;
    }

    var current = source_dir;
    while (true) {
        const candidate = std.fs.path.join(allocator, &.{ current, path }) catch return error.InvalidValue;
        if (pathExists(candidate)) return candidate;
        allocator.free(candidate);

        const parent = std.fs.path.dirname(current) orelse break;
        if (std.mem.eql(u8, parent, current)) break;
        current = parent;
    }

    const direct = allocator.dupe(u8, path) catch return error.InvalidValue;
    if (pathExists(direct)) return direct;
    allocator.free(direct);
    return error.MissingAsset;
}

pub fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn cloneMapSkipping(allocator: Allocator, entries: []const yaml.Entry, skipped_keys: []const []const u8) Error!yaml.Value {
    var cloned = std.ArrayListUnmanaged(yaml.Entry){};
    defer cloned.deinit(allocator);
    for (entries) |entry| {
        if (containsString(skipped_keys, entry.key)) continue;
        try cloned.append(allocator, .{
            .key = try allocator.dupe(u8, entry.key),
            .value = try entry.value.clone(allocator),
        });
    }
    return .{ .map = try cloned.toOwnedSlice(allocator) };
}

pub fn ensureKnownFields(entries: []const yaml.Entry, allowed: []const []const u8, strict: bool) Error!void {
    if (!strict) return;
    for (entries) |entry| {
        if (!containsString(allowed, entry.key)) return error.UnknownField;
    }
}

pub fn containsString(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) return true;
    }
    return false;
}

pub fn expectMap(value: yaml.Value) Error![]const yaml.Entry {
    return switch (value) {
        .map => |entries| entries,
        else => error.InvalidType,
    };
}

pub fn expectSeq(value: yaml.Value) Error![]const yaml.Value {
    return switch (value) {
        .seq => |items| items,
        else => error.InvalidType,
    };
}

pub fn expectString(value: yaml.Value) Error![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => error.InvalidType,
    };
}

pub fn expectBool(value: yaml.Value) Error!bool {
    return switch (value) {
        .bool => |boolean| boolean,
        else => error.InvalidType,
    };
}

pub fn expectI64(value: yaml.Value) Error!i64 {
    return switch (value) {
        .integer => |integer| integer,
        else => error.InvalidType,
    };
}

pub fn expectU64(value: yaml.Value) Error!u64 {
    const integer = try expectI64(value);
    if (integer < 0) return error.InvalidValue;
    return @intCast(integer);
}

pub fn expectF64(value: yaml.Value) Error!f64 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float_value| float_value,
        else => error.InvalidType,
    };
}

pub fn requiredField(entries: []const yaml.Entry, key: []const u8) yaml.Value {
    return mapGet(entries, key) orelse .null;
}

pub fn mapGet(entries: []const yaml.Entry, key: []const u8) ?yaml.Value {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.key, key)) return entry.value;
    }
    return null;
}
