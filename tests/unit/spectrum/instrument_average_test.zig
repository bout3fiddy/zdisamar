const std = @import("std");

const internal = @import("internal");

const controls = internal.transport.controls;
const jacobian_states = internal.transport.jacobian_states;
const instrument_average = internal.spectrum.instrument_average;
const radiance_results = internal.spectrum.radiance_results;

test "applySignal keeps old gain offset and stray-light calibration math" {
    const signal = [_]f64{ 2.0, 4.0, 10.0 };
    var output = [_]f64{0.0} ** signal.len;
    const calibration = instrument_average.Calibration{
        .gain = 1.5,
        .offset = -0.25,
        .stray_light = 0.2,
    };

    try instrument_average.applySignal(calibration, signal[0..], output[0..]);

    const signal_mean = (2.0 + 4.0 + 10.0) / 3.0;
    for (signal, output) |sample, actual| {
        const expected = calibration.gain * (sample + calibration.stray_light * (signal_mean - sample)) +
            calibration.offset;
        try std.testing.expectApproxEqAbs(expected, actual, 1.0e-15);
    }
}

test "applySignalDerivative omits additive offset and keeps stray-light derivative coupling" {
    const derivative = [_]f64{ -1.0, 3.0, 4.0 };
    var output = [_]f64{0.0} ** derivative.len;
    const calibration = instrument_average.Calibration{
        .gain = 2.0,
        .offset = 100.0,
        .stray_light = 0.25,
    };

    try instrument_average.applySignalDerivative(calibration, derivative[0..], output[0..]);

    const derivative_mean = (-1.0 + 3.0 + 4.0) / 3.0;
    for (derivative, output) |sample, actual| {
        const expected = calibration.gain * (sample + calibration.stray_light * (derivative_mean - sample));
        try std.testing.expectApproxEqAbs(expected, actual, 1.0e-15);
    }
}

test "applySlitConvolution uses clipped boundary normalization" {
    const signal = [_]f64{ 2.0, 4.0, 8.0, 16.0 };
    const kernel = [_]f64{ 1.0, 2.0, 1.0 };
    var output = [_]f64{0.0} ** signal.len;

    try instrument_average.applySlitConvolution(signal[0..], kernel[0..], output[0..]);

    for (output, 0..) |actual, index| {
        try std.testing.expectApproxEqAbs(
            expectedConvolutionSample(signal[0..], kernel[0..], index),
            actual,
            1.0e-15,
        );
    }
}

test "postprocessSignal skips convolution after integrated sampling then calibrates" {
    const signal = [_]f64{ 1.0, 3.0, 5.0 };
    var output = [_]f64{0.0} ** signal.len;
    const calibration = instrument_average.Calibration{
        .gain = 3.0,
        .offset = 1.0,
        .stray_light = 0.0,
    };

    try instrument_average.postprocessSignal(
        true,
        calibration,
        instrument_average.default_slit_kernel[0..],
        signal[0..],
        output[0..],
    );

    for (signal, output) |sample, actual| {
        try std.testing.expectApproxEqAbs(3.0 * sample + 1.0, actual, 1.0e-15);
    }
}

test "postprocessSignal rejects in-place non-integrated convolution" {
    var signal = [_]f64{ 1.0, 3.0, 5.0 };

    try std.testing.expectError(
        error.ShapeMismatch,
        instrument_average.postprocessSignal(
            false,
            .{},
            instrument_average.default_slit_kernel[0..],
            signal[0..],
            signal[0..],
        ),
    );
}

test "postprocessRadianceResults convolves and calibrates active row-vector Jacobian lanes" {
    const raw = [_]radiance_results.RadianceResult{
        .{ .radiance = 2.0, .jacobian = .{ 1.0, 10.0, 100.0 } },
        .{ .radiance = 4.0, .jacobian = .{ 2.0, 20.0, 200.0 } },
        .{ .radiance = 8.0, .jacobian = .{ 4.0, 40.0, 400.0 } },
        .{ .radiance = 16.0, .jacobian = .{ 8.0, 80.0, 800.0 } },
    };
    const kernel = [_]f64{ 1.0, 2.0, 1.0 };
    const calibration = instrument_average.Calibration{
        .gain = 2.0,
        .offset = 0.5,
        .stray_light = 0.25,
    };
    const mask = jacobian_states.stateMask(.surface_albedo) |
        jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa);
    var output = [_]radiance_results.RadianceResult{.{}} ** raw.len;

    try instrument_average.postprocessRadianceResults(
        .{
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = mask,
        },
        false,
        calibration,
        kernel[0..],
        raw[0..],
        output[0..],
    );

    var convolved_radiance: [raw.len]f64 = undefined;
    var convolved_surface: [raw.len]f64 = undefined;
    var convolved_pressure: [raw.len]f64 = undefined;
    for (0..raw.len) |index| {
        convolved_radiance[index] = expectedConvolutionRow(raw[0..], kernel[0..], index, .radiance, 0);
        convolved_surface[index] = expectedConvolutionRow(raw[0..], kernel[0..], index, .jacobian, 0);
        convolved_pressure[index] = expectedConvolutionRow(raw[0..], kernel[0..], index, .jacobian, 2);
    }

    for (output, 0..) |actual, index| {
        try std.testing.expectApproxEqAbs(
            expectedSignalCalibration(calibration, convolved_radiance[0..], index),
            actual.radiance,
            1.0e-15,
        );
        try std.testing.expectApproxEqAbs(
            expectedDerivativeCalibration(calibration, convolved_surface[0..], index),
            actual.jacobian[0],
            1.0e-15,
        );
        try std.testing.expectApproxEqAbs(0.0, actual.jacobian[1], 0.0);
        try std.testing.expectApproxEqAbs(
            expectedDerivativeCalibration(calibration, convolved_pressure[0..], index),
            actual.jacobian[2],
            1.0e-12,
        );
    }
}

