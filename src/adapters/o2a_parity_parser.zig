const std = @import("std");

pub const Node = union(enum) {
    map: []MapEntry,
    seq: []Node,
    scalar: []const u8,
};

pub const MapEntry = struct {
    key: []const u8,
    value: Node,
    line: usize,
};

const Line = struct {
    number: usize,
    indent: usize,
    text: []const u8,
};

const KeyValueSplit = struct {
    key: []const u8,
    value: ?[]const u8,
};

const Parser = struct {
    allocator: std.mem.Allocator,
    lines: []const Line,
    index: usize = 0,

    fn parse(self: *Parser) anyerror!Node {
        return self.parseBlock(0);
    }

    fn parseBlock(self: *Parser, indent: usize) anyerror!Node {
        if (self.index >= self.lines.len) return error.UnexpectedEndOfYaml;
        const line = self.lines[self.index];
        if (line.indent < indent) return error.InvalidYamlIndentation;
        if (line.indent > indent) return error.InvalidYamlIndentation;
        if (isSequenceLine(line.text)) return self.parseSequence(indent);
        return self.parseMap(indent);
    }

    fn parseMap(self: *Parser, indent: usize) anyerror!Node {
        var entries = std.ArrayList(MapEntry).empty;
        errdefer entries.deinit(self.allocator);

        while (self.index < self.lines.len) {
            const line = self.lines[self.index];
            if (line.indent < indent) break;
            if (line.indent > indent) return error.InvalidYamlIndentation;
            if (isSequenceLine(line.text)) break;

            const split = splitKeyValue(line.text) orelse return error.InvalidYamlSyntax;
            self.index += 1;
            const value = if (split.value) |inline_value|
                Node{ .scalar = inline_value }
            else if (self.index < self.lines.len and self.lines[self.index].indent > indent)
                try self.parseBlock(indent + 2)
            else
                Node{ .scalar = "" };

            try entries.append(self.allocator, .{
                .key = split.key,
                .value = value,
                .line = line.number,
            });
        }

        return .{ .map = try entries.toOwnedSlice(self.allocator) };
    }

    fn parseSequence(self: *Parser, indent: usize) anyerror!Node {
        var items = std.ArrayList(Node).empty;
        errdefer items.deinit(self.allocator);

        while (self.index < self.lines.len) {
            const line = self.lines[self.index];
            if (line.indent < indent) break;
            if (line.indent > indent) return error.InvalidYamlIndentation;
            if (!isSequenceLine(line.text)) break;

            const rest = std.mem.trimLeft(u8, line.text[1..], " ");
            if (rest.len == 0) {
                self.index += 1;
                try items.append(self.allocator, try self.parseBlock(indent + 2));
                continue;
            }

            if (splitKeyValue(rest)) |inline_map_entry| {
                self.index += 1;
                try items.append(self.allocator, try self.parseInlineSequenceMap(indent, line.number, inline_map_entry));
                continue;
            }

            self.index += 1;
            try items.append(self.allocator, .{ .scalar = rest });
        }

        return .{ .seq = try items.toOwnedSlice(self.allocator) };
    }

    fn parseInlineSequenceMap(
        self: *Parser,
        indent: usize,
        line_number: usize,
        first_entry: KeyValueSplit,
    ) anyerror!Node {
        var entries = std.ArrayList(MapEntry).empty;
        errdefer entries.deinit(self.allocator);

        const first_value = if (first_entry.value) |inline_value|
            Node{ .scalar = inline_value }
        else if (self.index < self.lines.len and self.lines[self.index].indent > indent)
            try self.parseBlock(indent + 4)
        else
            Node{ .scalar = "" };
        try entries.append(self.allocator, .{
            .key = first_entry.key,
            .value = first_value,
            .line = line_number,
        });

        while (self.index < self.lines.len) {
            const line = self.lines[self.index];
            if (line.indent < indent + 2) break;
            if (line.indent > indent + 2) return error.InvalidYamlIndentation;
            if (isSequenceLine(line.text)) break;

            const split = splitKeyValue(line.text) orelse return error.InvalidYamlSyntax;
            self.index += 1;
            const value = if (split.value) |inline_value|
                Node{ .scalar = inline_value }
            else if (self.index < self.lines.len and self.lines[self.index].indent > indent + 2)
                try self.parseBlock(indent + 4)
            else
                Node{ .scalar = "" };
            try entries.append(self.allocator, .{
                .key = split.key,
                .value = value,
                .line = line.number,
            });
        }

        return .{ .map = try entries.toOwnedSlice(self.allocator) };
    }
};

pub fn parseDocument(allocator: std.mem.Allocator, bytes: []const u8) !Node {
    var lines = std.ArrayList(Line).empty;
    defer lines.deinit(allocator);

    var iter = std.mem.splitScalar(u8, bytes, '\n');
    var line_number: usize = 1;
    while (iter.next()) |raw_line| : (line_number += 1) {
        const trimmed_right = std.mem.trimRight(u8, raw_line, "\r ");
        if (trimmed_right.len == 0) continue;
        const trimmed_left = std.mem.trimLeft(u8, trimmed_right, " ");
        if (trimmed_left.len == 0 or trimmed_left[0] == '#') continue;
        const indent = trimmed_right.len - trimmed_left.len;
        if ((indent % 2) != 0) return error.InvalidYamlIndentation;
        if (std.mem.indexOfScalar(u8, trimmed_right, '\t') != null) return error.InvalidYamlIndentation;
        try lines.append(allocator, .{
            .number = line_number,
            .indent = indent,
            .text = trimmed_left,
        });
    }

    if (lines.items.len == 0) return error.EmptyYamlDocument;
    var parser = Parser{
        .allocator = allocator,
        .lines = try lines.toOwnedSlice(allocator),
    };
    return parser.parse();
}

fn splitKeyValue(text: []const u8) ?KeyValueSplit {
    const colon_index = std.mem.indexOfScalar(u8, text, ':') orelse return null;
    const key = std.mem.trim(u8, text[0..colon_index], " ");
    if (key.len == 0) return null;
    const raw_value = std.mem.trim(u8, text[colon_index + 1 ..], " ");
    return .{
        .key = key,
        .value = if (raw_value.len == 0) null else raw_value,
    };
}

fn isSequenceLine(text: []const u8) bool {
    return text.len != 0 and text[0] == '-';
}

test "parity yaml parser rejects unknown root fields" {
    const yaml =
        \\schema_version: 1
        \\metadata:
        \\  id: t
        \\  workspace: w
        \\inputs:
        \\  assets: {}
        \\templates: {}
        \\experiment:
        \\  simulation:
        \\    from: base
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_assets: true
        \\  require_resolved_stage_references: true
        \\extra: 1
    ;
    const root = try parseDocument(std.testing.allocator, yaml);
    try std.testing.expectError(error.UnsupportedField, @import("o2a_parity_scene.zig").compileResolvedCase(std.testing.allocator, root));
}
