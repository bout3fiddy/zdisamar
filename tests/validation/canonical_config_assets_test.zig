const std = @import("std");
const zdisamar = @import("zdisamar");

const ReleaseReadiness = struct {
    version: u32,
    required_artifacts: []const []const u8,
};

fn containsString(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) return true;
    }
    return false;
}

test "tracked canonical examples resolve from repository-owned paths" {
    var common = try zdisamar.canonical_config.resolveFile(
        std.testing.allocator,
        "data/examples/zdisamar_common_use.yaml",
    );
    defer common.deinit();

    var expert = try zdisamar.canonical_config.resolveFile(
        std.testing.allocator,
        "data/examples/zdisamar_expert_o2a.yaml",
    );
    defer expert.deinit();

    try std.testing.expect(common.simulation != null);
    try std.testing.expect(common.retrieval != null);
    try std.testing.expect(expert.simulation != null);
    try std.testing.expect(expert.retrieval != null);
}

test "release readiness lists canonical config examples and validation artifacts" {
    const raw = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "validation/release/release_readiness.json",
        1024 * 1024,
    );
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        ReleaseReadiness,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);

    const required = parsed.value.required_artifacts;
    try std.testing.expect(containsString(required, "data/examples/canonical_config.yaml"));
    try std.testing.expect(containsString(required, "data/examples/zdisamar_common_use.yaml"));
    try std.testing.expect(containsString(required, "data/examples/zdisamar_expert_o2a.yaml"));
    try std.fs.cwd().access("data/examples/canonical_config.yaml", .{});
    try std.fs.cwd().access("data/examples/zdisamar_common_use.yaml", .{});
    try std.fs.cwd().access("data/examples/zdisamar_expert_o2a.yaml", .{});
}
