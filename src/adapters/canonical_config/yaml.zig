//! Purpose:
//!   Parse and merge the small YAML dialect used by canonical configuration
//!   files.
//!
//! Physics:
//!   This parser is purely structural; it resolves mappings, sequences, and
//!   scalars so higher-level adapter code can build typed plan and scene
//!   records.
//!
//! Vendor:
//!   Canonical YAML parsing and merge behavior.
//!
//! Design:
//!   Keep the parser compact and allocation-aware so document resolution can
//!   clone or overlay configuration trees deterministically.
//!
//! Invariants:
//!   Duplicate keys and malformed indentation remain hard parse errors.
//!
//! Validation:
//!   YAML parser tests cover parsing, merging, and indentation failure cases.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ParseError = error{
    OutOfMemory,
    DuplicateKey,
    InvalidIndentation,
    InvalidYaml,
    InvalidFlowValue,
    UnterminatedFlowCollection,
};

pub const Entry = struct {
    key: []const u8,
    value: Value,
};

pub const Value = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    map: []const Entry,
    seq: []const Value,

    /// Purpose:
    ///   Return a human-readable type name for the active YAML variant.
    pub fn kindName(self: Value) []const u8 {
        return switch (self) {
            .null => "null",
            .bool => "bool",
            .integer => "integer",
            .float => "float",
            .string => "string",
            .map => "map",
            .seq => "sequence",
        };
    }

    /// Purpose:
    ///   Look up a mapping entry by key.
    pub fn get(self: Value, key: []const u8) ?Value {
        return switch (self) {
            .map => |entries| for (entries) |entry| {
                if (std.mem.eql(u8, entry.key, key)) break entry.value;
            } else null,
            else => null,
        };
    }

    /// Purpose:
    ///   Deep-clone the YAML value into caller-owned storage.
    pub fn clone(self: Value, allocator: Allocator) ParseError!Value {
        return switch (self) {
            .null => .null,
            .bool => |value| .{ .bool = value },
            .integer => |value| .{ .integer = value },
            .float => |value| .{ .float = value },
            .string => |value| .{ .string = try allocator.dupe(u8, value) },
            .seq => |items| blk: {
                const cloned = try allocator.alloc(Value, items.len);
                for (items, 0..) |item, index| {
                    cloned[index] = try item.clone(allocator);
                }
                break :blk .{ .seq = cloned };
            },
            .map => |entries| blk: {
                const cloned = try allocator.alloc(Entry, entries.len);
                for (entries, 0..) |entry, index| {
                    cloned[index] = .{
                        .key = try allocator.dupe(u8, entry.key),
                        .value = try entry.value.clone(allocator),
                    };
                }
                break :blk .{ .map = cloned };
            },
        };
    }

    /// Purpose:
    ///   Compare two YAML values structurally.
    pub fn eql(lhs: Value, rhs: Value) bool {
        if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;

        return switch (lhs) {
            .null => true,
            .bool => |value| value == rhs.bool,
            .integer => |value| value == rhs.integer,
            .float => |value| value == rhs.float,
            .string => |value| std.mem.eql(u8, value, rhs.string),
            .seq => |items| blk: {
                const other = rhs.seq;
                if (items.len != other.len) break :blk false;
                for (items, other) |item, other_item| {
                    if (!item.eql(other_item)) break :blk false;
                }
                break :blk true;
            },
            .map => |entries| blk: {
                const other = rhs.map;
                if (entries.len != other.len) break :blk false;
                for (entries, other) |entry, other_entry| {
                    if (!std.mem.eql(u8, entry.key, other_entry.key)) break :blk false;
                    if (!entry.value.eql(other_entry.value)) break :blk false;
                }
                break :blk true;
            },
        };
    }
};

/// Purpose:
///   Merge an overlay YAML tree onto a base YAML tree.
pub fn merge(base: Value, overlay: Value, allocator: Allocator) ParseError!Value {
    if (base == .map and overlay == .map) {
        return mergeMaps(base.map, overlay.map, allocator);
    }
    return overlay.clone(allocator);
}

/// Purpose:
///   Parse the canonical YAML dialect into a typed tree of YAML values.
pub fn parse(allocator: Allocator, source: []const u8) ParseError!Value {
    var lines = std.ArrayListUnmanaged(RawLine){};
    defer lines.deinit(allocator);

    var iterator = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 1;
    while (iterator.next()) |raw_line| : (line_number += 1) {
        try lines.append(allocator, .{
            .number = line_number,
            .text = std.mem.trimRight(u8, raw_line, "\r"),
        });
    }

    var parser = Parser{
        .allocator = allocator,
        .lines = lines.items,
    };
    const root = try parser.parseDocument();
    parser.skipIgnorable();
    if (parser.index != parser.lines.len) {
        return ParseError.InvalidYaml;
    }
    return root;
}

