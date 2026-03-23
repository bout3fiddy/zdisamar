//! Purpose:
//!   Expose the runtime thread-context type used by batch execution.
//!
//! Physics:
//!   A thread context is the same execution-reuse contract as a workspace: plan binding, scratch
//!   reservation, and reset semantics all remain identical.
//!
//! Vendor:
//!   `thread/workspace execution context`
//!
//! Design:
//!   Alias `Workspace` directly instead of duplicating the lifecycle type so thread and
//!   single-request execution stay behaviorally identical.
//!
//! Invariants:
//!   Thread contexts and workspaces share the same binding and reset rules.
//!
//! Validation:
//!   The aliasing test in this file plus batch-runner tests that reuse the thread context across
//!   multiple plan ids.

const std = @import("std");
const PreparedLayout = @import("../cache/PreparedLayout.zig").PreparedLayout;
const Workspace = @import("../../core/Workspace.zig").Workspace;

// DECISION:
//   Thread execution reuses the exact `Workspace` semantics rather than introducing a parallel
//   thread-specific lifecycle type.
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
