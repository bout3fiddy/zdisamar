const std = @import("std");

const internal = @import("internal");

const controls = internal.transport.controls;
const jacobian_states = internal.transport.jacobian_states;
const instrument_average = internal.spectrum.instrument_average;
const radiance_results = internal.spectrum.radiance_results;

test "assembleReflectance converts calibrated radiance and irradiance to reflectance" {
    const solar_cosine = 0.5;
    const radiance = [_]f64{ 2.0, 4.0 };
    const irradiance = [_]f64{ 8.0, 16.0 };
    var reflectance = [_]f64{0.0} ** 2;

    const summary = try instrument_average.assembleReflectance(
        solar_cosine,
        radiance[0..],
        irradiance[0..],
        reflectance[0..],
    );

    try std.testing.expectApproxEqAbs(std.math.pi * 2.0 / 4.0, reflectance[0], 1.0e-15);
    try std.testing.expectApproxEqAbs(std.math.pi * 4.0 / 8.0, reflectance[1], 1.0e-15);
    try std.testing.expectEqual(@as(usize, 2), summary.sample_count);
    try std.testing.expectEqual(@as(usize, 0), summary.denominator_clamp_count);
    try std.testing.expectApproxEqAbs(6.0, summary.radiance_sum, 0.0);
    try std.testing.expectApproxEqAbs(24.0, summary.irradiance_sum, 0.0);
    try std.testing.expectApproxEqAbs(4.0, summary.min_denominator, 0.0);
    try std.testing.expectApproxEqAbs(reflectance[1], summary.max_reflectance, 0.0);
}

test "assembleReflectance keeps old denominator floor and clamp summary" {
    const radiance = [_]f64{ 1.0, 2.0 };
    const irradiance = [_]f64{ 0.0, 2.0e-9 };
    var reflectance = [_]f64{0.0} ** 2;

    const summary = try instrument_average.assembleReflectance(
        0.5,
        radiance[0..],
        irradiance[0..],
        reflectance[0..],
    );

    try std.testing.expectApproxEqAbs(
        std.math.pi / instrument_average.reflectance_denominator_floor,
        reflectance[0],
        0.0,
    );
    try std.testing.expectApproxEqAbs(
        2.0 * std.math.pi / instrument_average.reflectance_denominator_floor,
        reflectance[1],
        0.0,
    );
    try std.testing.expectEqual(@as(usize, 2), summary.denominator_clamp_count);
    try std.testing.expectApproxEqAbs(0.0, summary.min_denominator, 0.0);
    try std.testing.expectApproxEqAbs(reflectance[1], summary.max_reflectance, 0.0);
}

test "assembleReflectanceResults scales active radiance Jacobian lanes into reflectance units" {
    const mask = jacobian_states.stateMask(.surface_albedo) |
        jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa);
    const radiance = [_]radiance_results.RadianceResult{
        .{ .radiance = 2.0, .jacobian = .{ 0.25, 25.0, 250.0 } },
        .{ .radiance = 4.0, .jacobian = .{ 0.5, 50.0, 500.0 } },
    };
    const irradiance = [_]f64{ 8.0, 16.0 };
    var reflectance = [_]f64{0.0} ** 2;
    var jacobian = [_]jacobian_states.Vector{jacobian_states.zero()} ** 2;

    const summary = try instrument_average.assembleReflectanceResults(
        controls.SolveConfig{
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = mask,
        },
        0.5,
        radiance[0..],
        irradiance[0..],
        reflectance[0..],
        jacobian[0..],
    );

    const scale0 = std.math.pi / (8.0 * 0.5);
    const scale1 = std.math.pi / (16.0 * 0.5);
    try std.testing.expectApproxEqAbs(2.0 * scale0, reflectance[0], 1.0e-15);
    try std.testing.expectApproxEqAbs(4.0 * scale1, reflectance[1], 1.0e-15);
    try std.testing.expectApproxEqAbs(0.25 * scale0, jacobian[0][0], 1.0e-15);
    try std.testing.expectApproxEqAbs(0.0, jacobian[0][1], 0.0);
    try std.testing.expectApproxEqAbs(250.0 * scale0, jacobian[0][2], 1.0e-13);
    try std.testing.expectApproxEqAbs(0.5 * scale1, jacobian[1][0], 1.0e-15);
    try std.testing.expectApproxEqAbs(0.0, jacobian[1][1], 0.0);
    try std.testing.expectApproxEqAbs(500.0 * scale1, jacobian[1][2], 1.0e-13);
    try std.testing.expectApproxEqAbs(jacobian[0][0] + jacobian[1][0], summary.jacobian_sum[0], 1.0e-15);
    try std.testing.expectApproxEqAbs(0.0, summary.jacobian_sum[1], 0.0);
    try std.testing.expectApproxEqAbs(jacobian[0][2] + jacobian[1][2], summary.jacobian_sum[2], 1.0e-13);
}