fn mergeMaps(base: []const Entry, overlay: []const Entry, allocator: Allocator) ParseError!Value {
    var merged = std.ArrayListUnmanaged(Entry){};
    defer merged.deinit(allocator);

    for (base) |entry| {
        try merged.append(allocator, .{
            .key = try allocator.dupe(u8, entry.key),
            .value = try entry.value.clone(allocator),
        });
    }

    for (overlay) |entry| {
        if (findEntryIndex(merged.items, entry.key)) |index| {
            merged.items[index].value = try merge(merged.items[index].value, entry.value, allocator);
        } else {
            try merged.append(allocator, .{
                .key = try allocator.dupe(u8, entry.key),
                .value = try entry.value.clone(allocator),
            });
        }
    }

    return .{ .map = try merged.toOwnedSlice(allocator) };
}

fn findEntryIndex(entries: []const Entry, key: []const u8) ?usize {
    for (entries, 0..) |entry, index| {
        if (std.mem.eql(u8, entry.key, key)) return index;
    }
    return null;
}

const RawLine = struct {
    number: usize,
    text: []const u8,
};

const Parser = struct {
    allocator: Allocator,
    lines: []const RawLine,
    index: usize = 0,

    fn parseDocument(self: *Parser) ParseError!Value {
        self.skipIgnorable();
        const next = self.peekSignificant() orelse return .{ .map = &[_]Entry{} };
        return self.parseBlock(next.indent);
    }

    fn parseBlock(self: *Parser, indent: usize) ParseError!Value {
        const next = self.peekSignificant() orelse return ParseError.InvalidYaml;
        if (next.indent != indent) return ParseError.InvalidIndentation;

        if (isSequenceLine(next.content)) {
            return self.parseSequence(indent);
        }
        return self.parseMapping(indent);
    }

    fn parseMapping(self: *Parser, indent: usize) ParseError!Value {
        var entries = std.ArrayListUnmanaged(Entry){};
        defer entries.deinit(self.allocator);

        while (true) {
            self.skipIgnorable();
            const next = self.peekSignificant() orelse break;
            if (next.indent < indent) break;
            if (next.indent != indent) return ParseError.InvalidIndentation;
            if (isSequenceLine(next.content)) return ParseError.InvalidYaml;

            self.index += 1;
            try self.parseMappingEntry(indent, next.content, &entries);
        }

        return .{ .map = try entries.toOwnedSlice(self.allocator) };
    }

    fn parseSequence(self: *Parser, indent: usize) ParseError!Value {
        var items = std.ArrayListUnmanaged(Value){};
        defer items.deinit(self.allocator);

        while (true) {
            self.skipIgnorable();
            const next = self.peekSignificant() orelse break;
            if (next.indent < indent) break;
            if (next.indent != indent) return ParseError.InvalidIndentation;
            if (!isSequenceLine(next.content)) return ParseError.InvalidYaml;

            self.index += 1;
            const tail = std.mem.trimLeft(u8, next.content[1..], " ");
            const value = if (tail.len == 0)
                try self.parseNestedOrNull(indent)
            else if (std.mem.eql(u8, tail, ">"))
                try self.consumeFoldedBlock(indent)
            else if (looksLikeMappingEntry(tail))
                try self.parseInlineMapping(indent + 2, tail)
            else
                try self.parseInlineValue(tail);

            try items.append(self.allocator, value);
        }

        return .{ .seq = try items.toOwnedSlice(self.allocator) };
    }

    fn parseInlineMapping(self: *Parser, indent: usize, first_entry: []const u8) ParseError!Value {
        var entries = std.ArrayListUnmanaged(Entry){};
        defer entries.deinit(self.allocator);

        try self.parseMappingEntry(indent, first_entry, &entries);

        while (true) {
            self.skipIgnorable();
            const next = self.peekSignificant() orelse break;
            if (next.indent < indent) break;
            if (next.indent != indent) return ParseError.InvalidIndentation;
            if (isSequenceLine(next.content)) break;

            self.index += 1;
            try self.parseMappingEntry(indent, next.content, &entries);
        }

        return .{ .map = try entries.toOwnedSlice(self.allocator) };
    }

    fn parseMappingEntry(
        self: *Parser,
        indent: usize,
        content: []const u8,
        entries: *std.ArrayListUnmanaged(Entry),
    ) ParseError!void {
        const delimiter = findMappingDelimiter(content) orelse return ParseError.InvalidYaml;
        const key = std.mem.trim(u8, content[0..delimiter], " ");
        if (key.len == 0) return ParseError.InvalidYaml;
        if (findEntryIndex(entries.items, key) != null) return ParseError.DuplicateKey;

        const remainder = std.mem.trimLeft(u8, content[delimiter + 1 ..], " ");
        const owned_key = try self.allocator.dupe(u8, key);
        const value = if (remainder.len == 0)
            try self.parseNestedOrNull(indent)
        else if (std.mem.eql(u8, remainder, ">"))
            try self.consumeFoldedBlock(indent)
        else
            try self.parseInlineValue(remainder);

        try entries.append(self.allocator, .{
            .key = owned_key,
            .value = value,
        });
    }

    fn parseNestedOrNull(self: *Parser, parent_indent: usize) ParseError!Value {
        const next = self.peekSignificant() orelse return .null;
        if (next.indent <= parent_indent) return .null;
        return self.parseBlock(next.indent);
    }

    fn consumeFoldedBlock(self: *Parser, parent_indent: usize) ParseError!Value {
        var lines = std.ArrayListUnmanaged(RawLine){};
        defer lines.deinit(self.allocator);

        var minimum_indent: ?usize = null;
        while (self.index < self.lines.len) {
            const raw = self.lines[self.index];
            if (isBlank(raw.text)) {
                try lines.append(self.allocator, raw);
                self.index += 1;
                continue;
            }

            const indent = try countIndent(raw.text);
            if (indent <= parent_indent) break;
            minimum_indent = if (minimum_indent) |current| @min(current, indent) else indent;
            try lines.append(self.allocator, raw);
            self.index += 1;
        }

        const content_indent = minimum_indent orelse return .{ .string = try self.allocator.dupe(u8, "") };

        var builder = std.ArrayListUnmanaged(u8){};
        defer builder.deinit(self.allocator);

        var previous_blank = false;
        var wrote_any = false;
        for (lines.items) |raw| {
            if (isBlank(raw.text)) {
                previous_blank = true;
                continue;
            }

            const trimmed = raw.text[content_indent..];
            if (wrote_any) {
                if (previous_blank) {
                    try builder.append(self.allocator, '\n');
                } else {
                    try builder.append(self.allocator, ' ');
                }
            }

            try builder.appendSlice(self.allocator, trimmed);
            wrote_any = true;
            previous_blank = false;
        }

        return .{ .string = try builder.toOwnedSlice(self.allocator) };
    }

    fn parseInlineValue(self: *Parser, text: []const u8) ParseError!Value {
        const trimmed = std.mem.trim(u8, text, " ");
        if (trimmed.len == 0) return .null;
        if (std.mem.eql(u8, trimmed, "null")) return .null;
        if (std.mem.eql(u8, trimmed, "true")) return .{ .bool = true };
        if (std.mem.eql(u8, trimmed, "false")) return .{ .bool = false };
        if (std.mem.eql(u8, trimmed, "[]")) return .{ .seq = &[_]Value{} };
        if (std.mem.eql(u8, trimmed, "{}")) return .{ .map = &[_]Entry{} };
        if (trimmed[0] == '[') return parseFlowSequence(self.allocator, trimmed);
        if (trimmed[0] == '{') return parseFlowMap(self.allocator, trimmed);

        if (isQuoted(trimmed)) {
            return .{ .string = try self.allocator.dupe(u8, trimmed[1 .. trimmed.len - 1]) };
        }

        if (parseInteger(trimmed)) |integer_value| {
            return .{ .integer = integer_value };
        }
        if (parseFloat(trimmed)) |float_value| {
            return .{ .float = float_value };
        }

        return .{ .string = try self.allocator.dupe(u8, trimmed) };
    }

    fn skipIgnorable(self: *Parser) void {
        while (self.index < self.lines.len) : (self.index += 1) {
            const text = self.lines[self.index].text;
            if (!isIgnorable(text)) break;
        }
    }

    fn peekSignificant(self: *Parser) ?struct {
        indent: usize,
        content: []const u8,
    } {
        var cursor = self.index;
        while (cursor < self.lines.len) : (cursor += 1) {
            const text = self.lines[cursor].text;
            if (isIgnorable(text)) continue;

            const indent = countIndent(text) catch return null;
            return .{
                .indent = indent,
                .content = text[indent..],
            };
        }
        return null;
    }
};

