const std = @import("std");

pub const Error = error{
    ShapeMismatch,
};

// o2a_band_metrics.zig -------------------------------------------------------------------------------------  |
// Validation-only O2 A spectrum comparison metrics.                                                           |
//                                                                                                             |
//   Replaces the removed broad runtime-case metrics helper with explicit validation vectors.                  |
//   Runtime-case wrappers stay out of O2 A because they depend on broad pre-refactor owner shapes.            |
//                                                                                                             |
// boundary                                                                                                    |
//   Callers pass explicit wavelength/reflectance vectors and reference rows. This module performs no file     |
//   I/O, imports no RTM/product modules, and stores no retained state.                                        |
//                                                                                                             |
// O2 A windows                                                                                                |
//   blue wing 755.0..758.5 nm; trough 760.2..761.1 nm; rebound 761.8..762.4 nm; mid band 763.8..765.5 nm;     |
//   red wing 769.5..771.0 nm.                                                                                 |
// ----------------------------------------------------------------------------------------------------------- |

// ReferenceSample ------------------------------------------------------------------------------------------  |
// One retained O2 A reference reflectance sample.                                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] wavelength_nm : f64                                                                                 |
// [8..15] reflectance   : f64                                                                                 |
pub const ReferenceSample = struct {
    wavelength_nm: f64,
    reflectance: f64,
};
// ----------------------------------------------------------------------------------------------------------- |

// RangeExtremum --------------------------------------------------------------------------------------------  |
// Wavelength and value for a range-local minimum or maximum.                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] wavelength_nm : f64                                                                                 |
// [8..15] value         : f64                                                                                 |
pub const RangeExtremum = struct {
    wavelength_nm: f64,
    value: f64,
};
// ----------------------------------------------------------------------------------------------------------- |

// ComparisonMetrics ----------------------------------------------------------------------------------------  |
// Scalar residual, correlation, and O2 A morphology metrics for one generated/reference comparison.           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 120 B (0.117 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] sample_count                      : usize                                                        |
// [  8.. 15] nonzero_sample_count              : usize                                                        |
// [ 16.. 23] mean_signed_difference            : f64                                                          |
// [ 24.. 31] mean_abs_difference               : f64                                                          |
// [ 32.. 39] root_mean_square_difference       : f64                                                          |
// [ 40.. 47] max_abs_difference                : f64                                                          |
// [ 48.. 55] max_abs_difference_wavelength_nm  : f64                                                          |
// [ 56.. 63] correlation                       : f64                                                          |
// [ 64.. 71] blue_wing_mean_difference         : f64                                                          |
// [ 72.. 79] trough_wavelength_difference_nm   : f64                                                          |
// [ 80.. 87] trough_value_difference           : f64                                                          |
// [ 88.. 95] rebound_peak_difference           : f64                                                          |
// [ 96..103] mid_band_mean_difference          : f64                                                          |
// [104..111] red_wing_mean_difference          : f64                                                          |
// [112..112] exact_match_within_zero_tolerance : bool                                                         |
// [113..119] trailing padding                  : 7 B                                                          |
pub const ComparisonMetrics = struct {
    sample_count: usize,
    nonzero_sample_count: usize,
    exact_match_within_zero_tolerance: bool,
    mean_signed_difference: f64,
    mean_abs_difference: f64,
    root_mean_square_difference: f64,
    max_abs_difference: f64,
    max_abs_difference_wavelength_nm: f64,
    correlation: f64,
    blue_wing_mean_difference: f64,
    trough_wavelength_difference_nm: f64,
    trough_value_difference: f64,
    rebound_peak_difference: f64,
    mid_band_mean_difference: f64,
    red_wing_mean_difference: f64,
};
// ----------------------------------------------------------------------------------------------------------- |

