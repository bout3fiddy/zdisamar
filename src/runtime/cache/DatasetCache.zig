const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Entry = struct {
    id: []const u8,
    dataset_hash: []const u8,
    revision: u64 = 0,
};

pub const DatasetCache = struct {
    allocator: Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .{},
    generation: u64 = 0,
    owned_bytes: usize = 0,

    pub fn init(allocator: Allocator) DatasetCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DatasetCache) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.id);
            self.allocator.free(entry.dataset_hash);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn upsert(self: *DatasetCache, id: []const u8, dataset_hash: []const u8) !void {
        if (id.len == 0 or dataset_hash.len == 0) {
            return error.InvalidDatasetRecord;
        }

        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.id, id)) {
                const hash_copy = try self.allocator.dupe(u8, dataset_hash);
                self.allocator.free(entry.dataset_hash);
                entry.dataset_hash = hash_copy;
                entry.revision += 1;
                self.generation += 1;
                return;
            }
        }

        const id_copy = try self.allocator.dupe(u8, id);
        errdefer self.allocator.free(id_copy);

        const hash_copy = try self.allocator.dupe(u8, dataset_hash);
        errdefer self.allocator.free(hash_copy);

        try self.entries.append(self.allocator, .{
            .id = id_copy,
            .dataset_hash = hash_copy,
        });
        self.owned_bytes += id_copy.len + hash_copy.len;
        self.generation += 1;
    }

    pub fn get(self: *const DatasetCache, id: []const u8) ?Entry {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.id, id)) {
                return entry;
            }
        }
        return null;
    }

    pub fn count(self: *const DatasetCache) usize {
        return self.entries.items.len;
    }
};

test "dataset cache owns records and updates revisions on overwrite" {
    var cache = DatasetCache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.upsert("climatology.base", "sha256:a");
    try cache.upsert("cross_sections.o3", "sha256:b");
    try cache.upsert("climatology.base", "sha256:c");

    try std.testing.expectEqual(@as(usize, 2), cache.count());
    try std.testing.expectEqual(@as(u64, 3), cache.generation);
    try std.testing.expect(cache.owned_bytes > 0);

    const first = cache.get("climatology.base").?;
    try std.testing.expectEqual(@as(u64, 1), first.revision);
    try std.testing.expectEqualStrings("sha256:c", first.dataset_hash);
}
