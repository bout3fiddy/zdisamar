const common = @import("../../retrieval/common/contracts.zig");
const forward_model = @import("../../retrieval/common/forward_model.zig");
const SolverOutcome = common.SolverOutcome;
const doas = @import("../../retrieval/doas/solver.zig");
const dismas = @import("../../retrieval/dismas/solver.zig");
const oe = @import("../../retrieval/oe/solver.zig");

pub const Provider = struct {
    id: []const u8,
    solve: *const fn (problem: common.RetrievalProblem, evaluator: forward_model.SummaryEvaluator) anyerror!SolverOutcome,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.oe_solver")) {
        return .{
            .id = provider_id,
            .solve = oe.solveWithEvaluator,
        };
    }
    if (std.mem.eql(u8, provider_id, "builtin.doas_solver")) {
        return .{
            .id = provider_id,
            .solve = doas.solveWithEvaluator,
        };
    }
    if (std.mem.eql(u8, provider_id, "builtin.dismas_solver")) {
        return .{
            .id = provider_id,
            .solve = dismas.solveWithEvaluator,
        };
    }
    return null;
}

const std = @import("std");
