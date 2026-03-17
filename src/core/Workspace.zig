const errors = @import("errors.zig");
const PreparedLayout = @import("../runtime/cache/PreparedLayout.zig").PreparedLayout;
const ScratchArena = @import("../runtime/scheduler/ScratchArena.zig").ScratchArena;

pub const Workspace = struct {
    label: []const u8,
    reset_count: u64 = 0,
    execution_count: u64 = 0,
    bound_plan_id: ?u64 = null,
    scratch: ScratchArena = .{},

    pub fn init(label: []const u8) Workspace {
        return .{ .label = label };
    }

    pub fn beginExecution(self: *Workspace, plan_id: u64) errors.Error!void {
        if (self.bound_plan_id) |bound| {
            if (bound != plan_id) {
                return errors.Error.WorkspacePlanMismatch;
            }
        } else {
            self.bound_plan_id = plan_id;
        }

        self.execution_count += 1;
    }

    pub fn prepareScratch(self: *Workspace, prepared_layout: *const PreparedLayout) void {
        self.scratch.reserveFromLayout(prepared_layout);
    }

    pub fn reset(self: *Workspace) void {
        self.reset_count += 1;
        self.execution_count = 0;
        self.bound_plan_id = null;
        self.scratch.reset();
    }
};