fn parseFlowSequence(allocator: Allocator, text: []const u8) ParseError!Value {
    if (text.len < 2 or text[text.len - 1] != ']') return ParseError.UnterminatedFlowCollection;

    const inner = std.mem.trim(u8, text[1 .. text.len - 1], " ");
    if (inner.len == 0) return .{ .seq = &[_]Value{} };

    var items = std.ArrayListUnmanaged(Value){};
    defer items.deinit(allocator);

    var last: usize = 0;
    var depth_square: usize = 0;
    var depth_brace: usize = 0;
    var quote: u8 = 0;
    for (inner, 0..) |char, index| {
        if (quote != 0) {
            if (char == quote) quote = 0;
            continue;
        }

        switch (char) {
            '\'', '"' => quote = char,
            '[' => depth_square += 1,
            ']' => {
                if (depth_square == 0) return ParseError.InvalidFlowValue;
                depth_square -= 1;
            },
            '{' => depth_brace += 1,
            '}' => {
                if (depth_brace == 0) return ParseError.InvalidFlowValue;
                depth_brace -= 1;
            },
            ',' => {
                if (depth_square == 0 and depth_brace == 0) {
                    try items.append(allocator, try parseInlineFragment(allocator, inner[last..index]));
                    last = index + 1;
                }
            },
            else => {},
        }
    }

    if (quote != 0 or depth_square != 0 or depth_brace != 0) return ParseError.UnterminatedFlowCollection;
    try items.append(allocator, try parseInlineFragment(allocator, inner[last..]));

    return .{ .seq = try items.toOwnedSlice(allocator) };
}

