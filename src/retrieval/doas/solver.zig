const std = @import("std");
const common = @import("../common/contracts.zig");

pub fn solve(problem: common.RetrievalProblem) common.Error!common.SolverOutcome {
    try problem.validateForMethod(.doas);

    const sample_count: f64 = @floatFromInt(problem.inverse_problem.measurements.sample_count);
    const cost = 1.0 / (sample_count + 1.0);
    const jacobians_used = problem.derivative_mode != .none and problem.jacobians_requested;

    return common.outcome(
        problem,
        .doas,
        2,
        cost,
        true,
        jacobians_used,
    );
}

test "doas retrieval can run without derivative mode" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-doas",
            .spectral_grid = .{ .sample_count = 24 },
        },
        .inverse_problem = .{
            .id = "inverse-doas",
            .state_vector = .{
                .parameter_names = &[_][]const u8{"slant_column"},
                .value_count = 1,
            },
            .measurements = .{
                .product = "slant_column",
                .sample_count = 24,
            },
        },
        .derivative_mode = .none,
        .jacobians_requested = false,
    };

    const result = try solve(problem);
    try std.testing.expectEqual(common.Method.doas, result.method);
    try std.testing.expect(!result.jacobians_used);
    try std.testing.expect(result.converged);
}
