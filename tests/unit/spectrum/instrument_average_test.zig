const std = @import("std");

const internal = @import("internal");

const instrument_average = internal.spectrum.instrument_average;

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
