const std = @import("std");
const zdisamar = @import("zdisamar");
const retrieval = @import("retrieval");

test "retrieval solvers share canonical problem model with method-specific policy" {
    const request = zdisamar.Request{
        .scene = .{
            .id = "scene-retrieval-integration",
            .spectral_grid = .{ .sample_count = 40 },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-integration",
            .state_vector = .{
                .parameter_names = &[_][]const u8{ "a", "b" },
                .value_count = 2,
            },
            .measurements = .{
                .product = "radiance",
                .sample_count = 40,
            },
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };
    const base_problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(request);

    const oe_result = try retrieval.oe.solver.solve(base_problem);
    try std.testing.expectEqual(retrieval.common.contracts.Method.oe, oe_result.method);
    try std.testing.expect(oe_result.jacobians_used);

    var doas_problem = base_problem;
    doas_problem.derivative_mode = .none;
    doas_problem.jacobians_requested = false;
    const doas_result = try retrieval.doas.solver.solve(doas_problem);
    try std.testing.expectEqual(retrieval.common.contracts.Method.doas, doas_result.method);
    try std.testing.expect(!doas_result.jacobians_used);

    const dismas_result = try retrieval.dismas.solver.solve(base_problem);
    try std.testing.expectEqual(retrieval.common.contracts.Method.dismas, dismas_result.method);
    try std.testing.expect(dismas_result.jacobians_used);

    try std.testing.expectEqualStrings(oe_result.scene_id, doas_result.scene_id);
    try std.testing.expectEqualStrings(oe_result.scene_id, dismas_result.scene_id);
}
