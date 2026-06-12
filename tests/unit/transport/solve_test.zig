const std = @import("std");

const internal = @import("internal");

const controls = internal.transport.controls;
const jacobian_states = internal.transport.jacobian_states;
const layer_depths = internal.optics.layer_depths;
const solve = internal.transport.solve;

test "direct surface solve ports old scalar formula and surface Jacobian" {
    var work = solve.TransportWorkArrays{};
    const layers = [_]layer_depths.LayerOptics{
        .{ .total_optical_depth = 0.12 },
        .{ .total_optical_depth = 0.08 },
    };
    const angles = solve.ViewAngles{
        .solar_mu = 0.5,
        .view_mu = 0.25,
    };
    const config = controls.SolveConfig{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.surface_albedo),
        .controls = .{ .scattering = .none },
    };
    const result = try solve.solveReflectance(
        angles,
        0.3,
        &layers,
        &.{},
        &.{},
        config,
        &work,
    );
    const direct = std.math.exp(-0.2 / 0.5) * std.math.exp(-0.2 / 0.25);

    try std.testing.expectApproxEqAbs(0.3 * direct, result.reflectance, 1.0e-15);
    try std.testing.expectApproxEqAbs(
        direct,
        jacobian_states.get(result.jacobian, .surface_albedo),
        1.0e-15,
    );
    try std.testing.expectEqual(@as(f64, 0.0), jacobian_states.get(result.jacobian, .aerosol_optical_depth));
}

test "direct surface solve respects active Jacobian mask and public clamp" {
    const masked = solve.directSurfaceOnly(
        .{ .solar_mu = 1.0, .view_mu = 1.0 },
        0.3,
        0.0,
        .semi_analytical,
        jacobian_states.stateMask(.aerosol_optical_depth),
    );
    const clamped = solve.directSurfaceOnly(
        .{ .solar_mu = 1.0, .view_mu = 1.0 },
        3.0,
        0.0,
        .semi_analytical,
        jacobian_states.stateMask(.surface_albedo),
    );

    try std.testing.expectEqual(@as(f64, 0.3), masked.reflectance);
    try std.testing.expectEqual(@as(f64, 0.0), jacobian_states.get(masked.jacobian, .surface_albedo));
    try std.testing.expectEqual(@as(f64, 2.0), clamped.reflectance);
    try std.testing.expectEqual(@as(f64, 0.0), jacobian_states.get(clamped.jacobian, .surface_albedo));
}

test "solveReflectance rejects enabled LABOS physics until Fourier route is wired" {
    var work = solve.TransportWorkArrays{};

    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        solve.solveReflectance(
            .{ .solar_mu = 0.5, .view_mu = 0.25 },
            0.3,
            &.{},
            &.{},
            &.{},
            .{ .controls = .{ .scattering = .multiple } },
            &work,
        ),
    );
    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        solve.solveReflectance(
            .{ .solar_mu = 0.5, .view_mu = 0.25 },
            0.3,
            &.{},
            &.{},
            &.{},
            .{ .controls = .{ .scattering = .none, .use_spherical_correction = true } },
            &work,
        ),
    );
}

test "solve route rows keep explicit layout" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(solve.ViewAngles));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(solve.ReflectanceResult));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(solve.TransportWorkArrays));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(solve.ViewAngles, "solar_mu"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(solve.ViewAngles, "view_mu"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(solve.ViewAngles, "relative_azimuth_rad"));
}
