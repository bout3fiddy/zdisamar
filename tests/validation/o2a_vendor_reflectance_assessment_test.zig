const std = @import("std");
const zdisamar = @import("zdisamar");
const disamar_reference = zdisamar.disamar_reference;

const BaselineAnchor = struct {
    version: u32,
    scenario: []const u8,
    upstream_config: []const u8,
    reference_path: []const u8,
    zero_tolerance_abs: f64,
    trend_tolerances: disamar_reference.TrendTolerances,
    guidance: struct {
        allowed_to_fail: bool,
        summary: []const u8,
        expect_improvement_when_touched: []const []const u8,
    },
    baseline: disamar_reference.ComparisonMetrics,
};

const LoadedBaselineAnchor = struct {
    raw: []u8,
    parsed: std.json.Parsed(BaselineAnchor),

    fn deinit(self: *LoadedBaselineAnchor, allocator: std.mem.Allocator) void {
        self.parsed.deinit();
        allocator.free(self.raw);
        self.* = undefined;
    }
};

fn loadBaselineAnchor(allocator: std.mem.Allocator) !LoadedBaselineAnchor {
    const raw = try std.fs.cwd().readFileAlloc(
        allocator,
        "validation/o2a_vendor_forward_reflectance_baseline.json",
        64 * 1024,
    );
    errdefer allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        BaselineAnchor,
        allocator,
        raw,
        .{ .ignore_unknown_fields = false },
    );
    return .{
        .raw = raw,
        .parsed = parsed,
    };
}

fn verdictLabel(verdict: disamar_reference.AssessmentVerdict) []const u8 {
    return switch (verdict) {
        .exact_zero_pass => "pass_exact_zero",
        .baseline_pass => "pass_baseline_trend",
        .regression_fail => "fail_regression",
        .nonzero_fail => "fail_nonzero",
    };
}

fn emitAssessment(
    allocator: std.mem.Allocator,
    anchor: BaselineAnchor,
    current: disamar_reference.ComparisonMetrics,
    outcome: disamar_reference.AssessmentOutcome,
) !void {
    const assessment = .{
        .scenario = anchor.scenario,
        .upstream_config = anchor.upstream_config,
        .reference_path = anchor.reference_path,
        .status = verdictLabel(outcome.verdict),
        .zero_tolerance_abs = anchor.zero_tolerance_abs,
        .baseline = anchor.baseline,
        .current = current,
        .delta_from_baseline = .{
            .mean_signed_difference = current.mean_signed_difference - anchor.baseline.mean_signed_difference,
            .mean_abs_difference = current.mean_abs_difference - anchor.baseline.mean_abs_difference,
            .root_mean_square_difference = current.root_mean_square_difference - anchor.baseline.root_mean_square_difference,
            .max_abs_difference = current.max_abs_difference - anchor.baseline.max_abs_difference,
            .correlation = current.correlation - anchor.baseline.correlation,
            .blue_wing_mean_difference = current.blue_wing_mean_difference - anchor.baseline.blue_wing_mean_difference,
            .trough_wavelength_difference_nm = current.trough_wavelength_difference_nm - anchor.baseline.trough_wavelength_difference_nm,
            .trough_value_difference = current.trough_value_difference - anchor.baseline.trough_value_difference,
            .rebound_peak_difference = current.rebound_peak_difference - anchor.baseline.rebound_peak_difference,
            .mid_band_mean_difference = current.mid_band_mean_difference - anchor.baseline.mid_band_mean_difference,
            .red_wing_mean_difference = current.red_wing_mean_difference - anchor.baseline.red_wing_mean_difference,
            .nonzero_sample_count = @as(i64, @intCast(current.nonzero_sample_count)) -
                @as(i64, @intCast(anchor.baseline.nonzero_sample_count)),
        },
        .trend = outcome.trend,
        .guidance = anchor.guidance,
    };

    const rendered = try std.fmt.allocPrint(
        allocator,
        "{f}\n",
        .{std.json.fmt(assessment, .{ .whitespace = .indent_2 })},
    );
    defer allocator.free(rendered);
    std.debug.print("{s}", .{rendered});
}

fn makeMetrics(
    mean_abs_difference: f64,
    root_mean_square_difference: f64,
    max_abs_difference: f64,
    correlation: f64,
    exact_match_within_zero_tolerance: bool,
) disamar_reference.ComparisonMetrics {
    return .{
        .sample_count = 1,
        .nonzero_sample_count = if (exact_match_within_zero_tolerance) 0 else 1,
        .exact_match_within_zero_tolerance = exact_match_within_zero_tolerance,
        .mean_signed_difference = 0.0,
        .mean_abs_difference = mean_abs_difference,
        .root_mean_square_difference = root_mean_square_difference,
        .max_abs_difference = max_abs_difference,
        .max_abs_difference_wavelength_nm = 760.8,
        .correlation = correlation,
        .blue_wing_mean_difference = 0.0,
        .trough_wavelength_difference_nm = 0.0,
        .trough_value_difference = 0.0,
        .rebound_peak_difference = 0.0,
        .mid_band_mean_difference = 0.0,
        .red_wing_mean_difference = 0.0,
    };
}

