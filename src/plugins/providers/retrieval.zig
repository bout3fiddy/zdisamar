const common = @import("../../retrieval/common/contracts.zig");
const forward_model = @import("../../retrieval/common/forward_model.zig");
const SolverOutcome = common.SolverOutcome;
const doas = @import("../../retrieval/doas/solver.zig");
const dismas = @import("../../retrieval/dismas/solver.zig");
const oe = @import("../../retrieval/oe/solver.zig");
const Allocator = @import("std").mem.Allocator;

pub const Provider = struct {
    id: []const u8,
    solve: *const fn (allocator: Allocator, problem: common.RetrievalProblem, evaluator: forward_model.Evaluator) anyerror!SolverOutcome,
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

test "retrieval providers resolve real spectral DOAS and DISMAS solvers" {
    const doas_provider = resolve("builtin.doas_solver") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("builtin.doas_solver", doas_provider.id);
    try std.testing.expectEqual(@intFromPtr(&doas.solveWithEvaluator), @intFromPtr(doas_provider.solve));

    const dismas_provider = resolve("builtin.dismas_solver") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("builtin.dismas_solver", dismas_provider.id);
    try std.testing.expectEqual(@intFromPtr(&dismas.solveWithEvaluator), @intFromPtr(dismas_provider.solve));
}

test "retrieval providers quarantine surrogate-only names" {
    try std.testing.expect(resolve("builtin.surrogate_doas_solver") == null);
    try std.testing.expect(resolve("builtin.surrogate_dismas_solver") == null);
}
