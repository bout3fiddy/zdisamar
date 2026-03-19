const std = @import("std");
const Result = @import("../../core/Result.zig").Result;

pub const ExportFormat = @import("format.zig").ExportFormat;
pub const ExportRequest = @import("spec.zig").ExportRequest;
pub const ExportArtifact = @import("spec.zig").ExportArtifact;
pub const buildArtifact = @import("spec.zig").buildArtifact;

pub const writer = @import("writer.zig");

test "exporter package includes concrete backend modules" {
    _ = @import("io.zig");
    _ = @import("netcdf_cf.zig");
    _ = @import("zarr.zig");
    _ = @import("diagnostic.zig");
    _ = @import("writer.zig");
}

fn makeOutputRoot(prefix: []const u8, path_buffer: []u8) ![]const u8 {
    const timestamp = @as(u64, @intCast(@abs(std.time.nanoTimestamp())));
    return std.fmt.bufPrint(path_buffer, "zig-cache/exporter-tests/{s}-{d}", .{ prefix, timestamp });
}

fn makeResult() !Result {
    const dataset_hashes = &[_][]const u8{
        "sha256:test-cross-sections",
        "sha256:test-lut",
    };
    var provenance: @import("../../core/provenance.zig").Provenance = .{
        .plan_id = 42,
        .workspace_label = "export-suite",
        .scene_id = "scene-export",
        .dataset_hashes = dataset_hashes,
    };
    provenance.setPluginVersions(&[_][]const u8{
        "builtin.netcdf_cf@0.1.0",
        "builtin.zarr@0.1.0",
    });
    return Result.init(std.testing.allocator, 42, "export-suite", "scene-export", provenance);
}

test "netcdf/cf exporter writes file payload to destination uri" {
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try makeOutputRoot("netcdf", &root_buffer);
    defer std.fs.cwd().deleteTree(root) catch {};

    const destination_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/scene.nc", .{root});
    defer std.testing.allocator.free(destination_uri);
    var result = try makeResult();
    defer result.deinit(std.testing.allocator);

    const report = try writer.write(
        std.testing.allocator,
        .{
            .plugin_id = "builtin.netcdf_cf",
            .format = .netcdf_cf,
            .destination_uri = destination_uri,
            .dataset_name = "scene-export",
        },
        @import("spec.zig").ExportView.fromResult(&result),
    );

    try std.testing.expectEqual(@as(u32, 1), report.files_written);
    try std.testing.expectEqualStrings("builtin.netcdf_cf", report.artifact.plugin_id);

    const output_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.nc", .{root});
    defer std.testing.allocator.free(output_path);
    const payload = try std.fs.cwd().readFileAlloc(std.testing.allocator, output_path, 64 * 1024);
    defer std.testing.allocator.free(payload);

    try std.testing.expect(std.mem.startsWith(u8, payload, "CDF\x01"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "Conventions"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "scene-export"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "plugin_versions"));
}

test "zarr exporter writes structured store files" {
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try makeOutputRoot("zarr", &root_buffer);
    defer std.fs.cwd().deleteTree(root) catch {};

    const destination_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/scene.zarr", .{root});
    defer std.testing.allocator.free(destination_uri);
    var result = try makeResult();
    defer result.deinit(std.testing.allocator);

    const report = try writer.write(
        std.testing.allocator,
        .{
            .plugin_id = "builtin.zarr",
            .format = .zarr,
            .destination_uri = destination_uri,
            .dataset_name = "scene-export",
        },
        @import("spec.zig").ExportView.fromResult(&result),
    );
    try std.testing.expect(report.files_written >= 20);
    try std.testing.expectEqualStrings("builtin.zarr", report.artifact.plugin_id);

    const zgroup_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/.zgroup", .{root});
    defer std.testing.allocator.free(zgroup_path);
    const zattrs_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/.zattrs", .{root});
    defer std.testing.allocator.free(zattrs_path);
    const plugin_zarray_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/provenance/plugin_versions/.zarray", .{root});
    defer std.testing.allocator.free(plugin_zarray_path);
    const plugin_chunk_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/provenance/plugin_versions/0", .{root});
    defer std.testing.allocator.free(plugin_chunk_path);
    const counts_chunk_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/provenance/counts/0", .{root});
    defer std.testing.allocator.free(counts_chunk_path);

    try std.fs.cwd().access(zgroup_path, .{});
    try std.fs.cwd().access(zattrs_path, .{});
    try std.fs.cwd().access(plugin_zarray_path, .{});
    try std.fs.cwd().access(plugin_chunk_path, .{});
    try std.fs.cwd().access(counts_chunk_path, .{});

    const attrs = try std.fs.cwd().readFileAlloc(std.testing.allocator, zattrs_path, 64 * 1024);
    defer std.testing.allocator.free(attrs);
    const plugin_zarray = try std.fs.cwd().readFileAlloc(std.testing.allocator, plugin_zarray_path, 64 * 1024);
    defer std.testing.allocator.free(plugin_zarray);
    const plugin_chunk = try std.fs.cwd().readFileAlloc(std.testing.allocator, plugin_chunk_path, 64 * 1024);
    defer std.testing.allocator.free(plugin_chunk);
    try std.testing.expect(std.mem.containsAtLeast(u8, attrs, 1, "\"scene_id\": \"scene-export\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, plugin_zarray, 1, "\"dtype\": \"|S"));
    try std.testing.expect(std.mem.containsAtLeast(u8, plugin_chunk, 1, "builtin.zarr@0.1.0"));
}

test "diagnostic exporter writes csv and text artifacts" {
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try makeOutputRoot("diag", &root_buffer);
    defer std.fs.cwd().deleteTree(root) catch {};

    const csv_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/diag.csv", .{root});
    defer std.testing.allocator.free(csv_uri);
    const txt_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/diag.txt", .{root});
    defer std.testing.allocator.free(txt_uri);
    var result = makeResult();

    _ = try writer.exportDiagnostic(
        std.testing.allocator,
        csv_uri,
        .csv,
        @import("spec.zig").ExportView.fromResult(&result),
    );
    _ = try writer.exportDiagnostic(
        std.testing.allocator,
        txt_uri,
        .text,
        @import("spec.zig").ExportView.fromResult(&result),
    );

    const csv_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/diag.csv", .{root});
    defer std.testing.allocator.free(csv_path);
    const txt_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/diag.txt", .{root});
    defer std.testing.allocator.free(txt_path);

    const csv_payload = try std.fs.cwd().readFileAlloc(std.testing.allocator, csv_path, 64 * 1024);
    defer std.testing.allocator.free(csv_payload);
    const txt_payload = try std.fs.cwd().readFileAlloc(std.testing.allocator, txt_path, 64 * 1024);
    defer std.testing.allocator.free(txt_payload);

    try std.testing.expect(std.mem.startsWith(u8, csv_payload, "plan_id,scene_id"));
    try std.testing.expect(std.mem.containsAtLeast(u8, txt_payload, 1, "solver_route: builtin.dispatcher"));
}