fn parseFlowMap(allocator: Allocator, text: []const u8) ParseError!Value {
    if (text.len < 2 or text[text.len - 1] != '}') return ParseError.UnterminatedFlowCollection;

    const inner = std.mem.trim(u8, text[1 .. text.len - 1], " ");
    if (inner.len == 0) return .{ .map = &[_]Entry{} };

    var entries = std.ArrayListUnmanaged(Entry){};
    defer entries.deinit(allocator);

    var last: usize = 0;
    var depth_square: usize = 0;
    var depth_brace: usize = 0;
    var quote: u8 = 0;
    for (inner, 0..) |char, index| {
        if (quote != 0) {
            if (char == quote) quote = 0;
            continue;
        }

        switch (char) {
            '\'', '"' => quote = char,
            '[' => depth_square += 1,
            ']' => {
                if (depth_square == 0) return ParseError.InvalidFlowValue;
                depth_square -= 1;
            },
            '{' => depth_brace += 1,
            '}' => {
                if (depth_brace == 0) return ParseError.InvalidFlowValue;
                depth_brace -= 1;
            },
            ',' => {
                if (depth_square == 0 and depth_brace == 0) {
                    try appendFlowMapEntry(allocator, &entries, inner[last..index]);
                    last = index + 1;
                }
            },
            else => {},
        }
    }

    if (quote != 0 or depth_square != 0 or depth_brace != 0) return ParseError.UnterminatedFlowCollection;
    try appendFlowMapEntry(allocator, &entries, inner[last..]);

    return .{ .map = try entries.toOwnedSlice(allocator) };
}

fn appendFlowMapEntry(
    allocator: Allocator,
    entries: *std.ArrayListUnmanaged(Entry),
    fragment: []const u8,
) ParseError!void {
    const trimmed = std.mem.trim(u8, fragment, " ");
    const delimiter = findMappingDelimiter(trimmed) orelse return ParseError.InvalidFlowValue;
    const key = std.mem.trim(u8, trimmed[0..delimiter], " ");
    if (key.len == 0) return ParseError.InvalidFlowValue;
    if (findEntryIndex(entries.items, key) != null) return ParseError.DuplicateKey;

    try entries.append(allocator, .{
        .key = try allocator.dupe(u8, key),
        .value = try parseInlineFragment(allocator, trimmed[delimiter + 1 ..]),
    });
}

fn parseInlineFragment(allocator: Allocator, fragment: []const u8) ParseError!Value {
    var parser = Parser{
        .allocator = allocator,
        .lines = &[_]RawLine{},
    };
    return parser.parseInlineValue(fragment);
}

