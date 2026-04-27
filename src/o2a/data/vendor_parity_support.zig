//! Purpose:
//!   Own the retained O2A parity execution and assessment helpers
//!   now that YAML is the source of truth for case assembly.
//!
//! Physics:
//!   This module runs the committed O2 A-band parity scene through optics
//!   preparation and measurement-space simulation, then computes the residual
//!   and morphology metrics used by the validation lanes.
//!
//! Vendor:
//!   `readConfigFileModule::O2/O2-O2/INSTRUMENT/ATMOSPHERIC_INTERVALS`
//!   and the vendor-reflectance assessment harness semantics
//!
//! Design:
//!   Case assembly lives in the YAML adapter and shared runtime contract. This
//!   file keeps only the typed execution products and residual analysis helpers
//!   that multiple lanes still share.
//!
//! Invariants:
//!   The helpers here never invent a second config source of truth; they only
//!   consume resolved parity cases.
//!
//! Validation:
//!   `tests/validation/o2a_yaml_parity_runtime_test.zig`,
//!   `tests/validation/o2a_forward_shape_test.zig`,
//!   `tests/validation/o2a_vendor_reflectance_assessment_test.zig`,
//!   and retained plot-bundle validation.

const std = @import("std");
const MeasurementSpace = @import("../../kernels/transport/measurement.zig");
const ReferenceDataModel = @import("../../model/ReferenceData.zig");
const runtime = @import("vendor_parity_runtime.zig");
const support_types = @import("vendor_parity_support_types.zig");

pub const ReferenceData = support_types.ReferenceData;
pub const ReferenceSample = support_types.ReferenceSample;
pub const ResolvedVendorO2ACase = support_types.ResolvedVendorO2ACase;
pub const LineGasSpec = support_types.LineGasSpec;
pub const RangeExtremum = support_types.RangeExtremum;
pub const ComparisonMetrics = support_types.ComparisonMetrics;
pub const TrendTolerances = support_types.TrendTolerances;
pub const TrendState = support_types.TrendState;
pub const AssessmentVerdict = support_types.AssessmentVerdict;
pub const AssessmentTrend = support_types.AssessmentTrend;
pub const AssessmentOutcome = support_types.AssessmentOutcome;
pub const VendorO2AReflectanceCase = support_types.VendorO2AReflectanceCase;
pub const VendorO2APreparedCase = support_types.VendorO2APreparedCase;

