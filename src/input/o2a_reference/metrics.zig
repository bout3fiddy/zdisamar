const std = @import("std");
const InstrumentGrid = @import("../../forward_model/instrument_grid/root.zig");
const OpticsPrepare = @import("../../forward_model/optical_properties/root.zig");
const ReferenceDataModel = @import("../../input/ReferenceData.zig");
const Scene = @import("../../input/Scene.zig").Scene;
const runtime = @import("run.zig");
const SolveConfig = @import("../../forward_model/radiative_transfer/root.zig").SolveConfig;

pub const ReferenceData = ReferenceDataModel;
pub const ReferenceSample = runtime.ReferenceSample;
pub const ResolvedVendorO2ACase = runtime.ResolvedVendorO2ACase;
pub const LineGasSpec = runtime.LineGasSpec;

// metrics.zig ----------------------------------------------------------------------------------------------- |
// O2 A reference-vs-product comparison metrics and trend assessment helpers.                                  |
//                                                                                                             |
// used by                                                                                                     |
//   validation and benchmark paths compare simulated instrument-grid reflectance against retained reference   |
//   rows.                                                                                                     |
//                                                                                                             |
// hot path                                                                                                    |
//   Metric calculation streams the reference samples once, interpolating the generated product at each        |
//   reference wavelength. Range helpers scan wavelength windows used by the O2 A morphology checks.           |
//                                                                                                             |
// memory                                                                                                      |
//   Metric structs are compact value rows. VendorO2A*Case structs are large owner/view headers over scene,    |
//   prepared optical state, product, and reference storage.                                                   |
// ----------------------------------------------------------------------------------------------------------- |

// RangeExtremum --------------------------------------------------------------------------------------------- |
// Wavelength and value for a range-local minimum or maximum.                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] wavelength_nm : f64                                                                                 |
// [8..15] value         : f64                                                                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B                                                                              |
pub const RangeExtremum = struct {
    wavelength_nm: f64,
    value: f64,
};

// ComparisonMetrics ----------------------------------------------------------------------------------------- |
// Scalar error, correlation, and O2 A morphology metrics for one product/reference comparison.                |
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
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 120 B                                                                             |
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

// TrendTolerances ------------------------------------------------------------------------------------------- |
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
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 80 B                                                                              |
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

// AssessmentTrend ------------------------------------------------------------------------------------------- |
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
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 10 B                                                                              |
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

// AssessmentOutcome ----------------------------------------------------------------------------------------- |
// Final validation verdict plus metric-by-metric trend states.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 11 B (0.011 KiB), align: 1 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 0] verdict : AssessmentVerdict                                                                        |
// [ 1..10] trend   : AssessmentTrend                                                                          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 11 B                                                                              |
pub const AssessmentOutcome = struct {
    verdict: AssessmentVerdict,
    trend: AssessmentTrend,
};

// VendorO2AReflectanceCase ---------------------------------------------------------------------------------- |
// Fully prepared O2 A case plus simulated instrument-grid product.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 3144 B (3.070 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..  15] reference  : []ReferenceSample                                                                 |
// [  16.. 687] scene      : Scene                                                                             |
// [ 688.. 767] rtm_config : SolveConfig                                                                       |
// [ 768..2903] prepared   : PreparedOpticalState                                                              |
// [2904..3143] product    : InstrumentGridProduct                                                             |
//                                                                                                             |
// out-of-line                                                                                                 |
//   reference is an owned slice. scene, prepared, and product are inline headers that own or borrow nested    |
//   storage released by deinit.                                                                               |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 50 cache lines at 64 B per line                                                                 |
// footprint: per instance = 3144 B plus referenced scene/product/reference storage                            |
pub const VendorO2AReflectanceCase = struct {
    reference: []ReferenceSample,
    scene: Scene,
    rtm_config: SolveConfig,
    prepared: OpticsPrepare.PreparedOpticalState,
    product: InstrumentGrid.InstrumentGridProduct,

    pub fn deinit(self: *VendorO2AReflectanceCase, allocator: std.mem.Allocator) void {
        self.product.deinit(allocator);
        self.prepared.deinit(allocator);
        self.scene.deinitOwned(allocator);
        allocator.free(self.reference);
        self.* = undefined;
    }
};

