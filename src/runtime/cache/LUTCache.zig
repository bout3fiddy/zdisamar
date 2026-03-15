const std = @import("std");

const Allocator = std.mem.Allocator;

pub const LUTShape = struct {
    spectral_bins: u32 = 0,
    layer_count: u32 = 0,
    coefficient_count: u32 = 0,
};

pub const Entry = struct {
    dataset_id: []const u8,
    lut_id: []const u8,
    shape: LUTShape = .{},
    revision: u64 = 0,
};

pub const LUTCache = struct {
    pub const Shape = LUTShape;

    allocator: Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .{},
    generation: u64 = 0,

    pub fn init(allocator: Allocator) LUTCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LUTCache) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.dataset_id);
            self.allocator.free(entry.lut_id);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn upsert(self: *LUTCache, dataset_id: []const u8, lut_id: []const u8, shape: LUTShape) !void {
        if (dataset_id.len == 0 or lut_id.len == 0) {
            return error.InvalidLUTRecord;
        }

        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.dataset_id, dataset_id) and std.mem.eql(u8, entry.lut_id, lut_id)) {
                entry.shape = shape;
                entry.revision += 1;
                self.generation += 1;
                return;
            }
        }

        const dataset_copy = try self.allocator.dupe(u8, dataset_id);
        errdefer self.allocator.free(dataset_copy);
        const lut_copy = try self.allocator.dupe(u8, lut_id);
        errdefer self.allocator.free(lut_copy);

        try self.entries.append(self.allocator, .{
            .dataset_id = dataset_copy,
            .lut_id = lut_copy,
            .shape = shape,
        });
        self.generation += 1;
    }

    pub fn get(self: *const LUTCache, dataset_id: []const u8, lut_id: []const u8) ?Entry {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.dataset_id, dataset_id) and std.mem.eql(u8, entry.lut_id, lut_id)) {
                return entry;
            }
        }
        return null;
    }

    pub fn count(self: *const LUTCache) usize {
        return self.entries.items.len;
    }
};

test "lut cache keys records by dataset and lut id" {
    var cache = LUTCache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.upsert("cross_sections.o3", "temperature_273", .{
        .spectral_bins = 600,
        .layer_count = 40,
        .coefficient_count = 8,
    });
    try cache.upsert("cross_sections.o3", "temperature_273", .{
        .spectral_bins = 620,
        .layer_count = 40,
        .coefficient_count = 8,
    });
    try cache.upsert("cross_sections.o3", "temperature_280", .{
        .spectral_bins = 620,
        .layer_count = 40,
        .coefficient_count = 8,
    });

    try std.testing.expectEqual(@as(usize, 2), cache.count());
    try std.testing.expectEqual(@as(u64, 3), cache.generation);

    const updated = cache.get("cross_sections.o3", "temperature_273").?;
    try std.testing.expectEqual(@as(u32, 620), updated.shape.spectral_bins);
    try std.testing.expectEqual(@as(u64, 1), updated.revision);
}
