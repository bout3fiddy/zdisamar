const std = @import("std");

pub const ExportFormat = enum {
    netcdf_cf,
    zarr,

    pub fn id(self: ExportFormat) []const u8 {
        return switch (self) {
            .netcdf_cf => "netcdf_cf",
            .zarr => "zarr",
        };
    }

    pub fn extension(self: ExportFormat) []const u8 {
        return switch (self) {
            .netcdf_cf => ".nc",
            .zarr => ".zarr",
        };
    }

    pub fn mediaType(self: ExportFormat) []const u8 {
        return switch (self) {
            .netcdf_cf => "application/x-netcdf",
            .zarr => "application/vnd+zarr",
        };
    }
};

test "export format metadata remains stable for official formats" {
    try std.testing.expectEqualStrings("netcdf_cf", ExportFormat.netcdf_cf.id());
    try std.testing.expectEqualStrings(".nc", ExportFormat.netcdf_cf.extension());
    try std.testing.expectEqualStrings("application/x-netcdf", ExportFormat.netcdf_cf.mediaType());
    try std.testing.expectEqualStrings("zarr", ExportFormat.zarr.id());
    try std.testing.expectEqualStrings(".zarr", ExportFormat.zarr.extension());
    try std.testing.expectEqualStrings("application/vnd+zarr", ExportFormat.zarr.mediaType());
}
