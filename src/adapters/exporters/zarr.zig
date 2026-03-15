const std = @import("std");
const Result = @import("../../core/Result.zig").Result;
const Spec = @import("spec.zig");
const io = @import("io.zig");

pub const Error = error{
    UnsupportedFormat,
    PathTooLong,
    ValueOutOfRange,
} || io.Error || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.WriteError || std.fs.Dir.MakeError || std.fmt.BufPrintError;

pub const ExportReport = struct {
    artifact: Spec.ExportArtifact,
    files_written: u32,
    bytes_written: usize,
};

pub fn write(request: Spec.ExportRequest, result: Result, allocator: std.mem.Allocator) Error!ExportReport {
    if (request.format != .zarr) return Error.UnsupportedFormat;
    const artifact = Spec.buildArtifact(request);
    const store_path = try io.filePathFromUri(request.destination_uri);

    try std.fs.cwd().makePath(store_path);

    var files_written: u32 = 0;
    var bytes_written: usize = 0;

    const root_group_payload = "{\n  \"zarr_format\": 2\n}\n";
    bytes_written += try writeStoreTextFile(store_path, ".zgroup", root_group_payload, &files_written);

    const root_attrs_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"conventions\": \"CF-1.10\",\n  \"source\": \"zdisamar\",\n  \"dataset_name\": \"{s}\",\n  \"scene_id\": \"{s}\",\n  \"workspace_label\": \"{s}\",\n  \"plan_id\": {d},\n  \"solver_route\": \"{s}\",\n  \"model_family\": \"{s}\",\n  \"transport_family\": \"{s}\",\n  \"derivative_mode\": \"{s}\",\n  \"numerical_mode\": \"{s}\",\n  \"status\": \"{s}\",\n  \"plugin_count\": {d},\n  \"dataset_hash_count\": {d},\n  \"native_capability_count\": {d},\n  \"native_entry_symbol_count\": {d},\n  \"native_library_path_count\": {d}\n}}\n",
        .{
            artifact.dataset_name,
            result.scene_id,
            result.workspace_label,
            result.plan_id,
            result.provenance.solver_route,
            result.provenance.model_family,
            result.provenance.transport_family,
            result.provenance.derivative_mode,
            result.provenance.numerical_mode,
            @tagName(result.status),
            result.provenance.plugin_versions.len,
            result.provenance.dataset_hashes.len,
            result.provenance.native_capability_slots.len,
            result.provenance.native_entry_symbols.len,
            result.provenance.native_library_paths.len,
        },
    );
    defer allocator.free(root_attrs_payload);
    bytes_written += try writeStoreTextFile(store_path, ".zattrs", root_attrs_payload, &files_written);

    const root_group_names = [_][]const u8{
        "metadata",
        "provenance",
        "diagnostics",
    };
    for (root_group_names) |group_name| {
        bytes_written += try writeSubgroup(allocator, store_path, group_name, &files_written);
    }

    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/dataset_name",
        "metadata",
        &[_][]const u8{artifact.dataset_name},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/scene_id",
        "metadata",
        &[_][]const u8{result.scene_id},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/workspace_label",
        "metadata",
        &[_][]const u8{result.workspace_label},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/status",
        "metadata",
        &[_][]const u8{@tagName(result.status)},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/engine_version",
        "metadata",
        &[_][]const u8{result.provenance.engine_version},
        &files_written,
    );

    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/model_family",
        "provenance",
        &[_][]const u8{result.provenance.model_family},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/solver_route",
        "provenance",
        &[_][]const u8{result.provenance.solver_route},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/transport_family",
        "provenance",
        &[_][]const u8{result.provenance.transport_family},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/derivative_mode",
        "provenance",
        &[_][]const u8{result.provenance.derivative_mode},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/numerical_mode",
        "provenance",
        &[_][]const u8{result.provenance.numerical_mode},
        &files_written,
    );

    if (result.provenance.plugin_versions.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/plugin_versions",
            "provenance",
            result.provenance.plugin_versions,
            &files_written,
        );
    }
    if (result.provenance.dataset_hashes.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/dataset_hashes",
            "provenance",
            result.provenance.dataset_hashes,
            &files_written,
        );
    }
    if (result.provenance.native_capability_slots.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/native_capability_slots",
            "provenance",
            result.provenance.native_capability_slots,
            &files_written,
        );
    }
    if (result.provenance.native_entry_symbols.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/native_entry_symbols",
            "provenance",
            result.provenance.native_entry_symbols,
            &files_written,
        );
    }
    if (result.provenance.native_library_paths.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/native_library_paths",
            "provenance",
            result.provenance.native_library_paths,
            &files_written,
        );
    }

    const provenance_counts = [_]i32{
        try toI32(result.provenance.plugin_versions.len),
        try toI32(result.provenance.dataset_hashes.len),
        try toI32(result.provenance.native_capability_slots.len),
        try toI32(result.provenance.native_entry_symbols.len),
        try toI32(result.provenance.native_library_paths.len),
    };
    bytes_written += try writeInt32Array(
        allocator,
        store_path,
        "provenance/counts",
        "provenance",
        &provenance_counts,
        &files_written,
    );

    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "diagnostics/summary",
        "diagnostics",
        &[_][]const u8{result.diagnostics.summary},
        &files_written,
    );
    const diagnostic_flags = [_]i32{
        @intFromBool(result.diagnostics.emitted_provenance),
        @intFromBool(result.diagnostics.emitted_jacobians),
        @intFromBool(result.diagnostics.emitted_internal_fields),
        @intFromBool(result.diagnostics.materialized_cache_keys),
    };
    bytes_written += try writeInt32Array(
        allocator,
        store_path,
        "diagnostics/flags",
        "diagnostics",
        &diagnostic_flags,
        &files_written,
    );

    return .{
        .artifact = artifact,
        .files_written = files_written,
        .bytes_written = bytes_written,
    };
}