// TrendTolerances ------------------------------------------------------------------------------------------  |
// Absolute tolerances used when classifying metric trends against a baseline.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] mean_abs_difference_abs             : f64                                                          |
// [ 8..15] root_mean_square_difference_abs     : f64                                                          |
// [16..23] max_abs_difference_abs              : f64                                                          |
// [24..31] correlation_abs                     : f64                                                          |
// [32..39] blue_wing_mean_difference_abs       : f64                                                          |
// [40..47] trough_wavelength_difference_nm_abs : f64                                                          |
// [48..55] trough_value_difference_abs         : f64                                                          |
// [56..63] rebound_peak_difference_abs         : f64                                                          |
// [64..71] mid_band_mean_difference_abs        : f64                                                          |
// [72..79] red_wing_mean_difference_abs        : f64                                                          |
pub const TrendTolerances = struct {
    mean_abs_difference_abs: f64,
    root_mean_square_difference_abs: f64,
    max_abs_difference_abs: f64,
    correlation_abs: f64,
    blue_wing_mean_difference_abs: f64 = 1.0e-6,
    trough_wavelength_difference_nm_abs: f64 = 1.0e-6,
    trough_value_difference_abs: f64 = 1.0e-6,
    rebound_peak_difference_abs: f64 = 1.0e-6,
    mid_band_mean_difference_abs: f64 = 1.0e-6,
    red_wing_mean_difference_abs: f64 = 1.0e-6,
};
// ----------------------------------------------------------------------------------------------------------- |

pub const TrendState = enum {
    improved,
    flat,
    regressed,
};

pub const AssessmentVerdict = enum {
    exact_zero_pass,
    baseline_pass,
    regression_fail,
    nonzero_fail,
};

// AssessmentTrend ------------------------------------------------------------------------------------------  |
// Per-metric trend states after comparing current metrics to a baseline.                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 10 B (0.010 KiB), align: 1 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..0] mean_abs_difference             : TrendState                                                         |
// [1..1] root_mean_square_difference     : TrendState                                                         |
// [2..2] max_abs_difference              : TrendState                                                         |
// [3..3] correlation                     : TrendState                                                         |
// [4..4] blue_wing_mean_difference       : TrendState                                                         |
// [5..5] trough_wavelength_difference_nm : TrendState                                                         |
// [6..6] trough_value_difference         : TrendState                                                         |
// [7..7] rebound_peak_difference         : TrendState                                                         |
// [8..8] mid_band_mean_difference        : TrendState                                                         |
// [9..9] red_wing_mean_difference        : TrendState                                                         |
pub const AssessmentTrend = struct {
    mean_abs_difference: TrendState,
    root_mean_square_difference: TrendState,
    max_abs_difference: TrendState,
    correlation: TrendState,
    blue_wing_mean_difference: TrendState,
    trough_wavelength_difference_nm: TrendState,
    trough_value_difference: TrendState,
    rebound_peak_difference: TrendState,
    mid_band_mean_difference: TrendState,
    red_wing_mean_difference: TrendState,
};
// ----------------------------------------------------------------------------------------------------------- |

// AssessmentOutcome ----------------------------------------------------------------------------------------  |
// Final validation verdict plus metric-by-metric trend states.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 11 B (0.011 KiB), align: 1 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 0] verdict : AssessmentVerdict                                                                        |
// [ 1..10] trend   : AssessmentTrend                                                                          |
pub const AssessmentOutcome = struct {
    verdict: AssessmentVerdict,
    trend: AssessmentTrend,
};
// ----------------------------------------------------------------------------------------------------------- |

pub fn meanVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) Error!f64 {
    // meanVectorInRange ------------------------------------------------------------------------------------  |
    // Average generated values inside one inclusive wavelength window.                                        |
    // ------------------------------------------------------------------------------------------------------- |
    if (wavelengths_nm.len != values.len) return error.ShapeMismatch;

    var sum: f64 = 0.0;
    var count: usize = 0;
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        sum += value;
        count += 1;
    }
    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

pub fn minVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) Error!RangeExtremum {
    // minVectorInRange -------------------------------------------------------------------------------------  |
    // Return the minimum generated value inside one inclusive wavelength window.                              |
    // ------------------------------------------------------------------------------------------------------- |
    if (wavelengths_nm.len != values.len) return error.ShapeMismatch;

    var best = std.math.inf(f64);
    var best_wavelength = start_nm;
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value < best) {
            best = value;
            best_wavelength = wavelength_nm;
        }
    }
    return .{ .wavelength_nm = best_wavelength, .value = best };
}

pub fn maxVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) Error!f64 {
    // maxVectorInRange -------------------------------------------------------------------------------------  |
    // Return the maximum generated value inside one inclusive wavelength window.                              |
    // ------------------------------------------------------------------------------------------------------- |
    if (wavelengths_nm.len != values.len) return error.ShapeMismatch;

    var best = -std.math.inf(f64);
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value > best) best = value;
    }
    return best;
}

