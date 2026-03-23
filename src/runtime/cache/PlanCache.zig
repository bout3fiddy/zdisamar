//! Purpose:
//!   Cache prepared plan layouts keyed by plan id for repeated execution.
//!
//! Physics:
//!   Preserve the reused measurement and layout sizing hints that do not alter the underlying
//!   retrieval or transport calculations.
//!
//! Vendor:
//!   `prepared plan cache`
//!
//! Design:
//!   Keep the cache keyed by plan id and evict the oldest entry when capacity is reached.
//!
//! Invariants:
//!   Each cached entry owns a single prepared layout snapshot for its plan id.
//!
//! Validation:
//!   Cache package unit tests.

const std = @import("std");
const PreparedLayout = @import("PreparedLayout.zig").PreparedLayout;

const Allocator = std.mem.Allocator;

/// Purpose:
///   Store the prepared layout and usage counters for one plan.
///
/// Physics:
///   Keep the reusable execution shape and revision state together.
pub const Entry = struct {
    plan_id: u64,
    prepared_layout: PreparedLayout,
    run_count: u64 = 0,
    revision: u64 = 0,
};

/// Purpose:
///   Configure the reuse cap for the prepared-plan cache.
///
/// Physics:
///   Limit how many prepared layouts remain resident at once.
pub const Options = struct {
    // Maximum prepared plans retained for reuse before oldest entries are evicted.
    max_entries: usize = 64,
};

/// Purpose:
///   Retain prepared plans for repeated execution.
///
/// Physics:
///   Cache the derived layout state so repeated requests can skip recomputation.
///
/// Invariants:
///   Entries are keyed by plan id and updates refresh the stored layout in place.
pub const PlanCache = struct {
    allocator: Allocator,
    options: Options,
    entries: std.ArrayListUnmanaged(Entry) = .{},
    generation: u64 = 0,

    /// Purpose:
    ///   Construct an empty prepared-plan cache.
    pub fn init(allocator: Allocator, options: Options) PlanCache {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Purpose:
    ///   Release all cached prepared layouts.
    pub fn deinit(self: *PlanCache) void {
        self.entries.deinit(self.allocator);
    }

    /// Purpose:
    ///   Insert or refresh a prepared layout for one plan id.
    ///
    /// Physics:
    ///   Update the cached execution shape without changing the downstream scientific result.
    pub fn put(self: *PlanCache, plan_id: u64, prepared_layout: PreparedLayout) !void {
        if (self.options.max_entries == 0) {
            return error.PlanCacheDisabled;
        }

        for (self.entries.items) |*entry| {
            if (entry.plan_id == plan_id) {
                entry.prepared_layout = prepared_layout;
                entry.revision += 1;
                self.generation += 1;
                return;
            }
        }

        if (self.entries.items.len >= self.options.max_entries) {
            _ = self.entries.orderedRemove(0);
        }

        try self.entries.append(self.allocator, .{
            .plan_id = plan_id,
            .prepared_layout = prepared_layout,
        });
        self.generation += 1;
    }

    /// Purpose:
    ///   Look up a cached prepared layout by plan id.
    ///
    /// Physics:
    ///   Retrieve the reusable execution shape for repeated work.
    pub fn get(self: *PlanCache, plan_id: u64) ?*Entry {
        for (self.entries.items) |*entry| {
            if (entry.plan_id == plan_id) {
                return entry;
            }
        }
        return null;
    }

    /// Purpose:
    ///   Record one reuse of a cached prepared layout.
    ///
    /// Physics:
    ///   Track repeated execution without modifying the scientific payload.
    pub fn markRun(self: *PlanCache, plan_id: u64) bool {
        const entry = self.get(plan_id) orelse return false;
        entry.run_count += 1;
        return true;
    }

    /// Purpose:
    ///   Report how many prepared layouts are currently cached.
    pub fn count(self: *const PlanCache) usize {
        return self.entries.items.len;
    }
};

test "plan cache evicts oldest entries once capacity is reached" {
    var cache = PlanCache.init(std.testing.allocator, .{ .max_entries = 2 });
    defer cache.deinit();

    try cache.put(100, .{ .measurement_capacity = 16 });
    try cache.put(200, .{ .measurement_capacity = 24 });
    try cache.put(300, .{ .measurement_capacity = 32 });

    try std.testing.expectEqual(@as(usize, 2), cache.count());
    try std.testing.expect(cache.get(100) == null);
    try std.testing.expect(cache.get(200) != null);
    try std.testing.expect(cache.get(300) != null);
}

test "plan cache records run counts and revisions" {
    var cache = PlanCache.init(std.testing.allocator, .{ .max_entries = 4 });
    defer cache.deinit();

    try cache.put(17, .{ .measurement_capacity = 8 });
    try cache.put(17, .{ .measurement_capacity = 12 });
    try std.testing.expect(cache.markRun(17));

    const entry = cache.get(17).?;
    try std.testing.expectEqual(@as(u64, 1), entry.revision);
    try std.testing.expectEqual(@as(u64, 1), entry.run_count);
    try std.testing.expectEqual(@as(u32, 12), entry.prepared_layout.measurement_capacity);
}
