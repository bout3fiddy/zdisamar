const std = @import("std");
const o2a_vendor = @import("o2a_vendor_reflectance_support.zig");

const BaselineAnchor = struct {
    version: u32,
    scenario: []const u8,
    upstream_config: []const u8,
    reference_path: []const u8,
    zero_tolerance_abs: f64,
    trend_tolerances: struct {
        mean_abs_difference_abs: f64,
        root_mean_square_difference_abs: f64,
        max_abs_difference_abs: f64,
        correlation_abs: f64,
    },
    guidance: struct {
        allowed_to_fail: bool,
        summary: []const u8,
        expect_improvement_when_touched: []const []const u8,
    },
    baseline: o2a_vendor.ComparisonMetrics,
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
        "validation/compatibility/o2a_vendor_forward_reflectance_baseline.json",
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

fn compareLowerIsBetter(current: f64, baseline: f64, tolerance: f64) []const u8 {
    if (current < baseline - tolerance) return "improved";
    if (current > baseline + tolerance) return "regressed";
    return "flat";
}

fn compareHigherIsBetter(current: f64, baseline: f64, tolerance: f64) []const u8 {
    if (current > baseline + tolerance) return "improved";
    if (current < baseline - tolerance) return "regressed";
    return "flat";
}

fn emitAssessment(
    allocator: std.mem.Allocator,
    anchor: BaselineAnchor,
    current: o2a_vendor.ComparisonMetrics,
) !void {
    const assessment = .{
        .scenario = anchor.scenario,
        .upstream_config = anchor.upstream_config,
        .reference_path = anchor.reference_path,
        .status = if (current.exact_match_within_zero_tolerance)
            "pass_exact_zero"
        else
            "allowed_fail_nonzero_delta",
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
        .trend = .{
            .mean_abs_difference = compareLowerIsBetter(
                current.mean_abs_difference,
                anchor.baseline.mean_abs_difference,
                anchor.trend_tolerances.mean_abs_difference_abs,
            ),
            .root_mean_square_difference = compareLowerIsBetter(
                current.root_mean_square_difference,
                anchor.baseline.root_mean_square_difference,
                anchor.trend_tolerances.root_mean_square_difference_abs,
            ),
            .max_abs_difference = compareLowerIsBetter(
                current.max_abs_difference,
                anchor.baseline.max_abs_difference,
                anchor.trend_tolerances.max_abs_difference_abs,
            ),
            .correlation = compareHigherIsBetter(
                current.correlation,
                anchor.baseline.correlation,
                anchor.trend_tolerances.correlation_abs,
            ),
        },
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

test "o2a vendor forward reflectance assessment reports trend against stored baseline" {
    var anchor = try loadBaselineAnchor(std.testing.allocator);
    defer anchor.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 1), anchor.parsed.value.version);
    try std.testing.expect(anchor.parsed.value.guidance.allowed_to_fail);
    try std.testing.expect(anchor.parsed.value.upstream_config.len != 0);
    try std.fs.cwd().access(anchor.parsed.value.reference_path, .{});

    var vendor_case = try o2a_vendor.runVendorO2AReflectanceCase(std.testing.allocator);
    defer vendor_case.deinit(std.testing.allocator);

    const current = o2a_vendor.computeComparisonMetrics(
        &vendor_case.product,
        vendor_case.reference,
        anchor.parsed.value.zero_tolerance_abs,
    );
    try emitAssessment(std.testing.allocator, anchor.parsed.value, current);

    if (!current.exact_match_within_zero_tolerance) {
        return error.TestUnexpectedResult;
    }
}