pub fn meanReferenceInRange(
    reference: []const ReferenceSample,
    start_nm: f64,
    end_nm: f64,
) f64 {
    // meanReferenceInRange ---------------------------------------------------------------------------------  |
    // Average reference reflectance inside one inclusive wavelength window.                                   |
    // ------------------------------------------------------------------------------------------------------- |
    var sum: f64 = 0.0;
    var count: usize = 0;
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;

        sum += sample.reflectance;
        count += 1;
    }

    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

pub fn minReferenceInRange(reference: []const ReferenceSample, start_nm: f64, end_nm: f64) RangeExtremum {
    // minReferenceInRange ----------------------------------------------------------------------------------  |
    // Return the minimum reference reflectance inside one inclusive wavelength window.                        |
    // ------------------------------------------------------------------------------------------------------- |
    var best = std.math.inf(f64);
    var best_wavelength = start_nm;
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;
        if (sample.reflectance < best) {
            best = sample.reflectance;
            best_wavelength = sample.wavelength_nm;
        }
    }
    return .{ .wavelength_nm = best_wavelength, .value = best };
}

pub fn maxReferenceInRange(reference: []const ReferenceSample, start_nm: f64, end_nm: f64) f64 {
    // maxReferenceInRange ----------------------------------------------------------------------------------  |
    // Return the maximum reference reflectance inside one inclusive wavelength window.                        |
    // ------------------------------------------------------------------------------------------------------- |
    var best = -std.math.inf(f64);
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;
        if (sample.reflectance > best) best = sample.reflectance;
    }
    return best;
}

pub fn interpolateVector(
    wavelengths_nm: []const f64,
    values: []const f64,
    target_wavelength_nm: f64,
) Error!f64 {
    // interpolateVector ------------------------------------------------------------------------------------  |
    // Linearly interpolate generated reflectance at a reference wavelength.                                   |
    // ------------------------------------------------------------------------------------------------------- |
    if (wavelengths_nm.len != values.len) return error.ShapeMismatch;
    if (wavelengths_nm.len == 0) return 0.0;
    if (target_wavelength_nm <= wavelengths_nm[0]) return values[0];
    if (target_wavelength_nm >= wavelengths_nm[wavelengths_nm.len - 1]) return values[values.len - 1];

    var lower_index: usize = 0;
    while (lower_index + 1 < wavelengths_nm.len and
        wavelengths_nm[lower_index + 1] < target_wavelength_nm) : (lower_index += 1)
    {}

    const upper_index = lower_index + 1;
    const lower_wavelength = wavelengths_nm[lower_index];
    const upper_wavelength = wavelengths_nm[upper_index];
    const lower_value = values[lower_index];
    const upper_value = values[upper_index];
    const blend = (target_wavelength_nm - lower_wavelength) / (upper_wavelength - lower_wavelength);
    return lower_value + (upper_value - lower_value) * blend;
}

pub fn compareLowerIsBetter(current: f64, baseline: f64, tolerance: f64) TrendState {
    // compareLowerIsBetter ---------------------------------------------------------------------------------  |
    // Classify residual metrics where lower values improve validation agreement.                              |
    // ------------------------------------------------------------------------------------------------------- |
    if (current < baseline - tolerance) return .improved;
    if (current > baseline + tolerance) return .regressed;
    return .flat;
}

pub fn compareHigherIsBetter(current: f64, baseline: f64, tolerance: f64) TrendState {
    // compareHigherIsBetter --------------------------------------------------------------------------------  |
    // Classify agreement metrics where higher values improve validation agreement.                            |
    // ------------------------------------------------------------------------------------------------------- |
    if (current > baseline + tolerance) return .improved;
    if (current < baseline - tolerance) return .regressed;
    return .flat;
}

pub fn compareAbsoluteCeiling(current: f64, ceiling: f64) TrendState {
    // compareAbsoluteCeiling -------------------------------------------------------------------------------  |
    // Classify morphology residuals against absolute allowed ceilings.                                        |
    // ------------------------------------------------------------------------------------------------------- |
    if (current > ceiling) return .regressed;
    return .flat;
}