// VendorO2APreparedCase ------------------------------------------------------------------------------------- |
// Prepared O2 A case before instrument-grid product simulation.                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2904 B (2.836 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..  15] reference  : []ReferenceSample                                                                 |
// [  16.. 687] scene      : Scene                                                                             |
// [ 688.. 767] rtm_config : SolveConfig                                                                       |
// [ 768..2903] prepared   : PreparedOpticalState                                                              |
//                                                                                                             |
// out-of-line                                                                                                 |
//   reference is an owned slice. scene and prepared are inline headers with nested owned/borrowed storage.    |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 46 cache lines at 64 B per line                                                                 |
// footprint: per instance = 2904 B plus referenced scene/prepared/reference storage                           |
pub const VendorO2APreparedCase = struct {
    reference: []ReferenceSample,
    scene: Scene,
    rtm_config: SolveConfig,
    prepared: OpticsPrepare.PreparedOpticalState,

    pub fn deinit(self: *VendorO2APreparedCase, allocator: std.mem.Allocator) void {
        self.prepared.deinit(allocator);
        self.scene.deinitOwned(allocator);
        allocator.free(self.reference);
        self.* = undefined;
    }

    pub fn intoReflectanceCase(
        self: *VendorO2APreparedCase,
        allocator: std.mem.Allocator,
    ) !VendorO2AReflectanceCase {
        var product = try InstrumentGrid.simulateProduct(
            allocator,
            &self.scene,
            self.rtm_config,
            &self.prepared,
        );
        errdefer product.deinit(allocator);

        const prepared = self.prepared;
        const rtm_config = self.rtm_config;
        const scene = self.scene;
        const reference = self.reference;
        self.* = undefined;

        return .{
            .reference = reference,
            .scene = scene,
            .rtm_config = rtm_config,
            .prepared = prepared,
            .product = product,
        };
    }
};

pub fn runResolvedVendorO2AReflectanceCase(
    allocator: std.mem.Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !VendorO2AReflectanceCase {
    const runtime_case = try runtime.runResolvedVendorO2AReflectanceCase(allocator, resolved);
    return .{
        .reference = runtime_case.reference,
        .scene = runtime_case.scene,
        .rtm_config = runtime_case.rtm_config,
        .prepared = runtime_case.prepared,
        .product = runtime_case.product,
    };
}

pub fn prepareResolvedVendorO2ACase(
    allocator: std.mem.Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !VendorO2APreparedCase {
    const runtime_case = try runtime.prepareResolvedVendorO2ACase(allocator, resolved);
    return .{
        .reference = runtime_case.reference,
        .scene = runtime_case.scene,
        .rtm_config = runtime_case.rtm_config,
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

    const blue_wing_regressed =
        compareAbsoluteCeiling(
            @abs(current.blue_wing_mean_difference),
            tolerances.blue_wing_mean_difference_abs,
        ) == .regressed;
    const trough_wavelength_regressed =
        compareAbsoluteCeiling(
            @abs(current.trough_wavelength_difference_nm),
            tolerances.trough_wavelength_difference_nm_abs,
        ) == .regressed;
    const trough_value_regressed =
        compareAbsoluteCeiling(
            @abs(current.trough_value_difference),
            tolerances.trough_value_difference_abs,
        ) == .regressed;
    const rebound_peak_regressed =
        compareAbsoluteCeiling(
            @abs(current.rebound_peak_difference),
            tolerances.rebound_peak_difference_abs,
        ) == .regressed;
    const mid_band_regressed =
        compareAbsoluteCeiling(
            @abs(current.mid_band_mean_difference),
            tolerances.mid_band_mean_difference_abs,
        ) == .regressed;
    const red_wing_regressed =
        compareAbsoluteCeiling(
            @abs(current.red_wing_mean_difference),
            tolerances.red_wing_mean_difference_abs,
        ) == .regressed;
    const morphology_ceiling_regressed =
        blue_wing_regressed or
        trough_wavelength_regressed or
        trough_value_regressed or
        rebound_peak_regressed or
        mid_band_regressed or
        red_wing_regressed;

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
    product: *const InstrumentGrid.InstrumentGridProduct,
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

pub fn loadResolvedO2ASpectroscopyLineList(
    allocator: std.mem.Allocator,
    spec: LineGasSpec,
) !ReferenceDataModel.SpectroscopyLineList {
    return runtime.loadResolvedVendorO2ALineList(allocator, spec);
}