pub fn runResolvedVendorO2AReflectanceCase(
    allocator: std.mem.Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !VendorO2AReflectanceCase {
    const runtime_case = try runtime.runResolvedVendorO2AReflectanceCase(allocator, resolved);
    return .{
        .reference = runtime_case.reference,
        .scene = runtime_case.scene,
        .route = runtime_case.route,
        .prepared = runtime_case.prepared,
        .product = runtime_case.product,
    };
}

pub fn prepareResolvedVendorO2ACase(
    allocator: std.mem.Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !VendorO2APreparedCase {
    const runtime_case = try runtime.prepareResolvedVendorO2ACase(
        allocator,
        resolved,
    );
    return .{
        .reference = runtime_case.reference,
        .scene = runtime_case.scene,
        .route = runtime_case.route,
        .prepared = runtime_case.prepared,
    };
}

pub fn meanVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) f64 {
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
) RangeExtremum {
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
) f64 {
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
    var sum: f64 = 0.0;
    var count: usize = 0;
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;
        sum += sample.reflectance;
        count += 1;
    }
    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

pub fn minReferenceInRange(
    reference: []const ReferenceSample,
    start_nm: f64,
    end_nm: f64,
) RangeExtremum {
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

pub fn maxReferenceInRange(
    reference: []const ReferenceSample,
    start_nm: f64,
    end_nm: f64,
) f64 {
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
) f64 {
    if (wavelengths_nm.len == 0 or values.len == 0) return 0.0;
    if (target_wavelength_nm <= wavelengths_nm[0]) return values[0];
    if (target_wavelength_nm >= wavelengths_nm[wavelengths_nm.len - 1]) return values[values.len - 1];

    var lower_index: usize = 0;
    while (lower_index + 1 < wavelengths_nm.len and wavelengths_nm[lower_index + 1] < target_wavelength_nm) : (lower_index += 1) {}

    const upper_index = lower_index + 1;
    const lower_wavelength = wavelengths_nm[lower_index];
    const upper_wavelength = wavelengths_nm[upper_index];
    const lower_value = values[lower_index];
    const upper_value = values[upper_index];
    const blend = (target_wavelength_nm - lower_wavelength) / (upper_wavelength - lower_wavelength);
    return lower_value + (upper_value - lower_value) * blend;
}

pub fn compareLowerIsBetter(current: f64, baseline: f64, tolerance: f64) TrendState {
    if (current < baseline - tolerance) return .improved;
    if (current > baseline + tolerance) return .regressed;
    return .flat;
}

pub fn compareHigherIsBetter(current: f64, baseline: f64, tolerance: f64) TrendState {
    if (current > baseline + tolerance) return .improved;
    if (current < baseline - tolerance) return .regressed;
    return .flat;
}

pub fn compareAbsoluteCeiling(current: f64, ceiling: f64) TrendState {
    if (current > ceiling) return .regressed;
    return .flat;
}

pub fn assessAgainstBaseline(
    current: ComparisonMetrics,
    baseline: ComparisonMetrics,
    tolerances: TrendTolerances,
    allowed_to_fail: bool,
) AssessmentOutcome {
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
        compareAbsoluteCeiling(@abs(current.blue_wing_mean_difference), tolerances.blue_wing_mean_difference_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.trough_wavelength_difference_nm), tolerances.trough_wavelength_difference_nm_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.trough_value_difference), tolerances.trough_value_difference_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.rebound_peak_difference), tolerances.rebound_peak_difference_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.mid_band_mean_difference), tolerances.mid_band_mean_difference_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.red_wing_mean_difference), tolerances.red_wing_mean_difference_abs) == .regressed;

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
    product: *const MeasurementSpace.MeasurementSpaceProduct,
    reference: []const ReferenceSample,
    zero_tolerance_abs: f64,
) ComparisonMetrics {
    const blue_wing_mean = meanVectorInRange(product.wavelengths, product.reflectance, 755.0, 758.5);
    const trough = minVectorInRange(product.wavelengths, product.reflectance, 760.2, 761.1);
    const rebound_peak = maxVectorInRange(product.wavelengths, product.reflectance, 761.8, 762.4);
    const mid_band_mean = meanVectorInRange(product.wavelengths, product.reflectance, 763.8, 765.5);
    const red_wing_mean = meanVectorInRange(product.wavelengths, product.reflectance, 769.5, 771.0);

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
        const generated = interpolateVector(product.wavelengths, product.reflectance, sample.wavelength_nm);
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
        const generated = interpolateVector(product.wavelengths, product.reflectance, sample.wavelength_nm);
        covariance += (generated - generated_mean) * (sample.reflectance - reference_mean);
        generated_variance += std.math.pow(f64, generated - generated_mean, 2.0);
        reference_variance += std.math.pow(f64, sample.reflectance - reference_mean, 2.0);
    }

    const correlation = if (generated_variance == 0.0 or reference_variance == 0.0)
        0.0
    else
        covariance / @sqrt(generated_variance * reference_variance);

    return .{
        .sample_count = reference.len,
        .nonzero_sample_count = nonzero_sample_count,
        .exact_match_within_zero_tolerance = nonzero_sample_count == 0,
        .mean_signed_difference = if (reference.len == 0) 0.0 else sum_signed / sample_count,
        .mean_abs_difference = if (reference.len == 0) 0.0 else sum_abs / sample_count,
        .root_mean_square_difference = if (reference.len == 0) 0.0 else @sqrt(sum_sq / sample_count),
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

pub fn loadResolvedO2ASpectroscopyLineList(
    allocator: std.mem.Allocator,
    spec: LineGasSpec,
) !ReferenceDataModel.SpectroscopyLineList {
    return runtime.loadResolvedVendorO2ALineList(allocator, spec);
}
