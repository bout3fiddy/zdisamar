const std = @import("std");
const ExportFormat = @import("../../adapters/exporters/format.zig").ExportFormat;

pub const ProviderKind = enum {
    netcdf_cf,
    zarr,
};

pub const Provider = struct {
    id: []const u8,
    format: ExportFormat,
    media_type: []const u8,
    extension: []const u8,
    kind: ProviderKind,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.netcdf_cf")) {
        return .{
            .id = provider_id,
            .format = .netcdf_cf,
            .media_type = "application/x-netcdf",
            .extension = ".nc",
            .kind = .netcdf_cf,
        };
    }
    if (std.mem.eql(u8, provider_id, "builtin.zarr")) {
        return .{
            .id = provider_id,
            .format = .zarr,
            .media_type = "application/vnd+zarr",
            .extension = ".zarr",
            .kind = .zarr,
        };
    }
    return null;
}
