const std = @import("std");
const internal = @import("zdisamar_internal");

test "plugin ABI and resolver modules are linked into the unit suite" {
    _ = internal.plugin_internal.abi_types;
    _ = internal.plugin_internal.host_api;
    _ = internal.plugin_internal.dynlib;
    _ = internal.plugin_internal.resolver;
}

test "native plugin example manifests declare ABI v1 entry symbols" {
    const native_example_files = [_][]const u8{
        "plugins/examples/native_exporter/plugin.json",
        "plugins/examples/native_retrieval/plugin.json",
        "plugins/examples/native_surface/plugin.json",
    };

    for (native_example_files) |relative_path| {
        const raw = try std.fs.cwd().readFileAlloc(std.testing.allocator, relative_path, 64 * 1024);
        defer std.testing.allocator.free(raw);

        const parsed = try std.json.parseFromSlice(struct {
            lane: []const u8,
            native: struct {
                abi_version: u32,
                entry_symbol: []const u8,
            },
        }, std.testing.allocator, raw, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        try std.testing.expectEqualStrings("native", parsed.value.lane);
        try std.testing.expectEqual(@as(u32, 1), parsed.value.native.abi_version);
        try std.testing.expectEqualStrings("zdisamar_plugin_entry_v1", parsed.value.native.entry_symbol);
    }
}