fn writeSubgroup(
    allocator: std.mem.Allocator,
    store_path: []const u8,
    relative_group_path: []const u8,
    files_written: *u32,
) !usize {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const group_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ store_path, relative_group_path });
    try std.fs.cwd().makePath(group_path);

    var bytes_written: usize = 0;
    bytes_written += try writeStoreTextFile(group_path, ".zgroup", "{\n  \"zarr_format\": 2\n}\n", files_written);

    const attrs_payload = try std.fmt.allocPrint(allocator, "{{\n  \"group_role\": \"{s}\"\n}}\n", .{relative_group_path});
    defer allocator.free(attrs_payload);
    bytes_written += try writeStoreTextFile(group_path, ".zattrs", attrs_payload, files_written);
    return bytes_written;
}

fn writeStringArray(
    allocator: std.mem.Allocator,
    store_path: []const u8,
    relative_array_path: []const u8,
    group_role: []const u8,
    values: []const []const u8,
    files_written: *u32,
) !usize {
    const width = maxStringLen(values);
    const chunk_payload = try encodeStringChunk(allocator, values, width);
    defer allocator.free(chunk_payload);

    const zarray_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"chunks\": [{d}],\n  \"compressor\": null,\n  \"dtype\": \"|S{d}\",\n  \"fill_value\": null,\n  \"filters\": null,\n  \"order\": \"C\",\n  \"shape\": [{d}],\n  \"zarr_format\": 2\n}}\n",
        .{ values.len, width, values.len },
    );
    defer allocator.free(zarray_payload);

    const zattrs_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"_ARRAY_DIMENSIONS\": [\"item\"],\n  \"content_type\": \"fixed_ascii_string\",\n  \"group_role\": \"{s}\"\n}}\n",
        .{group_role},
    );
    defer allocator.free(zattrs_payload);

    var bytes_written: usize = 0;
    bytes_written += try writeArrayDirectory(store_path, relative_array_path);

    var zarray_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zarray_relative = try std.fmt.bufPrint(&zarray_rel_path, "{s}/.zarray", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zarray_relative, zarray_payload, files_written);

    var zattrs_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zattrs_relative = try std.fmt.bufPrint(&zattrs_rel_path, "{s}/.zattrs", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zattrs_relative, zattrs_payload, files_written);

    var chunk_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const chunk_relative = try std.fmt.bufPrint(&chunk_rel_path, "{s}/0", .{relative_array_path});
    bytes_written += try writeStoreBinaryFile(store_path, chunk_relative, chunk_payload, files_written);
    return bytes_written;
}

fn writeInt32Array(
    allocator: std.mem.Allocator,
    store_path: []const u8,
    relative_array_path: []const u8,
    group_role: []const u8,
    values: []const i32,
    files_written: *u32,
) !usize {
    const chunk_payload = try encodeInt32Chunk(allocator, values);
    defer allocator.free(chunk_payload);

    const zarray_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"chunks\": [{d}],\n  \"compressor\": null,\n  \"dtype\": \"<i4\",\n  \"fill_value\": 0,\n  \"filters\": null,\n  \"order\": \"C\",\n  \"shape\": [{d}],\n  \"zarr_format\": 2\n}}\n",
        .{ values.len, values.len },
    );
    defer allocator.free(zarray_payload);

    const zattrs_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"_ARRAY_DIMENSIONS\": [\"item\"],\n  \"content_type\": \"int32\",\n  \"group_role\": \"{s}\"\n}}\n",
        .{group_role},
    );
    defer allocator.free(zattrs_payload);

    var bytes_written: usize = 0;
    bytes_written += try writeArrayDirectory(store_path, relative_array_path);

    var zarray_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zarray_relative = try std.fmt.bufPrint(&zarray_rel_path, "{s}/.zarray", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zarray_relative, zarray_payload, files_written);

    var zattrs_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zattrs_relative = try std.fmt.bufPrint(&zattrs_rel_path, "{s}/.zattrs", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zattrs_relative, zattrs_payload, files_written);

    var chunk_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const chunk_relative = try std.fmt.bufPrint(&chunk_rel_path, "{s}/0", .{relative_array_path});
    bytes_written += try writeStoreBinaryFile(store_path, chunk_relative, chunk_payload, files_written);
    return bytes_written;
}

