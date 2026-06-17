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

    const pressure_altitude_profile = retrieval.PressureAltitudeProfile{
        .altitude_km = &.{ 0.0, 1.0 },
        .pressure_hpa = &.{ 900.0, 800.0 },
        .second = &.{ 0.0, 0.0 },
    };
    const retrieval_state: retrieval.RetrievalState = .{
        .aerosol_optical_depth = .{
            .initial = 0.3,
            .prior = 0.2,
            .variance = 4.0,
            .lower_bound = 0.0,
            .upper_bound = 1.0,
        },
        .aerosol_layer_mid_pressure = .{
            .scalar = .{
                .initial = 850.0,
                .prior = 850.0,
                .variance = 100.0,
                .lower_bound = 600.0,
                .upper_bound = 1000.0,
            },
            .placement = .{
                .thickness_hpa = 10.0,
                .interval_index_1based = 2,
                .pressure_altitude_profile = &pressure_altitude_profile,
            },
        },
    };
    var result = try retrieval.Result.init(std.testing.allocator, 1);
    defer result.deinit(std.testing.allocator);

    const state_space = try retrieval.initializeStateSpace(retrieval_state, &result);
    var scratch: retrieval.RetrievalIterationScratch = .{};
    try retrieval.preparePriorScales(state_space, &scratch);

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
        retrieval_state,
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
    try std.testing.expectEqual(.aerosol_layer_mid_pressure_hpa, result.state_ids[1]);
    try std.testing.expectApproxEqAbs(0.3, result.initial_state[0], 0.0);
    try std.testing.expectApproxEqAbs(850.0, result.initial_state[1], 0.0);
}

test "solve step keeps zero-residual state at the prior" {
    var scratch: retrieval.RetrievalIterationScratch = .{};
    scratch.dx_white = algebra.zeroVector();

    const step = try retrieval.solveStep(
        .{ .{ 2.0, 0.0 }, .{ 0.0, 3.0 } },
        .{ 0.0, 0.0 },
        .{ 0.3, 850.0 },
        .{ 2.0, 10.0 },
        .{ 0.5, 0.1 },
        1.0,
        &scratch,
    );

    try std.testing.expectApproxEqAbs(0.3, step.state[0], 0.0);
    try std.testing.expectApproxEqAbs(850.0, step.state[1], 0.0);
    try std.testing.expect(step.snr_normal);
    try std.testing.expectApproxEqAbs(0.75, step.posterior_precision[0][0], 1.0e-15);
    try std.testing.expectApproxEqAbs(0.04, step.posterior_precision[1][1], 1.0e-15);
}
