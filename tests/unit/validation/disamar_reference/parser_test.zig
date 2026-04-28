const std = @import("std");
const internal = @import("internal");

const o2a_parity_parser = internal.disamar_reference.parser;
const parseDocument = o2a_parity_parser.parseDocument;

test "parity yaml parser rejects unknown root fields" {
    const yaml =
        \\schema_version: 1
        \\metadata:
        \\  id: t
        \\  storage: w
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try parseDocument(allocator, yaml);
    try std.testing.expectError(
        error.UnsupportedField,
        internal.disamar_reference.scene.compileResolvedCase(allocator, root),
    );
}
