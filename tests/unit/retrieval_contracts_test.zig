const std = @import("std");
const zdisamar = @import("zdisamar");
const retrieval = @import("retrieval");

test "retrieval common contracts enforce derivative requirement by method" {
    const request = zdisamar.Request{
        .scene = .{
            .id = "scene-retrieval-unit",
            .atmosphere = .{ .layer_count = 10 },
            .spectral_grid = .{ .sample_count = 12 },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-unit",
            .state_vector = .{
                .parameter_names = &[_][]const u8{"x0"},
                .value_count = 1,
            },
            .measurements = .{
                .product = "radiance",
                .sample_count = 12,
            },
        },
        .expected_derivative_mode = .semi_analytical,
        .diagnostics = .{ .jacobians = true },
    };

    const base_problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(request);
    try base_problem.validateForMethod(.oe);

    const layout = base_problem.layoutRequirements();
    try std.testing.expectEqual(@as(u32, 10), layout.layer_count);
    try std.testing.expectEqual(@as(u32, 1), layout.state_parameter_count);
    try std.testing.expectEqual(@as(u32, 12), layout.measurement_count);

    var no_derivative = base_problem;
    no_derivative.derivative_mode = .none;
    no_derivative.jacobians_requested = true;
    try std.testing.expectError(
        retrieval.common.contracts.Error.DerivativeModeRequired,
        no_derivative.validateForMethod(.oe),
    );

    no_derivative.jacobians_requested = false;
    try no_derivative.validateForMethod(.doas);
}
