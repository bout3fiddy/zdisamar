const std = @import("std");
const PreparedPlanCache = @import("../cache/PreparedPlanCache.zig").PreparedPlanCache;
const ScratchArena = @import("ScratchArena.zig").ScratchArena;

const Allocator = std.mem.Allocator;

pub const ThreadContext = struct {
    allocator: Allocator,
    label: []const u8,
    scratch: ScratchArena = .{},
    bound_plan_id: ?u64 = null,
    execution_count: u64 = 0,
    reset_count: u64 = 0,

    pub fn init(allocator: Allocator, label: []const u8) !ThreadContext {
        if (label.len == 0) {
            return error.InvalidThreadLabel;
        }

        return .{
            .allocator = allocator,
            .label = try allocator.dupe(u8, label),
        };
    }

    pub fn deinit(self: *ThreadContext) void {
        self.allocator.free(self.label);
    }

    pub fn beginExecution(self: *ThreadContext, plan_id: u64, prepared: *const PreparedPlanCache) !void {
        if (self.bound_plan_id) |bound| {
            if (bound != plan_id) {
                return error.ThreadPlanMismatch;
            }
        } else {
            self.bound_plan_id = plan_id;
        }

        self.scratch.reserveFromPrepared(prepared);
        self.execution_count += 1;
    }

    pub fn reset(self: *ThreadContext) void {
        self.bound_plan_id = null;
        self.scratch.reset();
        self.reset_count += 1;
    }
};

test "thread context enforces plan binding and reset semantics" {
    var thread = try ThreadContext.init(std.testing.allocator, "thread-0");
    defer thread.deinit();

    const prepared: PreparedPlanCache = .{
        .layout_requirements = .{
            .spectral_start_nm = 400.0,
            .spectral_end_nm = 410.0,
            .spectral_sample_count = 8,
            .layer_count = 12,
            .state_parameter_count = 2,
            .measurement_count = 8,
        },
        .measurement_capacity = 8,
    };

    try thread.beginExecution(7, &prepared);
    try thread.beginExecution(7, &prepared);
    try std.testing.expectEqual(@as(u64, 2), thread.execution_count);
    try std.testing.expectEqual(@as(?u64, 7), thread.bound_plan_id);

    try std.testing.expectError(error.ThreadPlanMismatch, thread.beginExecution(9, &prepared));

    thread.reset();
    try std.testing.expectEqual(@as(?u64, null), thread.bound_plan_id);
    try std.testing.expectEqual(@as(u64, 1), thread.reset_count);
    try std.testing.expectEqual(@as(u64, 1), thread.scratch.reset_count);
}