fn countIndent(text: []const u8) ParseError!usize {
    var indent: usize = 0;
    while (indent < text.len) : (indent += 1) {
        if (text[indent] == ' ') continue;
        if (text[indent] == '\t') return ParseError.InvalidIndentation;
        break;
    }
    return indent;
}

fn isBlank(text: []const u8) bool {
    return std.mem.trim(u8, text, " ").len == 0;
}

fn isIgnorable(text: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, text, " ");
    return trimmed.len == 0 or trimmed[0] == '#';
}

fn isSequenceLine(content: []const u8) bool {
    return content.len != 0 and content[0] == '-' and (content.len == 1 or content[1] == ' ');
}

fn isQuoted(text: []const u8) bool {
    return text.len >= 2 and ((text[0] == '"' and text[text.len - 1] == '"') or (text[0] == '\'' and text[text.len - 1] == '\''));
}

fn looksLikeMappingEntry(text: []const u8) bool {
    return findMappingDelimiter(text) != null;
}

fn findMappingDelimiter(text: []const u8) ?usize {
    var depth_square: usize = 0;
    var depth_brace: usize = 0;
    var quote: u8 = 0;

    for (text, 0..) |char, index| {
        if (quote != 0) {
            if (char == quote) quote = 0;
            continue;
        }

        switch (char) {
            '\'', '"' => quote = char,
            '[' => depth_square += 1,
            ']' => {
                if (depth_square > 0) depth_square -= 1;
            },
            '{' => depth_brace += 1,
            '}' => {
                if (depth_brace > 0) depth_brace -= 1;
            },
            ':' => {
                if (depth_square == 0 and depth_brace == 0 and (index + 1 == text.len or text[index + 1] == ' ')) {
                    return index;
                }
            },
            else => {},
        }
    }

    return null;
}

fn parseInteger(text: []const u8) ?i64 {
    if (std.mem.indexOfAny(u8, text, ".eE")) |_| return null;
    return std.fmt.parseInt(i64, text, 10) catch null;
}

fn parseFloat(text: []const u8) ?f64 {
    if (!std.mem.containsAtLeast(u8, text, 1, ".") and
        !std.mem.containsAtLeast(u8, text, 1, "e") and
        !std.mem.containsAtLeast(u8, text, 1, "E"))
    {
        return null;
    }
    return std.fmt.parseFloat(f64, text) catch null;
}

test "yaml parser handles canonical subset with templates and flow collections" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  description: >
        \\    synthetic retrieval
        \\    example
        \\outputs:
        \\  - from: truth_radiance
        \\    destination_uri: file://out/demo.nc
        \\bands:
        \\  o2a:
        \\    exclude:
        \\      - [759.35, 759.55]
        \\      - [770.50, 770.80]
    ;

    const value = try parse(std.testing.allocator, source);
    const metadata = value.get("metadata").?;
    try std.testing.expectEqualStrings("synthetic retrieval example", metadata.get("description").?.string);
    const outputs = value.get("outputs").?.seq;
    try std.testing.expectEqual(@as(usize, 1), outputs.len);
    try std.testing.expectEqualStrings("truth_radiance", outputs[0].get("from").?.string);
    const exclude = value.get("bands").?.get("o2a").?.get("exclude").?.seq;
    try std.testing.expectEqual(@as(usize, 2), exclude.len);
    try std.testing.expectEqual(@as(f64, 759.35), exclude[0].seq[0].float);
}

test "yaml merge deep merges maps and replaces sequences" {
    const base = try parse(std.testing.allocator,
        \\scene:
        \\  bands:
        \\    o2a:
        \\      exclude:
        \\        - [1.0, 2.0]
        \\  surface:
        \\    model: lambertian
    );
    const overlay = try parse(std.testing.allocator,
        \\scene:
        \\  bands:
        \\    o2a:
        \\      exclude:
        \\        - [3.0, 4.0]
        \\  surface:
        \\    albedo: 0.04
    );
    const merged = try merge(base, overlay, std.testing.allocator);

    try std.testing.expectEqualStrings("lambertian", merged.get("scene").?.get("surface").?.get("model").?.string);
    try std.testing.expectEqual(@as(f64, 0.04), merged.get("scene").?.get("surface").?.get("albedo").?.float);
    const exclude = merged.get("scene").?.get("bands").?.get("o2a").?.get("exclude").?.seq;
    try std.testing.expectEqual(@as(usize, 1), exclude.len);
    try std.testing.expectEqual(@as(f64, 3.0), exclude[0].seq[0].float);
}