fn writeArrayDirectory(store_path: []const u8, relative_array_path: []const u8) !usize {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const array_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ store_path, relative_array_path });
    try std.fs.cwd().makePath(array_path);
    return 0;
}

fn writeStoreTextFile(store_path: []const u8, relative_path: []const u8, payload: []const u8, files_written: *u32) !usize {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ store_path, relative_path });
    files_written.* += 1;
    return io.writeTextFile(full_path, payload);
}

fn writeStoreBinaryFile(store_path: []const u8, relative_path: []const u8, payload: []const u8, files_written: *u32) !usize {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ store_path, relative_path });
    files_written.* += 1;
    return io.writeBinaryFile(full_path, payload);
}

fn encodeStringChunk(allocator: std.mem.Allocator, values: []const []const u8, width: usize) ![]u8 {
    const payload = try allocator.alloc(u8, values.len * width);
    @memset(payload, 0);
    for (values, 0..) |value, index| {
        const row = payload[index * width ..][0..width];
        std.mem.copyForwards(u8, row[0..value.len], value);
    }
    return payload;
}

fn encodeInt32Chunk(allocator: std.mem.Allocator, values: []const i32) ![]u8 {
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    for (values) |value| try writer.writeInt(i32, value, .little);
    return buffer.toOwnedSlice(allocator);
}

fn maxStringLen(values: []const []const u8) usize {
    var max_len: usize = 1;
    for (values) |value| max_len = @max(max_len, value.len);
    return max_len;
}

fn toI32(value: usize) Error!i32 {
    return std.math.cast(i32, value) orelse Error.ValueOutOfRange;
}

test "zarr exporter emits group metadata and array stores" {
    const plugin_versions = [_][]const u8{"builtin.zarr@0.1.0"};
    const dataset_hashes = [_][]const u8{"sha256:test-zarr"};
    const result = Result.init(9, "ws-zarr", "scene-zarr", .{
        .plan_id = 9,
        .workspace_label = "ws-zarr",
        .scene_id = "scene-zarr",
        .plugin_versions = &plugin_versions,
        .dataset_hashes = &dataset_hashes,
    });

    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try std.fmt.bufPrint(&root_buffer, "zig-cache/zarr-backend-test-{d}", .{@as(u64, @intCast(@abs(std.time.nanoTimestamp())))});
    defer std.fs.cwd().deleteTree(root) catch {};

    const destination_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/scene.zarr", .{root});
    defer std.testing.allocator.free(destination_uri);

    const report = try write(.{
        .format = .zarr,
        .destination_uri = destination_uri,
        .dataset_name = "scene-zarr",
    }, result, std.testing.allocator);

    try std.testing.expect(report.files_written >= 20);

    const zgroup_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/.zgroup", .{root});
    defer std.testing.allocator.free(zgroup_path);
    const plugin_array_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/provenance/plugin_versions/.zarray", .{root});
    defer std.testing.allocator.free(plugin_array_path);
    const plugin_chunk_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/provenance/plugin_versions/0", .{root});
    defer std.testing.allocator.free(plugin_chunk_path);

    const zgroup_payload = try std.fs.cwd().readFileAlloc(std.testing.allocator, zgroup_path, 8 * 1024);
    defer std.testing.allocator.free(zgroup_payload);
    const zarray_payload = try std.fs.cwd().readFileAlloc(std.testing.allocator, plugin_array_path, 8 * 1024);
    defer std.testing.allocator.free(zarray_payload);
    const chunk_payload = try std.fs.cwd().readFileAlloc(std.testing.allocator, plugin_chunk_path, 8 * 1024);
    defer std.testing.allocator.free(chunk_payload);

    try std.testing.expect(std.mem.containsAtLeast(u8, zgroup_payload, 1, "\"zarr_format\": 2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, zarray_payload, 1, "\"dtype\": \"|S"));
    try std.testing.expect(std.mem.containsAtLeast(u8, chunk_payload, 1, "builtin.zarr@0.1.0"));
}
