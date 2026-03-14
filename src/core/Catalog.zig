const std = @import("std");

pub const ModelFamily = struct {
    name: []const u8,
    description: []const u8,
};

pub const Catalog = struct {
    model_families: std.ArrayListUnmanaged(ModelFamily) = .{},
    exporters: std.ArrayListUnmanaged([]const u8) = .{},
    bootstrapped: bool = false,

    pub fn bootstrapBuiltin(self: *Catalog, allocator: std.mem.Allocator) !void {
        if (self.bootstrapped) return;

        try self.model_families.append(allocator, .{
            .name = "disamar_standard",
            .description = "Bundled DISAMAR 1D family on the reusable RT platform scaffold.",
        });
        try self.exporters.append(allocator, "netcdf_cf");
        try self.exporters.append(allocator, "zarr");

        self.bootstrapped = true;
    }

    pub fn deinit(self: *Catalog, allocator: std.mem.Allocator) void {
        self.model_families.deinit(allocator);
        self.exporters.deinit(allocator);
        self.* = .{};
    }

    pub fn supportsModelFamily(self: *const Catalog, name: []const u8) bool {
        for (self.model_families.items) |family| {
            if (std.mem.eql(u8, family.name, name)) {
                return true;
            }
        }
        return false;
    }
};
