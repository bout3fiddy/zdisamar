const std = @import("std");
const common = @import("../common/contracts.zig");

pub fn solve(problem: common.RetrievalProblem) common.Error!common.SolverOutcome {
    try problem.validateForMethod(.dismas);

    const state_terms: f64 = @floatFromInt(problem.inverse_problem.state_vector.value_count);
    const measurement_terms: f64 = @floatFromInt(problem.inverse_problem.measurements.sample_count);
    const cost = (state_terms * 0.5) / (measurement_terms + 1.0);

    return common.outcome(
        problem,
        .dismas,
        5,
        cost,
        true,
        true,
    );
}

test "dismas retrieval requires explicit derivative mode" {
    const base_problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-dismas",
            .spectral_grid = .{ .sample_count = 20 },
        },
        .inverse_problem = .{
            .id = "inverse-dismas",
            .state_vector = .{
                .parameter_names = &[_][]const u8{ "state_a", "state_b", "state_c" },
                .value_count = 3,
            },
            .measurements = .{
                .product = "multi_band_signal",
                .sample_count = 20,
            },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
    };

    const ok = try solve(base_problem);
    try std.testing.expectEqual(common.Method.dismas, ok.method);
    try std.testing.expect(ok.jacobians_used);

    var missing_mode = base_problem;
    missing_mode.derivative_mode = .none;
    try std.testing.expectError(common.Error.DerivativeModeRequired, solve(missing_mode));
}
