const std = @import("std");

pub const BuiltinExporter = struct {
    id: []const u8,
    format: []const u8,
    lane: []const u8,
    capability_slot: []const u8 = "exporter",
    manifest_path: []const u8,
    media_type: []const u8,
    extension: []const u8,
};

pub const builtin_exporters = [_]BuiltinExporter{
    .{
        .id = "builtin.netcdf_cf",
        .format = "netcdf_cf",
        .lane = "native",
        .manifest_path = "src/plugins/builtin/exporters/netcdf_cf.plugin.json",
        .media_type = "application/x-netcdf",
        .extension = ".nc",
    },
    .{
        .id = "builtin.zarr",
        .format = "zarr",
        .lane = "native",
        .manifest_path = "src/plugins/builtin/exporters/zarr.plugin.json",
        .media_type = "application/vnd+zarr",
        .extension = ".zarr",
    },
};

pub fn isOfficialFormat(format: []const u8) bool {
    for (builtin_exporters) |exporter| {
        if (std.mem.eql(u8, exporter.format, format)) return true;
    }
    return false;
}

test "official exporter catalog includes netcdf/cf and zarr only" {
    try std.testing.expectEqual(@as(usize, 2), builtin_exporters.len);
    try std.testing.expect(isOfficialFormat("netcdf_cf"));
    try std.testing.expect(isOfficialFormat("zarr"));
    try std.testing.expect(!isOfficialFormat("ascii_hdf"));

    try std.testing.expectEqualStrings("src/plugins/builtin/exporters/netcdf_cf.plugin.json", builtin_exporters[0].manifest_path);
    try std.testing.expectEqualStrings("application/vnd+zarr", builtin_exporters[1].media_type);
    try std.testing.expectEqualStrings(".zarr", builtin_exporters[1].extension);
}
