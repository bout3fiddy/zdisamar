const std = @import("std");
const PreparedLayout = @import("../cache/PreparedLayout.zig").PreparedLayout;
const Workspace = @import("../../core/Workspace.zig").Workspace;

pub const ThreadContext = Workspace;

test "thread context aliases the shared workspace execution semantics" {
    var thread = Workspace.init("thread-0");
    const prepared_layout: PreparedLayout = .{
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

    try thread.beginExecution(7);
    thread.prepareScratch(&prepared_layout);
    try thread.beginExecution(7);
    thread.prepareScratch(&prepared_layout);
    try std.testing.expectEqual(@as(u64, 2), thread.execution_count);
    try std.testing.expectEqual(@as(?u64, 7), thread.bound_plan_id);

    try std.testing.expectError(error.WorkspacePlanMismatch, thread.beginExecution(9));

    thread.reset();
    try std.testing.expectEqual(@as(?u64, null), thread.bound_plan_id);
    try std.testing.expectEqual(@as(u64, 1), thread.reset_count);
    try std.testing.expectEqual(@as(u64, 1), thread.scratch.reset_count);
}
