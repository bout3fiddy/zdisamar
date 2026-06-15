const std = @import("std");
const internal = @import("internal");

const algebra = internal.retrieval.algebra;
const retrieval = internal.retrieval.root;

test "normal-system accumulation uses reflectance Jacobians directly" {
    var measurements = try retrieval.MeasuredReflectanceRows.init(
        std.testing.allocator,
        &.{ 758.0, 760.0 },
        &.{ 0.12, 0.18 },
        &.{ 0.25, 0.50 },
    );
    defer measurements.deinit(std.testing.allocator);

    const specs = [_]retrieval.StateSpec{
        .{
            .state = .aerosol_optical_depth,
            .initial = 0.3,
            .prior = 0.2,
            .variance = 4.0,
            .lower_bound = 0.0,
            .upper_bound = 1.0,
        },
    };
    var result = try retrieval.Result.init(std.testing.allocator, specs.len, 1);
    defer result.deinit(std.testing.allocator);

    const state_space = try retrieval.initializeStateSpace(&specs, &result);
    var scratch: retrieval.RetrievalIterationScratch = .{};
    try retrieval.preparePriorScales(state_space, specs.len, &scratch);

    const jacobian_rows = [_]internal.rtm.jacobian_states.Vector{
        .{ 0.5, 0.0 },
        .{ 0.25, 0.0 },
    };
    const accumulation = try retrieval.accumulateNormalSystem(
        measurements,
        .{
            .wavelength_nm = &.{ 758.0, 760.0 },
            .reflectance = &.{ 0.10, 0.20 },
            .jacobian = &jacobian_rows,
        },
        &specs,
        state_space.state,
        state_space.prior,
        scratch.sqrt_sa,
        &scratch,
    );

    try std.testing.expectApproxEqAbs(0.0024, accumulation.chi2_reflectance, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.05, scratch.dx_white[0], 1.0e-15);
    try std.testing.expectApproxEqAbs(0.06, scratch.b[0], 1.0e-15);
    try std.testing.expectApproxEqAbs(4.5, scratch.g[0][0], 1.0e-15);
    try std.testing.expectApproxEqAbs(1.125, accumulation.jt_invse_j[0][0], 1.0e-15);
    try std.testing.expectEqual(.aerosol_optical_depth, result.state_ids[0]);
    try std.testing.expectApproxEqAbs(0.3, result.initial_state[0], 0.0);
}

test "solve step keeps zero-residual state at the prior" {
    var scratch: retrieval.RetrievalIterationScratch = .{};
    scratch.dx_white = algebra.zeroVector();

    const step = try retrieval.solveStep(
        1,
        .{ .{ 2.0, 0.0 }, .{ 0.0, 0.0 } },
        .{ 0.0, 0.0 },
        .{ 0.3, 0.0 },
        .{ 2.0, 0.0 },
        .{ 0.5, 0.0 },
        1.0,
        &scratch,
    );

    try std.testing.expectApproxEqAbs(0.3, step.state[0], 0.0);
    try std.testing.expect(step.snr_normal);
    try std.testing.expectApproxEqAbs(0.75, step.posterior_precision[0][0], 1.0e-15);
}