pub fn assessAgainstBaseline(
    current: ComparisonMetrics,
    baseline: ComparisonMetrics,
    tolerances: TrendTolerances,
    allowed_to_fail: bool,
) AssessmentOutcome {
    // assessAgainstBaseline --------------------------------------------------------------------------------  |
    // Apply the validation verdict rules to current metrics and a retained baseline row.                      |
    // ------------------------------------------------------------------------------------------------------- |
    const trend: AssessmentTrend = .{
        .mean_abs_difference = compareLowerIsBetter(
            current.mean_abs_difference,
            baseline.mean_abs_difference,
            tolerances.mean_abs_difference_abs,
        ),
        .root_mean_square_difference = compareLowerIsBetter(
            current.root_mean_square_difference,
            baseline.root_mean_square_difference,
            tolerances.root_mean_square_difference_abs,
        ),
        .max_abs_difference = compareLowerIsBetter(
            current.max_abs_difference,
            baseline.max_abs_difference,
            tolerances.max_abs_difference_abs,
        ),
        .correlation = compareHigherIsBetter(
            current.correlation,
            baseline.correlation,
            tolerances.correlation_abs,
        ),
        .blue_wing_mean_difference = compareLowerIsBetter(
            @abs(current.blue_wing_mean_difference),
            @abs(baseline.blue_wing_mean_difference),
            0.0,
        ),
        .trough_wavelength_difference_nm = compareLowerIsBetter(
            @abs(current.trough_wavelength_difference_nm),
            @abs(baseline.trough_wavelength_difference_nm),
            0.0,
        ),
        .trough_value_difference = compareLowerIsBetter(
            @abs(current.trough_value_difference),
            @abs(baseline.trough_value_difference),
            0.0,
        ),
        .rebound_peak_difference = compareLowerIsBetter(
            @abs(current.rebound_peak_difference),
            @abs(baseline.rebound_peak_difference),
            0.0,
        ),
        .mid_band_mean_difference = compareLowerIsBetter(
            @abs(current.mid_band_mean_difference),
            @abs(baseline.mid_band_mean_difference),
            0.0,
        ),
        .red_wing_mean_difference = compareLowerIsBetter(
            @abs(current.red_wing_mean_difference),
            @abs(baseline.red_wing_mean_difference),
            0.0,
        ),
    };

    const morphology_ceiling_regressed =
        compareAbsoluteCeiling(
            @abs(current.blue_wing_mean_difference),
            tolerances.blue_wing_mean_difference_abs,
        ) == .regressed or
        compareAbsoluteCeiling(
            @abs(current.trough_wavelength_difference_nm),
            tolerances.trough_wavelength_difference_nm_abs,
        ) == .regressed or
        compareAbsoluteCeiling(
            @abs(current.trough_value_difference),
            tolerances.trough_value_difference_abs,
        ) == .regressed or
        compareAbsoluteCeiling(
            @abs(current.rebound_peak_difference),
            tolerances.rebound_peak_difference_abs,
        ) == .regressed or
        compareAbsoluteCeiling(
            @abs(current.mid_band_mean_difference),
            tolerances.mid_band_mean_difference_abs,
        ) == .regressed or
        compareAbsoluteCeiling(
            @abs(current.red_wing_mean_difference),
            tolerances.red_wing_mean_difference_abs,
        ) == .regressed;

    if (current.exact_match_within_zero_tolerance) {
        return .{ .verdict = .exact_zero_pass, .trend = trend };
    }

    if (!allowed_to_fail) {
        return .{ .verdict = .nonzero_fail, .trend = trend };
    }

    if (trend.mean_abs_difference == .regressed or
        trend.root_mean_square_difference == .regressed or
        trend.max_abs_difference == .regressed or
        trend.correlation == .regressed or
        morphology_ceiling_regressed)
    {
        return .{ .verdict = .regression_fail, .trend = trend };
    }

    return .{ .verdict = .baseline_pass, .trend = trend };
}

