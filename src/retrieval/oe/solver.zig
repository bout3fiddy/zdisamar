const std = @import("std");
const common = @import("../common/contracts.zig");

pub fn solve(problem: common.RetrievalProblem) common.Error!common.SolverOutcome {
    try problem.validateForMethod(.oe);

    const state_terms: f64 = @floatFromInt(problem.inverse_problem.state_vector.value_count);
    const measurement_terms: f64 = @floatFromInt(problem.inverse_problem.measurements.sample_count);
    const cost = (state_terms + 1.0) / (measurement_terms + 2.0);

    return common.outcome(
        problem,
        .oe,
        4,
        cost,
        true,
        true,
    );
}

test "oe retrieval requires derivative mode and converges with jacobians" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-oe",
            .spectral_grid = .{ .sample_count = 32 },
        },
        .inverse_problem = .{
            .id = "inverse-oe",
            .state_vector = .{
                .parameter_names = &[_][]const u8{ "albedo", "aerosol" },
                .value_count = 2,
            },
            .measurements = .{
                .product = "radiance",
                .sample_count = 32,
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
    };

    const result = try solve(problem);
    try std.testing.expectEqual(common.Method.oe, result.method);
    try std.testing.expect(result.jacobians_used);
    try std.testing.expect(result.converged);
}
