const std = @import("std");

pub const BuiltinExporter = struct {
    id: []const u8,
    format: []const u8,
    lane: []const u8,
    capability_slot: []const u8 = "exporter",
};

pub const builtin_exporters = [_]BuiltinExporter{
    .{
        .id = "builtin.netcdf_cf",
        .format = "netcdf_cf",
        .lane = "native",
    },
    .{
        .id = "builtin.zarr",
        .format = "zarr",
        .lane = "native",
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
}
