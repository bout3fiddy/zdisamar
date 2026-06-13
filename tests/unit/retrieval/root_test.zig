const std = @import("std");
const internal = @import("internal");

const algebra = internal.retrieval.algebra;
const retrieval = internal.retrieval.root;

test "native retrieval layouts match canonical optimal-estimation value owners" {
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(retrieval.StateSpec));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(retrieval.PressureAltitudeProfile));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(retrieval.MeasuredReflectanceRows));
    try std.testing.expectEqual(@as(usize, 256), @sizeOf(retrieval.RetrievalIterationScratch));
    try std.testing.expectEqual(@as(usize, 184), @sizeOf(retrieval.Result));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(retrieval.BatchResult));
    try std.testing.expectEqual(@as(usize, 120), @sizeOf(retrieval.BatchOutput));
    try std.testing.expectEqual(@as(usize, 168), @sizeOf(retrieval.FastmodeBatchResult));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(retrieval.Controls));
    try std.testing.expectEqual(@as(usize, 88), @sizeOf(retrieval.StateSpace));
}

test "pressure profile validates two-point samples before linear log-pressure shortcut" {
    try std.testing.expectError(
        error.InvalidPressureProfile,
        retrieval.buildPressureProfile(
            std.testing.allocator,
            &.{ 0.0, 1.0 },
            &.{ 900.0, 950.0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidPressureProfile,
        retrieval.buildPressureProfile(
            std.testing.allocator,
            &.{ 0.0, 0.0 },
            &.{ 900.0, 800.0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidPressureProfile,
        retrieval.buildPressureProfile(
            std.testing.allocator,
            &.{ 0.0, 1.0 },
            &.{ 900.0, -1.0 },
        ),
    );

    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    const profile = try retrieval.buildPressureProfile(
        std.testing.allocator,
        &altitude_km,
        &pressure_hpa,
    );
    defer retrieval.freePressureProfile(std.testing.allocator, profile);

    try std.testing.expectEqual(@as(usize, 2), profile.second.len);
    try std.testing.expectEqual(@as(f64, 0.0), profile.second[0]);
    try std.testing.expectEqual(@as(f64, 0.0), profile.second[1]);
}

test "pressure profile derivative matches the canonical expectation two-point log-pressure route" {
    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    const profile = try retrieval.buildPressureProfile(
        std.testing.allocator,
        &altitude_km,
        &pressure_hpa,
    );
    defer retrieval.freePressureProfile(std.testing.allocator, profile);

    const pressure = 850.0;
    const step = @max(@abs(pressure) * 1.0e-4, 1.0e-3);
    const log_span = @log(pressure_hpa[1]) - @log(pressure_hpa[0]);
    const expected =
        ((@log(pressure + step) - @log(pressure_hpa[0])) / log_span) -
        ((@log(pressure - step) - @log(pressure_hpa[0])) / log_span);

    try std.testing.expectApproxEqAbs(
        expected / (2.0 * step),
        try profile.altitudeDerivativeAtPressure(pressure),
        2.0e-13,
    );
}

test "measured reflectance rows copy sorted finite samples and invert variance" {
    var measurements = try retrieval.MeasuredReflectanceRows.init(
        std.testing.allocator,
        &.{ 758.0, 760.0, 765.0 },
        &.{ 0.10, 0.20, 0.30 },
        &.{ 4.0, 2.0, 0.5 },
    );
    defer measurements.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(f64, &.{ 758.0, 760.0, 765.0 }, measurements.wavelength_nm);
    try std.testing.expectEqualSlices(f64, &.{ 0.10, 0.20, 0.30 }, measurements.reflectance);
    try std.testing.expectEqualSlices(f64, &.{ 0.25, 0.5, 2.0 }, measurements.inv_variance);
}

test "measured reflectance rows reject unsorted or invalid samples" {
    try std.testing.expectError(
        error.InvalidMeasurement,
        retrieval.MeasuredReflectanceRows.init(
            std.testing.allocator,
            &.{ 758.0, 758.0 },
            &.{ 0.10, 0.20 },
            &.{ 1.0, 1.0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidMeasurement,
        retrieval.MeasuredReflectanceRows.init(
            std.testing.allocator,
            &.{ 758.0, 760.0 },
            &.{ 0.10, 0.20 },
            &.{ 1.0, 0.0 },
        ),
    );
}

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