pub fn computeComparisonMetrics(
    wavelengths_nm: []const f64,
    reflectance: []const f64,
    reference: []const ReferenceSample,
    zero_tolerance_abs: f64,
) Error!ComparisonMetrics {
    // computeComparisonMetrics -----------------------------------------------------------------------------  |
    // Compare generated reflectance to reference rows using the residual and O2 A morphology metrics.         |
    // ------------------------------------------------------------------------------------------------------- |
    if (wavelengths_nm.len != reflectance.len) return error.ShapeMismatch;

    const blue_wing_mean = try meanVectorInRange(wavelengths_nm, reflectance, 755.0, 758.5);
    const trough = try minVectorInRange(wavelengths_nm, reflectance, 760.2, 761.1);
    const rebound_peak = try maxVectorInRange(wavelengths_nm, reflectance, 761.8, 762.4);
    const mid_band_mean = try meanVectorInRange(wavelengths_nm, reflectance, 763.8, 765.5);
    const red_wing_mean = try meanVectorInRange(wavelengths_nm, reflectance, 769.5, 771.0);

    const reference_blue_wing_mean = meanReferenceInRange(reference, 755.0, 758.5);
    const reference_trough = minReferenceInRange(reference, 760.2, 761.1);
    const reference_rebound_peak = maxReferenceInRange(reference, 761.8, 762.4);
    const reference_mid_band_mean = meanReferenceInRange(reference, 763.8, 765.5);
    const reference_red_wing_mean = meanReferenceInRange(reference, 769.5, 771.0);

    var sum_signed: f64 = 0.0;
    var sum_abs: f64 = 0.0;
    var sum_sq: f64 = 0.0;
    var generated_mean: f64 = 0.0;
    var reference_mean: f64 = 0.0;
    var max_abs_difference: f64 = 0.0;
    var max_abs_difference_wavelength_nm = if (reference.len == 0) 0.0 else reference[0].wavelength_nm;
    var nonzero_sample_count: usize = 0;

    for (reference) |sample| {
        const generated = try interpolateVector(wavelengths_nm, reflectance, sample.wavelength_nm);
        const delta = generated - sample.reflectance;
        const abs_delta = @abs(delta);
        sum_signed += delta;
        sum_abs += abs_delta;
        sum_sq += delta * delta;
        generated_mean += generated;
        reference_mean += sample.reflectance;
        if (abs_delta > zero_tolerance_abs) nonzero_sample_count += 1;
        if (abs_delta > max_abs_difference) {
            max_abs_difference = abs_delta;
            max_abs_difference_wavelength_nm = sample.wavelength_nm;
        }
    }

    const sample_count = @as(f64, @floatFromInt(reference.len));
    if (reference.len != 0) {
        generated_mean /= sample_count;
        reference_mean /= sample_count;
    }

    var covariance: f64 = 0.0;
    var generated_variance: f64 = 0.0;
    var reference_variance: f64 = 0.0;
    for (reference) |sample| {
        const generated = try interpolateVector(wavelengths_nm, reflectance, sample.wavelength_nm);
        covariance += (generated - generated_mean) * (sample.reflectance - reference_mean);
        generated_variance += std.math.pow(f64, generated - generated_mean, 2.0);
        reference_variance += std.math.pow(f64, sample.reflectance - reference_mean, 2.0);
    }

    const correlation = choose_correlation: {
        if (generated_variance == 0.0 or reference_variance == 0.0) break :choose_correlation 0.0;
        break :choose_correlation covariance / @sqrt(generated_variance * reference_variance);
    };
    var mean_signed_difference: f64 = 0.0;
    var mean_abs_difference: f64 = 0.0;
    var root_mean_square_difference: f64 = 0.0;
    if (reference.len != 0) {
        mean_signed_difference = sum_signed / sample_count;
        mean_abs_difference = sum_abs / sample_count;
        root_mean_square_difference = @sqrt(sum_sq / sample_count);
    }

    return .{
        .sample_count = reference.len,
        .nonzero_sample_count = nonzero_sample_count,
        .exact_match_within_zero_tolerance = nonzero_sample_count == 0,
        .mean_signed_difference = mean_signed_difference,
        .mean_abs_difference = mean_abs_difference,
        .root_mean_square_difference = root_mean_square_difference,
        .max_abs_difference = max_abs_difference,
        .max_abs_difference_wavelength_nm = max_abs_difference_wavelength_nm,
        .correlation = correlation,
        .blue_wing_mean_difference = blue_wing_mean - reference_blue_wing_mean,
        .trough_wavelength_difference_nm = trough.wavelength_nm - reference_trough.wavelength_nm,
        .trough_value_difference = trough.value - reference_trough.value,
        .rebound_peak_difference = rebound_peak - reference_rebound_peak,
        .mid_band_mean_difference = mid_band_mean - reference_mid_band_mean,
        .red_wing_mean_difference = red_wing_mean - reference_red_wing_mean,
    };
}

comptime {
    std.debug.assert(@sizeOf(ReferenceSample) == 16);
    std.debug.assert(@sizeOf(RangeExtremum) == 16);
    std.debug.assert(@sizeOf(ComparisonMetrics) == 120);
    std.debug.assert(@sizeOf(TrendTolerances) == 80);
    std.debug.assert(@sizeOf(AssessmentTrend) == 10);
    std.debug.assert(@sizeOf(AssessmentOutcome) == 11);
}
