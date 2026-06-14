const std = @import("std");
const internal = @import("internal");

const metrics = internal.validation.band_metrics;

test "O2A band metrics preserve morphology windows and residual formulas" {
    const wavelengths = [_]f64{ 755.0, 758.0, 760.2, 760.6, 761.0, 762.0, 764.0, 765.0, 770.0 };
    const generated = [_]f64{ 0.51, 0.61, 0.41, 0.31, 0.36, 0.46, 0.56, 0.66, 0.76 };
    const reference = [_]metrics.ReferenceSample{
        .{ .wavelength_nm = 755.0, .reflectance = 0.50 },
        .{ .wavelength_nm = 758.0, .reflectance = 0.60 },
        .{ .wavelength_nm = 760.2, .reflectance = 0.40 },
        .{ .wavelength_nm = 760.6, .reflectance = 0.30 },
        .{ .wavelength_nm = 761.0, .reflectance = 0.35 },
        .{ .wavelength_nm = 762.0, .reflectance = 0.45 },
        .{ .wavelength_nm = 764.0, .reflectance = 0.55 },
        .{ .wavelength_nm = 765.0, .reflectance = 0.65 },
        .{ .wavelength_nm = 770.0, .reflectance = 0.75 },
    };

    const result = try metrics.computeComparisonMetrics(
        wavelengths[0..],
        generated[0..],
        reference[0..],
        0.005,
    );

    try std.testing.expectEqual(@as(usize, 9), result.sample_count);
    try std.testing.expectEqual(@as(usize, 9), result.nonzero_sample_count);
    try std.testing.expect(!result.exact_match_within_zero_tolerance);
    try std.testing.expectApproxEqAbs(0.01, result.mean_signed_difference, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.01, result.mean_abs_difference, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.01, result.root_mean_square_difference, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.01, result.max_abs_difference, 1.0e-15);
    try std.testing.expectApproxEqAbs(755.0, result.max_abs_difference_wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(1.0, result.correlation, 1.0e-14);
    try std.testing.expectApproxEqAbs(0.01, result.blue_wing_mean_difference, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.0, result.trough_wavelength_difference_nm, 0.0);
    try std.testing.expectApproxEqAbs(0.01, result.trough_value_difference, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.01, result.rebound_peak_difference, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.01, result.mid_band_mean_difference, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.01, result.red_wing_mean_difference, 1.0e-15);
}

test "O2A band metric interpolation clamps and checks shapes" {
    const wavelengths = [_]f64{ 758.0, 760.0 };
    const values = [_]f64{ 0.2, 0.6 };
    const short_values = [_]f64{0.2};

    try std.testing.expectApproxEqAbs(0.2, try metrics.interpolateVector(wavelengths[0..], values[0..], 757.0), 0.0);
    try std.testing.expectApproxEqAbs(0.4, try metrics.interpolateVector(wavelengths[0..], values[0..], 759.0), 0.0);
    try std.testing.expectApproxEqAbs(0.6, try metrics.interpolateVector(wavelengths[0..], values[0..], 761.0), 0.0);
    try std.testing.expectError(
        error.ShapeMismatch,
        metrics.interpolateVector(wavelengths[0..], short_values[0..], 759.0),
    );
    try std.testing.expectError(
        error.ShapeMismatch,
        metrics.meanVectorInRange(wavelengths[0..], short_values[0..], 758.0, 760.0),
    );
}

test "O2A band assessment verdicts preserve baseline trend rules" {
    const baseline = metrics.ComparisonMetrics{
        .sample_count = 2,
        .nonzero_sample_count = 2,
        .exact_match_within_zero_tolerance = false,
        .mean_signed_difference = 0.0,
        .mean_abs_difference = 0.01,
        .root_mean_square_difference = 0.02,
        .max_abs_difference = 0.03,
        .max_abs_difference_wavelength_nm = 760.0,
        .correlation = 0.99,
        .blue_wing_mean_difference = 0.0,
        .trough_wavelength_difference_nm = 0.0,
        .trough_value_difference = 0.0,
        .rebound_peak_difference = 0.0,
        .mid_band_mean_difference = 0.0,
        .red_wing_mean_difference = 0.0,
    };
    const tolerances = metrics.TrendTolerances{
        .mean_abs_difference_abs = 0.001,
        .root_mean_square_difference_abs = 0.001,
        .max_abs_difference_abs = 0.001,
        .correlation_abs = 0.001,
    };

    var current = baseline;
    current.exact_match_within_zero_tolerance = true;
    var outcome = metrics.assessAgainstBaseline(current, baseline, tolerances, true);
    try std.testing.expectEqual(.exact_zero_pass, outcome.verdict);

    current = baseline;
    outcome = metrics.assessAgainstBaseline(current, baseline, tolerances, false);
    try std.testing.expectEqual(.nonzero_fail, outcome.verdict);

    current = baseline;
    current.mean_abs_difference = 0.02;
    outcome = metrics.assessAgainstBaseline(current, baseline, tolerances, true);
    try std.testing.expectEqual(.regression_fail, outcome.verdict);

    current = baseline;
    current.mean_abs_difference = 0.008;
    outcome = metrics.assessAgainstBaseline(current, baseline, tolerances, true);
    try std.testing.expectEqual(.baseline_pass, outcome.verdict);
    try std.testing.expectEqual(.improved, outcome.trend.mean_abs_difference);
}

test "O2A band metric value rows keep explicit layouts" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(metrics.ReferenceSample));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(metrics.RangeExtremum));
    try std.testing.expectEqual(@as(usize, 120), @sizeOf(metrics.ComparisonMetrics));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(metrics.TrendTolerances));
    try std.testing.expectEqual(@as(usize, 10), @sizeOf(metrics.AssessmentTrend));
    try std.testing.expectEqual(@as(usize, 11), @sizeOf(metrics.AssessmentOutcome));
    try std.testing.expectEqual(
        @as(usize, 112),
        @offsetOf(metrics.ComparisonMetrics, "exact_match_within_zero_tolerance"),
    );
}