test "assembleReflectanceResults requires output rows for requested Jacobians" {
    const radiance = [_]radiance_results.RadianceResult{
        .{ .radiance = 1.0, .jacobian = .{ 1.0, 2.0, 3.0 } },
    };
    const irradiance = [_]f64{2.0};
    var reflectance = [_]f64{0.0};
    var short_jacobian = [_]jacobian_states.Vector{};

    try std.testing.expectError(
        error.ShapeMismatch,
        instrument_average.assembleReflectanceResults(
            .{
                .derivative_mode = .semi_analytical,
                .derivative_state_mask = jacobian_states.stateMask(.aerosol_optical_depth),
            },
            1.0,
            radiance[0..],
            irradiance[0..],
            reflectance[0..],
            short_jacobian[0..],
        ),
    );
}

test "assembleReflectanceResults zeros provided Jacobian rows when derivative mode is off" {
    const radiance = [_]radiance_results.RadianceResult{
        .{ .radiance = 1.0, .jacobian = .{ 1.0, 2.0, 3.0 } },
        .{ .radiance = 2.0, .jacobian = .{ 4.0, 5.0, 6.0 } },
    };
    const irradiance = [_]f64{ 10.0, 20.0 };
    var reflectance = [_]f64{0.0} ** 2;
    var jacobian = [_]jacobian_states.Vector{
        .{ 9.0, 9.0, 9.0 },
        .{ 8.0, 8.0, 8.0 },
    };

    const summary = try instrument_average.assembleReflectanceResults(
        .{
            .derivative_mode = .none,
            .derivative_state_mask = jacobian_states.all_states_mask,
        },
        1.0,
        radiance[0..],
        irradiance[0..],
        reflectance[0..],
        jacobian[0..],
    );

    try std.testing.expectEqual(jacobian_states.zero(), jacobian[0]);
    try std.testing.expectEqual(jacobian_states.zero(), jacobian[1]);
    try std.testing.expectEqual(jacobian_states.zero(), summary.jacobian_sum);
}

test "assembleReflectance returns zero extrema for empty spectra" {
    const empty = [_]f64{};
    var reflectance = [_]f64{};

    const summary = try instrument_average.assembleReflectance(
        1.0,
        empty[0..],
        empty[0..],
        reflectance[0..],
    );

    try std.testing.expectEqual(@as(usize, 0), summary.sample_count);
    try std.testing.expectEqual(@as(usize, 0), summary.denominator_clamp_count);
    try std.testing.expectApproxEqAbs(0.0, summary.min_denominator, 0.0);
    try std.testing.expectApproxEqAbs(0.0, summary.max_reflectance, 0.0);
}

test "assembleReflectance rejects invalid shapes and solar cosine" {
    const one = [_]f64{1.0};
    const two = [_]f64{ 1.0, 2.0 };
    var out = [_]f64{0.0};

    try std.testing.expectError(
        error.ShapeMismatch,
        instrument_average.assembleReflectance(1.0, one[0..], two[0..], out[0..]),
    );
    try std.testing.expectError(
        error.InvalidSolarCosine,
        instrument_average.assembleReflectance(std.math.nan(f64), one[0..], one[0..], out[0..]),
    );
}
