const std = @import("std");
const reference_config = @import("config.zig");
const reference_metrics = @import("metrics.zig");
const SpectralGrid = @import("../../input/Spectrum.zig").SpectralGrid;

pub const default_yaml_path = "data/examples/vendor_o2a_parity.yaml";

pub const LoadedResolvedCase = reference_config.LoadedResolvedCase;
pub const RunSummary = reference_config.RunSummary;
pub const ReferenceData = reference_metrics.ReferenceData;
pub const ResolvedVendorO2ACase = reference_metrics.ResolvedVendorO2ACase;
pub const VendorO2AReflectanceCase = reference_metrics.VendorO2AReflectanceCase;
pub const VendorO2APreparedCase = reference_metrics.VendorO2APreparedCase;
pub const ComparisonMetrics = reference_metrics.ComparisonMetrics;
pub const TrendTolerances = reference_metrics.TrendTolerances;
pub const TrendState = reference_metrics.TrendState;
pub const AssessmentVerdict = reference_metrics.AssessmentVerdict;
pub const AssessmentOutcome = reference_metrics.AssessmentOutcome;
pub const RangeExtremum = reference_metrics.RangeExtremum;

pub const ExecutionOverrides = struct {
    spectral_grid: ?SpectralGrid = null,
    line_mixing_factor: ?f64 = null,
    isotopes_sim: ?[]const u8 = null,
    threshold_line_sim: ?f64 = null,
    cutoff_sim_cm1: ?f64 = null,
    adaptive_points_per_fwhm: ?u16 = null,
    adaptive_strong_line_min_divisions: ?u16 = null,
    adaptive_strong_line_max_divisions: ?u16 = null,
};

pub fn loadResolvedCaseFromFile(
    allocator: std.mem.Allocator,
    path: []const u8,
) !LoadedResolvedCase {
    return reference_config.loadResolvedCaseFromFile(allocator, path);
}

pub fn loadDefaultResolvedCase(
    allocator: std.mem.Allocator,
) !LoadedResolvedCase {
    return loadResolvedCaseFromFile(allocator, default_yaml_path);
}

pub fn applyExecutionOverrides(
    resolved: *ResolvedVendorO2ACase,
    overrides: ExecutionOverrides,
) void {
    if (overrides.spectral_grid) |value| resolved.spectral_grid = value;
    if (overrides.line_mixing_factor) |value| resolved.o2.line_mixing_factor = value;
    if (overrides.isotopes_sim) |value| resolved.o2.isotopes_sim = value;
    if (overrides.threshold_line_sim) |value| resolved.o2.threshold_line_sim = value;
    if (overrides.cutoff_sim_cm1) |value| resolved.o2.cutoff_sim_cm1 = value;
    if (overrides.adaptive_points_per_fwhm) |value| {
        resolved.observation.adaptive_reference_grid.points_per_fwhm = value;
    }
    if (overrides.adaptive_strong_line_min_divisions) |value| {
        resolved.observation.adaptive_reference_grid.strong_line_min_divisions = value;
    }
    if (overrides.adaptive_strong_line_max_divisions) |value| {
        resolved.observation.adaptive_reference_grid.strong_line_max_divisions = value;
    }
}

pub fn renderResolvedJson(
    allocator: std.mem.Allocator,
    resolved: *const ResolvedVendorO2ACase,
) ![]u8 {
    return reference_config.renderResolvedJson(allocator, resolved);
}

pub fn runResolvedCaseAndWriteOutputs(
    allocator: std.mem.Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !RunSummary {
    return reference_config.runResolvedCaseAndWriteOutputs(allocator, resolved);
}

pub const runResolvedVendorO2AReflectanceCase = reference_metrics.runResolvedVendorO2AReflectanceCase;
pub const prepareResolvedVendorO2ACase = reference_metrics.prepareResolvedVendorO2ACase;

pub fn runDefaultReflectanceCase(
    allocator: std.mem.Allocator,
    overrides: ExecutionOverrides,
) !VendorO2AReflectanceCase {
    return runReflectanceCaseFromFile(allocator, default_yaml_path, overrides);
}

pub fn runReflectanceCaseFromFile(
    allocator: std.mem.Allocator,
    yaml_path: []const u8,
    overrides: ExecutionOverrides,
) !VendorO2AReflectanceCase {
    var loaded = try loadResolvedCaseFromFile(allocator, yaml_path);
    defer loaded.deinit();
    applyExecutionOverrides(&loaded.resolved, overrides);
    return reference_metrics.runResolvedVendorO2AReflectanceCase(allocator, &loaded.resolved);
}

pub fn prepareDefaultCase(
    allocator: std.mem.Allocator,
    overrides: ExecutionOverrides,
) !VendorO2APreparedCase {
    return prepareCaseFromFile(allocator, default_yaml_path, overrides);
}

pub fn prepareCaseFromFile(
    allocator: std.mem.Allocator,
    yaml_path: []const u8,
    overrides: ExecutionOverrides,
) !VendorO2APreparedCase {
    var loaded = try loadResolvedCaseFromFile(allocator, yaml_path);
    defer loaded.deinit();
    applyExecutionOverrides(&loaded.resolved, overrides);
    return reference_metrics.prepareResolvedVendorO2ACase(allocator, &loaded.resolved);
}

pub fn prepareCase(
    allocator: std.mem.Allocator,
) !VendorO2APreparedCase {
    return prepareDefaultCase(allocator, .{});
}

pub fn loadDisamarReferenceO2ASpectroscopyLineList(
    allocator: std.mem.Allocator,
) !ReferenceData.SpectroscopyLineList {
    var loaded = try loadDefaultResolvedCase(allocator);
    defer loaded.deinit();
    return reference_metrics.loadResolvedO2ASpectroscopyLineList(allocator, loaded.resolved.o2);
}

pub const meanVectorInRange = reference_metrics.meanVectorInRange;
pub const minVectorInRange = reference_metrics.minVectorInRange;
pub const computeComparisonMetrics = reference_metrics.computeComparisonMetrics;
pub const assessAgainstBaseline = reference_metrics.assessAgainstBaseline;
