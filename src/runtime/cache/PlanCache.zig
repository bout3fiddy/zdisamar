const std = @import("std");
const PreparedPlanCache = @import("PreparedPlanCache.zig").PreparedPlanCache;

const Allocator = std.mem.Allocator;

pub const Entry = struct {
    plan_id: u64,
    prepared: PreparedPlanCache,
    run_count: u64 = 0,
    revision: u64 = 0,
};

pub const Options = struct {
    // Maximum prepared plans retained for reuse before oldest entries are evicted.
    max_entries: usize = 64,
};

pub const PlanCache = struct {
    allocator: Allocator,
    options: Options,
    entries: std.ArrayListUnmanaged(Entry) = .{},
    generation: u64 = 0,

    pub fn init(allocator: Allocator, options: Options) PlanCache {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn deinit(self: *PlanCache) void {
        self.entries.deinit(self.allocator);
    }

    pub fn put(self: *PlanCache, plan_id: u64, prepared: PreparedPlanCache) !void {
        if (self.options.max_entries == 0) {
            return error.PlanCacheDisabled;
        }

        for (self.entries.items) |*entry| {
            if (entry.plan_id == plan_id) {
                entry.prepared = prepared;
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
            .prepared = prepared,
        });
        self.generation += 1;
    }

    pub fn get(self: *PlanCache, plan_id: u64) ?*Entry {
        for (self.entries.items) |*entry| {
            if (entry.plan_id == plan_id) {
                return entry;
            }
        }
        return null;
    }

    pub fn markRun(self: *PlanCache, plan_id: u64) bool {
        const entry = self.get(plan_id) orelse return false;
        entry.run_count += 1;
        return true;
    }

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
    try std.testing.expectEqual(@as(u32, 12), entry.prepared.measurement_capacity);
}