test "postprocessRadianceResults permits in-place integrated sampling and zeros inactive lanes" {
    var rows = [_]radiance_results.RadianceResult{
        .{ .radiance = 1.0, .jacobian = .{ 2.0, 3.0, 4.0 } },
        .{ .radiance = 3.0, .jacobian = .{ 6.0, 9.0, 12.0 } },
    };
    const calibration = instrument_average.Calibration{
        .gain = 2.0,
        .offset = 1.0,
        .stray_light = 0.0,
    };

    try instrument_average.postprocessRadianceResults(
        .{
            .derivative_mode = .none,
            .derivative_state_mask = jacobian_states.all_states_mask,
        },
        true,
        calibration,
        instrument_average.default_slit_kernel[0..],
        rows[0..],
        rows[0..],
    );

    try std.testing.expectApproxEqAbs(3.0, rows[0].radiance, 1.0e-15);
    try std.testing.expectApproxEqAbs(7.0, rows[1].radiance, 1.0e-15);
    try std.testing.expectEqual(jacobian_states.zero(), rows[0].jacobian);
    try std.testing.expectEqual(jacobian_states.zero(), rows[1].jacobian);
}

test "postprocessRadianceResults rejects in-place non-integrated convolution" {
    var rows = [_]radiance_results.RadianceResult{
        .{ .radiance = 1.0 },
        .{ .radiance = 3.0 },
    };

    try std.testing.expectError(
        error.ShapeMismatch,
        instrument_average.postprocessRadianceResults(
            .{},
            false,
            .{},
            instrument_average.default_slit_kernel[0..],
            rows[0..],
            rows[0..],
        ),
    );
}

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

const ExpectedRowValue = enum {
    radiance,
    jacobian,
};

fn expectedMean(values: []const f64) f64 {
    // expectedMean ------------------------------------------------------------------------------------------ |
    // Test-local scalar mean used by independent calibration formulas.                                        |
    // --------------------------------------------------------------------------------------------------------|
    var total: f64 = 0.0;
    for (values) |value| total += value;
    return total / @as(f64, @floatFromInt(values.len));
}

fn expectedSignalCalibration(
    calibration: instrument_average.Calibration,
    signal: []const f64,
    index: usize,
) f64 {
    // expectedSignalCalibration ----------------------------------------------------------------------------- |
    // Test-local scalar formula for gain, offset, and stray-light mixing.                                     |
    // --------------------------------------------------------------------------------------------------------|
    const value = signal[index];
    return calibration.gain * (value + calibration.stray_light * (expectedMean(signal) - value)) +
        calibration.offset;
}

fn expectedDerivativeCalibration(
    calibration: instrument_average.Calibration,
    signal: []const f64,
    index: usize,
) f64 {
    // expectedDerivativeCalibration ------------------------------------------------------------------------- |
    // Test-local derivative calibration formula with no additive offset term.                                 |
    // --------------------------------------------------------------------------------------------------------|
    const value = signal[index];
    return calibration.gain * (value + calibration.stray_light * (expectedMean(signal) - value));
}

fn expectedConvolutionSample(signal: []const f64, kernel: []const f64, index: usize) f64 {
    // expectedConvolutionSample ----------------------------------------------------------------------------- |
    // Test-local clipped-kernel convolution for scalar slices.                                                |
    // --------------------------------------------------------------------------------------------------------|
    const half_width = kernel.len / 2;
    const kernel_start = if (index < half_width) half_width - index else 0;
    const kernel_end = @min(kernel.len, signal.len + half_width - index);

    var total: f64 = 0.0;
    var norm: f64 = 0.0;
    for (kernel_start..kernel_end) |kernel_index| {
        const signal_index = index + kernel_index - half_width;
        total += signal[signal_index] * kernel[kernel_index];
        norm += kernel[kernel_index];
    }
    return total / norm;
}

fn expectedConvolutionRow(
    rows: []const radiance_results.RadianceResult,
    kernel: []const f64,
    index: usize,
    value: ExpectedRowValue,
    state_index: usize,
) f64 {
    // expectedConvolutionRow -------------------------------------------------------------------------------- |
    // Test-local clipped-kernel convolution over row-vector radiance or one Jacobian lane.                    |
    // --------------------------------------------------------------------------------------------------------|
    const half_width = kernel.len / 2;
    const kernel_start = if (index < half_width) half_width - index else 0;
    const kernel_end = @min(kernel.len, rows.len + half_width - index);

    var total: f64 = 0.0;
    var norm: f64 = 0.0;
    for (kernel_start..kernel_end) |kernel_index| {
        const row_index = index + kernel_index - half_width;
        const sample = switch (value) {
            .radiance => rows[row_index].radiance,
            .jacobian => rows[row_index].jacobian[state_index],
        };
        total += sample * kernel[kernel_index];
        norm += kernel[kernel_index];
    }
    return total / norm;
}
