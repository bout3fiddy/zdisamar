const std = @import("std");
const parser = @import("o2a_parity_parser.zig");

const Allocator = std.mem.Allocator;

pub const Node = parser.Node;
pub const MapEntry = parser.MapEntry;

pub fn mergeOptionalNodes(allocator: Allocator, base: ?Node, override: ?Node) !?Node {
    if (base == null) return override;
    if (override == null) return base;
    return try mergeNodes(allocator, base.?, override.?);
}

pub fn mergeNodes(allocator: Allocator, base: Node, override: Node) !Node {
    return switch (base) {
        .map => |base_map| switch (override) {
            .map => |override_map| blk: {
                var merged = std.ArrayList(MapEntry).empty;
                errdefer merged.deinit(allocator);

                for (base_map) |entry| {
                    if (findField(override_map, entry.key)) |override_entry| {
                        try merged.append(allocator, .{
                            .key = entry.key,
                            .value = try mergeNodes(allocator, entry.value, override_entry.value),
                            .line = override_entry.line,
                        });
                    } else {
                        try merged.append(allocator, entry);
                    }
                }
                for (override_map) |entry| {
                    if (findField(base_map, entry.key) == null) try merged.append(allocator, entry);
                }
                break :blk Node{ .map = try merged.toOwnedSlice(allocator) };
            },
            else => override,
        },
        else => override,
    };
}

pub fn expectMap(node: Node) ![]const MapEntry {
    return switch (node) {
        .map => |value| value,
        else => error.ExpectedMap,
    };
}

pub fn expectSeq(node: Node) ![]const Node {
    return switch (node) {
        .seq => |value| value,
        else => error.ExpectedSequence,
    };
}

pub fn parseString(node: Node) ![]const u8 {
    return switch (node) {
        .scalar => |raw| unquoteScalar(raw),
        else => error.ExpectedScalar,
    };
}

pub fn parseBool(node: Node) !bool {
    const text = try parseString(node);
    if (std.mem.eql(u8, text, "true")) return true;
    if (std.mem.eql(u8, text, "false")) return false;
    return error.InvalidBoolean;
}

pub fn parseF64(node: Node) !f64 {
    return std.fmt.parseFloat(f64, try parseString(node));
}

pub fn parseU32(node: Node) !u32 {
    return std.fmt.parseInt(u32, try parseString(node), 10);
}

pub fn parseU16(node: Node) !u16 {
    return std.fmt.parseInt(u16, try parseString(node), 10);
}

pub fn parseU8(node: Node) !u8 {
    return std.fmt.parseInt(u8, try parseString(node), 10);
}

pub fn parseInlineU8List(allocator: Allocator, text: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, text, " ");
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') return error.InvalidInlineList;
    const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " ");
    if (inner.len == 0) return &.{};
    var items = std.ArrayList(u8).empty;
    errdefer items.deinit(allocator);

    var iter = std.mem.splitScalar(u8, inner, ',');
    while (iter.next()) |part| {
        const value = try std.fmt.parseInt(u8, std.mem.trim(u8, part, " "), 10);
        try items.append(allocator, value);
    }
    return try items.toOwnedSlice(allocator);
}

pub fn requiredField(map: []const MapEntry, key: []const u8) !Node {
    return (try findRequiredField(map, key)).value;
}

pub fn optionalField(map: []const MapEntry, key: []const u8) !?Node {
    if (findField(map, key)) |entry| return entry.value;
    return null;
}

pub fn requiredString(map: []const MapEntry, key: []const u8) ![]const u8 {
    return parseString(try requiredField(map, key));
}

pub fn optionalString(map: []const MapEntry, key: []const u8) !?[]const u8 {
    if (try optionalField(map, key)) |node| return try parseString(node);
    return null;
}

pub fn requiredBool(map: []const MapEntry, key: []const u8) !bool {
    return parseBool(try requiredField(map, key));
}

pub fn optionalBool(map: []const MapEntry, key: []const u8) !?bool {
    if (try optionalField(map, key)) |node| return try parseBool(node);
    return null;
}

pub fn requiredF64(map: []const MapEntry, key: []const u8) !f64 {
    return parseF64(try requiredField(map, key));
}

pub fn optionalF64(map: []const MapEntry, key: []const u8) !?f64 {
    if (try optionalField(map, key)) |node| return try parseF64(node);
    return null;
}

pub fn requiredU32(map: []const MapEntry, key: []const u8) !u32 {
    return parseU32(try requiredField(map, key));
}

pub fn requiredU16(map: []const MapEntry, key: []const u8) !u16 {
    return parseU16(try requiredField(map, key));
}

pub fn requiredU8(map: []const MapEntry, key: []const u8) !u8 {
    return parseU8(try requiredField(map, key));
}

pub fn expectOnlyFields(map: []const MapEntry, allowed_keys: []const []const u8) !void {
    for (map) |entry| {
        var allowed = false;
        for (allowed_keys) |allowed_key| {
            if (std.mem.eql(u8, entry.key, allowed_key)) {
                allowed = true;
                break;
            }
        }
        if (!allowed) return error.UnsupportedField;
    }
}

pub fn findField(map: []const MapEntry, key: []const u8) ?MapEntry {
    var found: ?MapEntry = null;
    for (map) |entry| {
        if (!std.mem.eql(u8, entry.key, key)) continue;
        if (found != null) return null;
        found = entry;
    }
    return found;
}

pub fn findRequiredField(map: []const MapEntry, key: []const u8) !MapEntry {
    var found: ?MapEntry = null;
    for (map) |entry| {
        if (!std.mem.eql(u8, entry.key, key)) continue;
        if (found != null) return error.DuplicateField;
        found = entry;
    }
    return found orelse error.MissingRequiredField;
}

fn unquoteScalar(text: []const u8) []const u8 {
    if (text.len >= 2 and ((text[0] == '"' and text[text.len - 1] == '"') or (text[0] == '\'' and text[text.len - 1] == '\''))) {
        return text[1 .. text.len - 1];
    }
    return text;
}
