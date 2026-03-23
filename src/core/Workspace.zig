//! Purpose:
//!   Track per-workspace execution reuse and scratch-allocation state.
//!
//! Physics:
//!   A workspace represents execution-local storage reused across repeated forward/retrieval
//!   evaluations for the same prepared plan.
//!
//! Vendor:
//!   `workspace reuse and scratch reservation`
//!
//! Design:
//!   Workspaces keep the plan binding explicit and delegate actual buffer sizing/reuse to the
//!   scheduler scratch arena.
//!
//! Invariants:
//!   A workspace may only execute requests for one bound plan until reset. Scratch reservation is
//!   derived from the prepared layout associated with that plan.
//!
//! Validation:
//!   Engine execution and scheduler tests that reuse workspaces across repeated plan execution.

const errors = @import("errors.zig");
const PreparedLayout = @import("../runtime/cache/PreparedLayout.zig").PreparedLayout;
const ScratchArena = @import("../runtime/scheduler/ScratchArena.zig").ScratchArena;

/// Purpose:
///   Hold reusable execution counters, plan binding, and scratch buffers for one workspace.
pub const Workspace = struct {
    label: []const u8,
    reset_count: u64 = 0,
    execution_count: u64 = 0,
    bound_plan_id: ?u64 = null,
    scratch: ScratchArena = .{},

    pub fn init(label: []const u8) Workspace {
        return .{ .label = label };
    }

    /// Purpose:
    ///   Bind the workspace to a prepared plan and advance the execution counter.
    pub fn beginExecution(self: *Workspace, plan_id: u64) errors.Error!void {
        if (self.bound_plan_id) |bound| {
            if (bound != plan_id) {
                return errors.Error.WorkspacePlanMismatch;
            }
        } else {
            // INVARIANT:
            //   The first execution fixes the workspace to one plan until `reset` clears the
            //   binding explicitly.
            self.bound_plan_id = plan_id;
        }

        self.execution_count += 1;
    }

    /// Purpose:
    ///   Reserve scratch storage according to the prepared layout for the bound plan.
    pub fn prepareScratch(self: *Workspace, prepared_layout: *const PreparedLayout) void {
        self.scratch.reserveFromLayout(prepared_layout);
    }

    /// Purpose:
    ///   Clear plan binding and scratch state so the workspace can be reused for another plan.
    pub fn reset(self: *Workspace) void {
        self.reset_count += 1;
        self.execution_count = 0;
        self.bound_plan_id = null;
        self.scratch.reset();
    }
};
