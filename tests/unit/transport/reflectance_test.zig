const std = @import("std");

const internal = @import("internal");

const controls = internal.transport.controls;
const gauss_angles = internal.transport.gauss_angles;
const reflectance = internal.transport.reflectance;
const rows = internal.transport.rows;
const sensitivity = internal.instrumentation.sensitivity;

test "top reflectance coefficient reads solar column at viewing stream" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    var fields = zeroFields(3, geometry.stream_count);
    const top_level: usize = 2;
    const expected = 0.0375;
    fields[top_level].U.col[1].set(geometry.viewIndex(), expected);
    fields[top_level].U.col[0].set(geometry.viewIndex(), -9.0);
    fields[top_level].U.col[1].set(geometry.solarIndex(), 12.0);

    try std.testing.expectEqual(
        expected,
        reflectance.topReflectanceCoefficient(&fields, top_level, &geometry),
    );
}

test "Fourier contribution applies old azimuthal weight and tail floor" {
    const thresholds = controls.PerformanceThresholds{
        .fourier_tail_reflectance_epsilon = 1.0e-6,
        .fourier_floor_scalar = 2,
    };
    const contribution = reflectance.weightedFourierContribution(
        3,
        0.25,
        0.125,
        thresholds,
    );
    const expected_weight = 2.0 * std.math.cos(3.0 * 0.25);

    try std.testing.expectApproxEqAbs(expected_weight, contribution.weight, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.125, contribution.rho_m, 0.0);
    try std.testing.expectApproxEqAbs(expected_weight * 0.125, contribution.weighted, 1.0e-15);
    try std.testing.expectEqual(false, contribution.tail_break);

    const tail = reflectance.weightedFourierContribution(2, 0.25, -5.0e-7, thresholds);
    try std.testing.expectEqual(true, tail.tail_break);
    try std.testing.expectApproxEqAbs(2.0 * std.math.cos(0.5), tail.weight, 1.0e-15);
}

test "Fourier zero weight and floor prevent early tail stop" {
    const thresholds = controls.PerformanceThresholds{
        .fourier_tail_reflectance_epsilon = 1.0e-6,
        .fourier_floor_scalar = 2,
    };
    const coord = sensitivity.Coord{ .fourier_index = 1 };

    try std.testing.expectEqual(@as(f64, 1.0), reflectance.fourierWeight(0, 1.25));
    try std.testing.expectEqual(
        false,
        reflectance.fourierTailBreak(1, 1.0e-12, thresholds, coord),
    );
}

test "surface albedo weighting integrates direct and diffuse surface fields" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    var fields = zeroFields(2, geometry.stream_count);
    const surface_level: usize = 0;
    fields[surface_level].E.set(geometry.viewIndex(), 0.71);
    fields[surface_level].E.set(geometry.solarIndex(), 0.64);

    var diffuse_view: f64 = 0.0;
    var diffuse_solar: f64 = 0.0;
    for (0..geometry.n_gauss) |gauss_index| {
        const view_value = 0.01 * @as(f64, @floatFromInt(gauss_index + 1));
        const solar_value = 0.015 * @as(f64, @floatFromInt(gauss_index + 2));
        fields[surface_level].D.col[0].set(gauss_index, view_value);
        fields[surface_level].D.col[1].set(gauss_index, solar_value);
        diffuse_view += view_value * geometry.w[gauss_index];
        diffuse_solar += solar_value * geometry.w[gauss_index];
    }

    const expected = (0.71 + diffuse_view) * (0.64 + diffuse_solar);
    try std.testing.expectApproxEqAbs(
        expected,
        reflectance.surfaceAlbedoWeighting(&fields, &geometry),
        1.0e-15,
    );
}

test "public reflectance clamp keeps old output range" {
    try std.testing.expectEqual(@as(f64, 0.0), reflectance.clampPublicReflectance(-0.25));
    try std.testing.expectEqual(@as(f64, 0.5), reflectance.clampPublicReflectance(0.5));
    try std.testing.expectEqual(@as(f64, 2.0), reflectance.clampPublicReflectance(2.5));
}

fn zeroFields(level_count: usize, stream_count: usize) [3]rows.UDField {
    // zeroFields -------------------------------------------------------------------------------------------- |
    // Build zeroed U/D/E rows for reflectance helper tests.                                                   |
    // --------------------------------------------------------------------------------------------------------|
    var fields: [3]rows.UDField = undefined;
    for (0..level_count) |level| {
        fields[level] = .{
            .E = rows.Vec.zero(stream_count),
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
    }
    return fields;
}
