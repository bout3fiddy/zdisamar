//! Purpose:
//!   Cache lookup-table metadata by dataset id and LUT id.
//!
//! Physics:
//!   Preserve the reusable shape information for reference LUTs without changing the table
//!   values themselves.
//!
//! Vendor:
//!   `lookup-table cache`
//!
//! Design:
//!   Key entries by the composite `(dataset_id, lut_id)` pair and refresh revisions in place.
//!
//! Invariants:
//!   The dataset/LUT pair uniquely identifies each cached entry.
//!
//! Validation:
//!   Cache package unit tests.

const std = @import("std");

const Allocator = std.mem.Allocator;

/// Purpose:
///   Store the reusable LUT shape summary.
pub const LUTShape = struct {
    spectral_bins: u32 = 0,
    layer_count: u32 = 0,
    coefficient_count: u32 = 0,
};

/// Purpose:
///   Store one cached LUT entry.
pub const Entry = struct {
    dataset_id: []const u8,
    lut_id: []const u8,
    shape: LUTShape = .{},
    revision: u64 = 0,
};

/// Purpose:
///   Retain LUT metadata for repeated execution.
///
/// Invariants:
///   The same `(dataset_id, lut_id)` pair always resolves to the same cache slot.
pub const LUTCache = struct {
    pub const Shape = LUTShape;

    allocator: Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .{},
    generation: u64 = 0,

    /// Purpose:
    ///   Construct an empty LUT cache.
    pub fn init(allocator: Allocator) LUTCache {
        return .{ .allocator = allocator };
    }

    /// Purpose:
    ///   Release all owned LUT identifiers.
    pub fn deinit(self: *LUTCache) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.dataset_id);
            self.allocator.free(entry.lut_id);
        }
        self.entries.deinit(self.allocator);
    }

    /// Purpose:
    ///   Insert or refresh one LUT metadata entry.
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

    /// Purpose:
    ///   Look up the cached LUT metadata for a dataset/LUT pair.
    pub fn get(self: *const LUTCache, dataset_id: []const u8, lut_id: []const u8) ?Entry {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.dataset_id, dataset_id) and std.mem.eql(u8, entry.lut_id, lut_id)) {
                return entry;
            }
        }
        return null;
    }

    /// Purpose:
    ///   Report how many LUT entries are cached.
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
