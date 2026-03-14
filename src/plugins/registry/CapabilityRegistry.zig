const std = @import("std");

pub const Lane = enum {
    declarative,
    native,
};

pub const Capability = struct {
    slot: []const u8,
    provider: []const u8,
    lane: Lane,
};

pub const CapabilityRegistry = struct {
    capabilities: std.ArrayListUnmanaged(Capability) = .{},

    pub fn register(self: *CapabilityRegistry, allocator: std.mem.Allocator, capability: Capability) !void {
        try self.capabilities.append(allocator, capability);
    }

    pub fn bootstrapBuiltin(self: *CapabilityRegistry, allocator: std.mem.Allocator) !void {
        if (self.capabilities.items.len != 0) return;

        try self.register(allocator, .{
            .slot = "transport.solver",
            .provider = "builtin.dispatcher",
            .lane = .native,
        });
        try self.register(allocator, .{
            .slot = "exporter",
            .provider = "builtin.netcdf_cf",
            .lane = .native,
        });
        try self.register(allocator, .{
            .slot = "exporter",
            .provider = "builtin.zarr",
            .lane = .native,
        });
    }

    pub fn deinit(self: *CapabilityRegistry, allocator: std.mem.Allocator) void {
        self.capabilities.deinit(allocator);
        self.* = .{};
    }
};