test "o2a vendor assessment passes when metrics are flat versus baseline" {
    const baseline = makeMetrics(0.04, 0.05, 0.08, 0.99, false);
    const outcome = disamar_reference.assessAgainstBaseline(
        baseline,
        baseline,
        .{
            .mean_abs_difference_abs = 1.0e-6,
            .root_mean_square_difference_abs = 1.0e-6,
            .max_abs_difference_abs = 1.0e-6,
            .correlation_abs = 1.0e-6,
        },
        true,
    );

    try std.testing.expectEqual(disamar_reference.AssessmentVerdict.baseline_pass, outcome.verdict);
    try std.testing.expectEqual(disamar_reference.TrendState.flat, outcome.trend.mean_abs_difference);
    try std.testing.expectEqual(disamar_reference.TrendState.flat, outcome.trend.correlation);
}

test "o2a vendor assessment passes when lower-is-better metrics improve" {
    const baseline = makeMetrics(0.04, 0.05, 0.08, 0.99, false);
    const improved = makeMetrics(0.03, 0.04, 0.07, 0.991, false);
    const outcome = disamar_reference.assessAgainstBaseline(
        improved,
        baseline,
        .{
            .mean_abs_difference_abs = 1.0e-6,
            .root_mean_square_difference_abs = 1.0e-6,
            .max_abs_difference_abs = 1.0e-6,
            .correlation_abs = 1.0e-6,
        },
        true,
    );

    try std.testing.expectEqual(disamar_reference.AssessmentVerdict.baseline_pass, outcome.verdict);
    try std.testing.expectEqual(disamar_reference.TrendState.improved, outcome.trend.mean_abs_difference);
    try std.testing.expectEqual(disamar_reference.TrendState.improved, outcome.trend.correlation);
}

test "o2a vendor assessment fails when lower-is-better metrics regress" {
    const baseline = makeMetrics(0.04, 0.05, 0.08, 0.99, false);
    const regressed = makeMetrics(0.05, 0.06, 0.09, 0.99, false);
    const outcome = disamar_reference.assessAgainstBaseline(
        regressed,
        baseline,
        .{
            .mean_abs_difference_abs = 1.0e-6,
            .root_mean_square_difference_abs = 1.0e-6,
            .max_abs_difference_abs = 1.0e-6,
            .correlation_abs = 1.0e-6,
        },
        true,
    );

    try std.testing.expectEqual(disamar_reference.AssessmentVerdict.regression_fail, outcome.verdict);
    try std.testing.expectEqual(disamar_reference.TrendState.regressed, outcome.trend.mean_abs_difference);
}

test "o2a vendor assessment fails when higher-is-better metrics regress" {
    const baseline = makeMetrics(0.04, 0.05, 0.08, 0.99, false);
    const regressed = makeMetrics(0.04, 0.05, 0.08, 0.98, false);
    const outcome = disamar_reference.assessAgainstBaseline(
        regressed,
        baseline,
        .{
            .mean_abs_difference_abs = 1.0e-6,
            .root_mean_square_difference_abs = 1.0e-6,
            .max_abs_difference_abs = 1.0e-6,
            .correlation_abs = 1.0e-6,
        },
        true,
    );

    try std.testing.expectEqual(disamar_reference.AssessmentVerdict.regression_fail, outcome.verdict);
    try std.testing.expectEqual(disamar_reference.TrendState.regressed, outcome.trend.correlation);
}

test "o2a vendor assessment fails when morphology metrics regress" {
    const baseline = makeMetrics(0.04, 0.05, 0.08, 0.99, false);
    var regressed = baseline;
    regressed.mid_band_mean_difference = 0.02;

    const outcome = disamar_reference.assessAgainstBaseline(
        regressed,
        baseline,
        .{
            .mean_abs_difference_abs = 1.0e-6,
            .root_mean_square_difference_abs = 1.0e-6,
            .max_abs_difference_abs = 1.0e-6,
            .correlation_abs = 1.0e-6,
        },
        true,
    );

    try std.testing.expectEqual(disamar_reference.AssessmentVerdict.regression_fail, outcome.verdict);
    try std.testing.expectEqual(disamar_reference.TrendState.regressed, outcome.trend.mid_band_mean_difference);
}

test "yaml vendor trend assessment reports bounded drift against the stored vendor baseline" {
    var anchor = try loadBaselineAnchor(std.testing.allocator);
    defer anchor.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 1), anchor.parsed.value.version);
    try std.testing.expect(anchor.parsed.value.guidance.allowed_to_fail);
    try std.testing.expect(anchor.parsed.value.upstream_config.len != 0);
    try std.fs.cwd().access(anchor.parsed.value.reference_path, .{});

    var loaded = try disamar_reference.loadDefaultResolvedCase(std.testing.allocator);
    defer loaded.deinit();

    var disamar_case = try disamar_reference.runResolvedVendorO2AReflectanceCase(
        std.testing.allocator,
        &loaded.resolved,
    );
    defer disamar_case.deinit(std.testing.allocator);

    const current = disamar_reference.computeComparisonMetrics(
        &disamar_case.product,
        disamar_case.reference,
        anchor.parsed.value.zero_tolerance_abs,
    );
    const outcome = disamar_reference.assessAgainstBaseline(
        current,
        anchor.parsed.value.baseline,
        anchor.parsed.value.trend_tolerances,
        anchor.parsed.value.guidance.allowed_to_fail,
    );
    try emitAssessment(std.testing.allocator, anchor.parsed.value, current, outcome);

    try std.testing.expectEqual(@as(u32, 701), current.sample_count);
    try std.testing.expect(current.mean_abs_difference > 0.0);
    try std.testing.expect(current.correlation > 0.95);
}
