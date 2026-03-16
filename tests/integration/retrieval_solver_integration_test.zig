const std = @import("std");
const zdisamar = @import("zdisamar");
const retrieval = @import("retrieval");

test "retrieval solvers share canonical problem model with method-specific policy" {
    const oe_request = zdisamar.Request{
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
    const oe_problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(oe_request);

    const oe_result = try retrieval.oe.solver.solve(std.testing.allocator, oe_problem);
    defer {
        var owned = oe_result;
        owned.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(retrieval.common.contracts.Method.oe, oe_result.method);
    try std.testing.expect(oe_result.jacobians_used);

    const doas_problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(.{
        .scene = oe_request.scene,
        .inverse_problem = .{
            .id = "inverse-retrieval-doas",
            .state_vector = .{
                .parameter_names = &[_][]const u8{"slant_column"},
                .value_count = 1,
            },
            .measurements = .{
                .product = "slant_column",
                .sample_count = 40,
            },
        },
        .expected_derivative_mode = .none,
        .diagnostics = .{ .jacobians = false },
    });
    const doas_result = try retrieval.doas.solver.solve(std.testing.allocator, doas_problem);
    defer {
        var owned = doas_result;
        owned.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(retrieval.common.contracts.Method.doas, doas_result.method);
    try std.testing.expect(!doas_result.jacobians_used);

    const dismas_problem = try retrieval.common.contracts.RetrievalProblem.fromRequest(.{
        .scene = .{
            .id = "scene-retrieval-dismas",
            .observation_model = .{
                .instrument = "compatibility-harness",
                .regime = .limb,
                .sampling = "synthetic",
                .noise_model = "shot_noise",
            },
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 40 },
        },
        .inverse_problem = .{
            .id = "inverse-retrieval-dismas",
            .state_vector = .{
                .parameter_names = &[_][]const u8{ "state_a", "state_b", "state_c" },
                .value_count = 3,
            },
            .measurements = .{
                .product = "multi_band_signal",
                .sample_count = 40,
            },
        },
        .expected_derivative_mode = .numerical,
        .diagnostics = .{ .jacobians = true },
    });
    const dismas_result = try retrieval.dismas.solver.solve(std.testing.allocator, dismas_problem);
    defer {
        var owned = dismas_result;
        owned.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(retrieval.common.contracts.Method.dismas, dismas_result.method);
    try std.testing.expect(dismas_result.jacobians_used);

    try std.testing.expectEqualStrings(oe_result.scene_id, doas_result.scene_id);
    try std.testing.expectEqualStrings("scene-retrieval-dismas", dismas_result.scene_id);
}
