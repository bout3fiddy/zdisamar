const PlanModule = @import("../../core/Plan.zig");
const Result = @import("../../core/Result.zig").Result;

pub const abi_version: u32 = 1;

pub const SolverMode = enum(u32) {
    scalar = 0,
    polarized = 1,
    derivative_enabled = 2,
};

pub const PlanDesc = extern struct {
    model_family: [*:0]const u8,
    transport_solver: [*:0]const u8,
    retrieval_algorithm: ?[*:0]const u8 = null,
    solver_mode: SolverMode = .scalar,
};

pub const ResultDesc = extern struct {
    plan_id: u64,
    status: u32,
};

pub fn toSolverMode(mode: PlanModule.SolverMode) SolverMode {
    return switch (mode) {
        .scalar => .scalar,
        .polarized => .polarized,
        .derivative_enabled => .derivative_enabled,
    };
}

pub fn describeResult(result: Result) ResultDesc {
    return .{
        .plan_id = result.plan_id,
        .status = switch (result.status) {
            .success => 0,
            .invalid_request => 1,
            .internal_error => 2,
        },
    };
}
